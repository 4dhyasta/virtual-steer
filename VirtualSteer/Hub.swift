import Foundation
import Network
import CoreMotion
import UIKit

/// Dengerin koneksi dari PC (lewat USB / usbmuxd), baca gyro, kirim state ~100x/detik.
/// Format per baris: "steer gas brake gearUp gearDown\n"
final class Hub: ObservableObject {
    static let shared = Hub()

    @Published var connected = false
    @Published var showSettings = false

    private let port: NWEndpoint.Port = 5555
    private var listener: NWListener?
    private var conn: NWConnection?
    private let motion = CMMotionManager()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var offset: Double?
    private var wantCenter = false
    private var steer = 0.0, gas = 0.0, brake = 0.0

    private struct Gear {
        var held = false, sent = false, pending = false, consumed = false
        var work: DispatchWorkItem?
    }
    private var gears = [Gear(), Gear()]          // 0 = up, 1 = down
    private let grace = 0.035                      // tunggu bentar biar tekan barengan ga nge-shift
    private var bothHeld = false
    private var settingsWork: DispatchWorkItem?

    // MARK: - mulai

    func start(force: Bool = false) {
        startListener(force: force)
        startMotion()
    }

    func recenter() { wantCenter = true }

    // MARK: - koneksi

    private func startListener(force: Bool) {
        if listener != nil && !force { return }
        listener?.cancel()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        guard let l = try? NWListener(using: params, on: port) else { return }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self, weak l] st in
            guard let self = self, let l = l, self.listener === l else { return }
            switch st {
            case .failed:
                self.listener = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.startListener(force: false) }
            case .cancelled:
                self.listener = nil
            default: break
            }
        }
        l.start(queue: .main)
        listener = l
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self = self, let c = c, self.conn === c else { return }
            switch st {
            case .ready:
                self.connected = true
                self.wantCenter = true
            case .failed, .cancelled:
                self.connected = false
                self.conn = nil
            default: break
            }
        }
        c.start(queue: .main)
        drain(c)
    }

    // PC ga kirim apa-apa; receive cuma buat tau kapan koneksi putus.
    private func drain(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self, weak c] _, _, done, err in
            guard let self = self, let c = c else { return }
            if done || err != nil { c.cancel() } else { self.drain(c) }
        }
    }

    private func send() {
        guard let c = conn else { return }
        let line = String(format: "%.3f %.3f %.3f %d %d\n",
                          steer, gas, brake, gears[0].sent ? 1 : 0, gears[1].sent ? 1 : 0)
        c.send(content: line.data(using: .utf8), completion: .idempotent)
    }

    // MARK: - steering (gyro)

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self = self, let g = m?.gravity else { return }
            // Pegang landscape kayak setir: sudut vektor gravitasi di bidang layar = sudut putaran.
            let ang = atan2(g.y, g.x) * 180 / .pi
            if self.offset == nil || self.wantCenter {
                self.offset = ang
                self.wantCenter = false
            }
            var d = ang - (self.offset ?? ang)
            d = (d + 540).truncatingRemainder(dividingBy: 360) - 180
            let ud = UserDefaults.standard
            let range = max(10, ud.object(forKey: "range") as? Double ?? 90)
            let sign: Double = ud.bool(forKey: "invert") ? -1 : 1
            let s = max(-1, min(1, sign * d / range))
            self.steer = abs(s) < 0.02 ? 0 : s
            self.send()
        }
    }

    // MARK: - input sentuh

    func setPedals(brake b: Double, gas g: Double) {
        brake = b
        gas = g
        send()
    }

    func setGears(up u: Bool, down d: Bool) {
        for (i, pressed) in [u, d].enumerated() where pressed != gears[i].held {
            if pressed { gearPress(i) } else { gearRelease(i) }
        }
        let both = u && d
        if both != bothHeld {
            bothHeld = both
            settingsWork?.cancel()
            if both {
                let w = DispatchWorkItem { [weak self] in self?.showSettings = true }
                settingsWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
            }
        }
    }

    private func gearPress(_ i: Int) {
        let o = 1 - i
        gears[i].held = true
        haptic.impactOccurred()
        if gears[o].held && !gears[o].sent {   // dua-duanya ditekan barengan = center ulang
            gears[i].work?.cancel()
            gears[o].work?.cancel()
            gears[i].pending = false
            gears[o].pending = false
            gears[i].consumed = true
            gears[o].consumed = true
            wantCenter = true
            return
        }
        gears[i].pending = true
        let w = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.gears[i].pending = false
            if self.gears[i].held && !self.gears[i].consumed {
                self.gears[i].sent = true
                self.send()
            }
        }
        gears[i].work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: w)
    }

    private func gearRelease(_ i: Int) {
        gears[i].held = false
        if gears[i].pending && !gears[i].consumed {   // tap singkat, lepas sebelum grace habis
            gears[i].work?.cancel()
            gears[i].pending = false
            gears[i].sent = true
            send()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.gears[i].sent = false
                self?.send()
            }
        } else {
            gears[i].sent = false
            send()
        }
        gears[i].consumed = false
    }
}
