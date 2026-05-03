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

    func startAnimation() {
        ringLayer.removeAnimation(forKey: "pulseRadius")
        ringLayer.removeAnimation(forKey: "pulseOpacity")

        // 半径脉动
        let radiusAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        radiusAnim.values = [1.0, 1.28, 1.0]
        radiusAnim.keyTimes = [0, 0.5, 1]
        radiusAnim.duration = 1.2
        radiusAnim.repeatCount = .infinity
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // 透明度脉动
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [1.0, 0.5, 1.0]
        opacityAnim.keyTimes = [0, 0.5, 1]
        opacityAnim.duration = 1.2
        opacityAnim.repeatCount = .infinity
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        ringLayer.add(radiusAnim, forKey: "pulseRadius")
        ringLayer.add(opacityAnim, forKey: "pulseOpacity")
    }

    func stopAnimation() {
        ringLayer.removeAllAnimations()
    }
}
