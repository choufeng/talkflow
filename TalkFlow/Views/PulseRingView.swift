import AppKit

// MARK: - 录制呼吸光环

/// 霓虹呼吸环：外环脉动 + 中心实心点
/// 参照 TalkShow neon-ring SVG 动画
final class PulseRingView: NSView {

    private let ringLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(ringLayer)
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let r = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // 光环路径
        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: r * 0.67, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        ringLayer.path = ringPath
        ringLayer.fillColor = nil
        ringLayer.strokeColor = NSColor.systemRed.cgColor
        ringLayer.lineWidth = 1.5

        // 光环发光
        ringLayer.shadowColor = NSColor.systemRed.cgColor
        ringLayer.shadowRadius = 4
        ringLayer.shadowOpacity = 0.6
        ringLayer.shadowOffset = .zero

        // 中心实心点
        let dotPath = CGMutablePath()
        dotPath.addArc(center: center, radius: r * 0.25, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        dotLayer.path = dotPath
        dotLayer.fillColor = NSColor.systemRed.cgColor
        dotLayer.strokeColor = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let red = NSColor.systemRed.cgColor
        ringLayer.strokeColor = red
        ringLayer.shadowColor = red
        dotLayer.fillColor = red
    }

    func impureStartAnimation() {
        ringLayer.removeAnimation(forKey: "pulsePath")
        ringLayer.removeAnimation(forKey: "pulseOpacity")

        let r = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        func ringPath(radius: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            return p
        }

        // 半径脉动 — 直接动画 path（等同 SVG animate r）
        let pathAnim = CAKeyframeAnimation(keyPath: "path")
        pathAnim.values = [ringPath(radius: r * 0.58), ringPath(radius: r * 0.75), ringPath(radius: r * 0.58)]
        pathAnim.keyTimes = [0, 0.5, 1]
        pathAnim.duration = 1.2
        pathAnim.repeatCount = .infinity
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // 透明度脉动
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [1.0, 0.5, 1.0]
        opacityAnim.keyTimes = [0, 0.5, 1]
        opacityAnim.duration = 1.2
        opacityAnim.repeatCount = .infinity
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        ringLayer.add(pathAnim, forKey: "pulsePath")
        ringLayer.add(opacityAnim, forKey: "pulseOpacity")
    }

    func impureStopAnimation() {
        ringLayer.removeAllAnimations()
    }
}
