import SwiftUI
import UIKit

/// Full-screen touch surface. Layout 1: brake | gear down | gear up | throttle columns (gyro steering).
/// Layout 2: gear buttons on top, handbrake, brake + throttle sliders on the right, on-screen drift wheel bottom-left.
struct Surface: UIViewRepresentable {
    var layout: Int
    var paused: Bool

    func makeUIView(context: Context) -> SurfaceView { SurfaceView() }

    func updateUIView(_ v: SurfaceView, context: Context) {
        v.setMode(layout)
        v.setPaused(paused)
    }
}

private enum Theme {
    static let blue = UIColor(red: 0.56, green: 0.85, blue: 1.0, alpha: 1)
    static let brake = UIColor(red: 0.79, green: 0.28, blue: 0.25, alpha: 1)
    static let gas = UIColor(red: 0.25, green: 0.62, blue: 0.41, alpha: 1)
}

private enum Kind { case brake, gas, gearDown, gearUp, hand, wheel }

private final class Control {
    let kind: Kind
    let bg = CALayer()
    let fill = CALayer()
    var rect = CGRect.zero      // what is drawn
    var hit = CGRect.zero       // where touches count
    var value: CGFloat = 0      // pedals: 0...1
    var down = false            // buttons: pressed
    init(_ kind: Kind) { self.kind = kind }
    var isPedal: Bool { kind == .brake || kind == .gas }
}

final class SurfaceView: UIView {
    private var mode = 0
    private var paused = false
    private var controls: [Control] = []
    private var owner: [UITouch: Control] = [:]

