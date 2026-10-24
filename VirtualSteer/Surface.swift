import SwiftUI
import UIKit

/// Empat kolom satu layar: rem | gear down | gear up | gas. Ga ada gambar/tulisan.
struct Surface: UIViewRepresentable {
    func makeUIView(context: Context) -> SurfaceView { SurfaceView() }
    func updateUIView(_ uiView: SurfaceView, context: Context) {}
}

final class SurfaceView: UIView {
    private let gap: CGFloat = 3
    private let dim = UIColor(red: 0.102, green: 0.114, blue: 0.133, alpha: 1)
    private let blue = UIColor(red: 0.56, green: 0.85, blue: 1.0, alpha: 1)
    private let zones = (0..<4).map { _ in CALayer() }
    private let fills = (0..<4).map { _ in CALayer() }

    private var owner: [UITouch: Int] = [:]
    private var values = [CGFloat](repeating: 0, count: 4)
    private var pressed = [Bool](repeating: false, count: 4)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.055, green: 0.063, blue: 0.075, alpha: 1)
        let fillColors: [UIColor?] = [
            UIColor(red: 0.79, green: 0.28, blue: 0.25, alpha: 1), nil, nil,
            UIColor(red: 0.25, green: 0.62, blue: 0.41, alpha: 1),
        ]
        for i in 0..<4 {
            zones[i].backgroundColor = dim.cgColor
            zones[i].masksToBounds = true
            layer.addSublayer(zones[i])
            if let c = fillColors[i] {
                fills[i].backgroundColor = c.cgColor
                zones[i].addSublayer(fills[i])
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = (bounds.width - 3 * gap) / 4
        for i in 0..<4 {
            zones[i].frame = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
        }
        CATransaction.commit()
        render()
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<4 {
            let b = zones[i].bounds
            if i == 0 || i == 3 {
                fills[i].frame = CGRect(x: 0, y: b.height * (1 - values[i]), width: b.width, height: b.height * values[i])
            } else {
                zones[i].backgroundColor = (pressed[i] ? blue : dim).cgColor
            }
        }
        CATransaction.commit()
    }

    // MARK: - multitouch: tiap jari "dimiliki" kolom tempat dia pertama nempel

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let x = t.location(in: self).x
            owner[t] = min(3, max(0, Int(x / (bounds.width / 4))))
        }
        sync()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { sync() }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { owner[t] = nil }
        sync()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { owner[t] = nil }
        sync()
    }

    private func sync() {
        values = [0, 0, 0, 0]
        pressed = [false, false, false, false]
        for (t, z) in owner {
            pressed[z] = true
            if z == 0 || z == 3 {
                values[z] = max(0, min(1, 1 - t.location(in: self).y / bounds.height))
            }
        }
        render()
        let hub = Hub.shared
        hub.setPedals(brake: Double(values[0]), gas: Double(values[3]))
        hub.setGears(up: pressed[2], down: pressed[1])
    }
}