    private var wheelAngle = 0.0            // radians, + = clockwise
    private var wheelTouch: UITouch?
    private var lastTouchAngle = 0.0
    private var returnLink: CADisplayLink?
    private var wheelImageSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private var ctrlColor: UIColor {
        mode == 2 ? UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1)
                  : UIColor(red: 0.102, green: 0.114, blue: 0.133, alpha: 1)
    }

    // MARK: - mode / pause

    func setMode(_ requested: Int) {
        let m = requested == 2 ? 2 : 1
        guard m != mode else { return }
        mode = m
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        owner.removeAll()
        wheelTouch = nil
        wheelAngle = 0
        stopReturn()
        wheelImageSize = .zero

        backgroundColor = m == 2 ? UIColor(red: 0.13, green: 0.145, blue: 0.165, alpha: 1)
                                 : UIColor(red: 0.055, green: 0.063, blue: 0.075, alpha: 1)
        controls = m == 1
            ? [Control(.brake), Control(.gearDown), Control(.gearUp), Control(.gas)]
            : [Control(.gearDown), Control(.gearUp), Control(.hand), Control(.brake), Control(.gas), Control(.wheel)]

        for c in controls {
            if c.kind != .wheel {
                c.bg.backgroundColor = ctrlColor.cgColor
                c.bg.masksToBounds = true
            }
            if c.isPedal {
                c.fill.backgroundColor = (c.kind == .brake ? Theme.brake : Theme.gas).cgColor
                c.bg.addSublayer(c.fill)
            }
            layer.addSublayer(c.bg)
        }
        Hub.shared.setLayout(m)
        setNeedsLayout()
    }

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p {
            owner.removeAll()
            if wheelTouch != nil { wheelTouch = nil; startReturn() }
            sync()
        }
    }

    // MARK: - layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !controls.isEmpty else { return }
        if mode == 1 { layoutColumns() } else { layoutWheelMode() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for c in controls { place(c) }
        CATransaction.commit()
        render()
    }

    private func layoutColumns() {
        let gap: CGFloat = 3
        let w = (bounds.width - 3 * gap) / 4
        for (i, c) in controls.enumerated() {
            c.rect = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
            c.hit = CGRect(x: CGFloat(i) * bounds.width / 4, y: 0, width: bounds.width / 4, height: bounds.height)
        }
    }

    private func layoutWheelMode() {
        let ins = safeAreaInsets
        let left = max(ins.left, 12) + 14
        let right = bounds.width - max(ins.right, 12) - 14
        let top = max(ins.top, 0) + 14
        let bottom = bounds.height - max(ins.bottom, 10) - 10
        let usableH = bottom - top
        let usableW = right - left

        let gw = min(150, usableW * 0.2), gh = usableH * 0.22
        let R = usableH * 0.36
        let hb = usableH * 0.2
        let sw = min(110, usableW * 0.12)
        let th = usableH * 0.62, bh = usableH * 0.48      // brake slider is a bit shorter than throttle
        let wheelCY = bottom - R

        for c in controls {
            switch c.kind {
            case .gearDown: c.rect = CGRect(x: left, y: top, width: gw, height: gh)
            case .gearUp:   c.rect = CGRect(x: right - gw, y: top, width: gw, height: gh)
            case .hand:     c.rect = CGRect(x: left + 2 * R + 16, y: wheelCY - R * 0.35 - hb / 2, width: hb, height: hb)
            case .gas:      c.rect = CGRect(x: right - sw, y: bottom - th, width: sw, height: th)
            case .brake:    c.rect = CGRect(x: right - 2 * sw - 14, y: bottom - bh, width: sw, height: bh)
            case .wheel:    c.rect = CGRect(x: left, y: bottom - 2 * R, width: 2 * R, height: 2 * R)
            }
            c.hit = c.rect.insetBy(dx: -6, dy: -6)
        }
    }

    private func place(_ c: Control) {
        c.bg.bounds = CGRect(origin: .zero, size: c.rect.size)
        c.bg.position = CGPoint(x: c.rect.midX, y: c.rect.midY)
        if c.kind == .wheel {
            if wheelImageSize != c.rect.size {
                wheelImageSize = c.rect.size
                c.bg.contentsScale = traitCollection.displayScale
                c.bg.contents = makeWheel(c.rect.size).cgImage
            }
        } else {
            c.bg.cornerRadius = mode == 2 ? 14 : 0
        }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for c in controls {
            switch c.kind {
            case .brake, .gas:
                let b = c.bg.bounds
                c.fill.frame = CGRect(x: 0, y: b.height * (1 - c.value), width: b.width, height: b.height * c.value)
            case .gearDown, .gearUp, .hand:
                c.bg.backgroundColor = (c.down ? Theme.blue : ctrlColor).cgColor
            case .wheel:
                c.bg.transform = CATransform3DMakeRotation(CGFloat(wheelAngle), 0, 0, 1)
            }
        }
        CATransaction.commit()
    }

    /// Drift-style wheel: all black, three spokes (left, right, bottom), one white stripe at 12 o'clock.
    private func makeWheel(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = size.width / 2
            let ring = R * 0.17
            UIColor.black.setFill()
            UIColor.black.setStroke()
            g.setLineWidth(ring)
            g.strokeEllipse(in: CGRect(x: ring / 2, y: ring / 2, width: size.width - ring, height: size.height - ring))
            g.setLineWidth(R * 0.15)
            for a in [Double.pi, 0.0, Double.pi / 2] {
                g.move(to: c)
                g.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * (R - ring / 2), y: c.y + CGFloat(sin(a)) * (R - ring / 2)))
                g.strokePath()
            }
            let h = R * 0.24
            g.fillEllipse(in: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h))
            UIColor.white.setFill()
            let mw = R * 0.07
            g.fill(CGRect(x: c.x - mw / 2, y: 0, width: mw, height: ring))
        }
    }

    // MARK: - touches (multi-touch; each finger belongs to the control it first touched)

    private func control(at p: CGPoint) -> Control? {
        for c in controls {
            if c.kind == .wheel {
                let dx = p.x - c.rect.midX, dy = p.y - c.rect.midY
                if (dx * dx + dy * dy).squareRoot() <= c.rect.width / 2 * 1.1 { return c }
            } else if c.hit.contains(p) {
                return c
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !paused else { return }
        for t in touches {
            let p = t.location(in: self)
            guard let c = control(at: p) else { continue }
            if c.kind == .wheel {
                if wheelTouch != nil { continue }
                stopReturn()
                wheelTouch = t
                lastTouchAngle = atan2(Double(p.y - c.rect.midY), Double(p.x - c.rect.midX))
            }
            owner[t] = c
        }
        sync()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === wheelTouch { updateWheel(t) }
        sync()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches {
            owner[t] = nil
            if t === wheelTouch {
                wheelTouch = nil
                startReturn()
            }
        }
        sync()
    }

    // MARK: - wheel

    private func wheelLock() -> Double {
        let deg = UserDefaults.standard.object(forKey: "wheelRange") as? Double ?? 120
        return max(20, deg) * .pi / 180
    }

    private func updateWheel(_ t: UITouch) {
        guard let w = controls.first(where: { $0.kind == .wheel }) else { return }
        let p = t.location(in: self)
        let dx = Double(p.x - w.rect.midX), dy = Double(p.y - w.rect.midY)
        if (dx * dx + dy * dy).squareRoot() < Double(w.rect.width) * 0.1 { return }   // too close to the hub
        let a = atan2(dy, dx)
        var d = a - lastTouchAngle
        if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
        lastTouchAngle = a
        let lock = wheelLock()
        wheelAngle = max(-lock, min(lock, wheelAngle + d))
    }

    // After letting go, the wheel springs back to center.
    private func startReturn() {
        stopReturn()
        let link = CADisplayLink(target: self, selector: #selector(returnStep(_:)))
        link.add(to: .main, forMode: .common)
        returnLink = link
    }

    private func stopReturn() {
        returnLink?.invalidate()
        returnLink = nil
    }

    @objc private func returnStep(_ link: CADisplayLink) {
        let step = wheelLock() * 5.0 * link.duration      // full lock back to center in about 0.2 s
        if abs(wheelAngle) <= step {
            wheelAngle = 0
            stopReturn()
        } else {
            wheelAngle -= wheelAngle > 0 ? step : -step
        }
        sync()
    }

    // MARK: - push state to the hub

    private func sync() {
        for c in controls { c.value = 0; c.down = false }
        for (t, c) in owner {
            c.down = true
            if c.isPedal {
                c.value = max(0, min(1, 1 - (t.location(in: self).y - c.rect.minY) / c.rect.height))
            }
        }
        render()

        func find(_ k: Kind) -> Control? { controls.first { $0.kind == k } }
        let hub = Hub.shared
        hub.setPedals(brake: Double(find(.brake)?.value ?? 0), gas: Double(find(.gas)?.value ?? 0))
        hub.setGears(up: find(.gearUp)?.down ?? false, down: find(.gearDown)?.down ?? false)
        hub.setHand(find(.hand)?.down ?? false)
        if mode == 2 { hub.setWheel(wheelAngle / wheelLock()) }
        hub.push()
    }
}
