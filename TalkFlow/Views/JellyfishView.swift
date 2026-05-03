import AppKit

// MARK: - 转写中水母动画

/// 水母状呼吸动画 — 钟体脉动 + 触须飘摇
/// 参照 TalkShow jellyfish SVG 动画
final class JellyfishView: NSView {

    // 图层
    private let bellLayer = CAShapeLayer()       // 钟体
    private let innerGlowLayer = CAShapeLayer()   // 内部光晕椭圆
    private var tentacleLayers = [CAShapeLayer]() // 5 条触须

    // 颜色
    private let cyan = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 1.0).cgColor
    private let cyanGlow = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 0.15).cgColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // 钟体
        bellLayer.fillColor = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 0.08).cgColor
        bellLayer.strokeColor = cyan
        bellLayer.lineWidth = 1.2
        bellLayer.shadowColor = cyan
        bellLayer.shadowRadius = 2.5
        bellLayer.shadowOpacity = 1.0
        bellLayer.shadowOffset = .zero
        layer?.addSublayer(bellLayer)

        // 内部光晕
        innerGlowLayer.fillColor = cyanGlow
        innerGlowLayer.strokeColor = nil
        innerGlowLayer.shadowColor = cyan
        innerGlowLayer.shadowRadius = 1.5
        innerGlowLayer.shadowOpacity = 1.0
        innerGlowLayer.shadowOffset = .zero
        layer?.addSublayer(innerGlowLayer)

        // 5 条触须
        let tentacleOpacities: [Float] = [0.5, 0.7, 0.8, 0.7, 0.5]
        let tentacleWidths: [CGFloat] = [0.8, 1.0, 1.2, 1.0, 0.8]
        for i in 0..<5 {
            let t = CAShapeLayer()
            t.fillColor = nil
            t.strokeColor = cyan
            t.lineWidth = tentacleWidths[i]
            t.lineCap = .round
            t.opacity = tentacleOpacities[i]
            t.shadowColor = cyan
            t.shadowRadius = 1.5
            t.shadowOpacity = 1.0
            t.shadowOffset = .zero
            tentacleLayers.append(t)
            layer?.addSublayer(t)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        // 坐标系：0,0 左上 → 右下，viewBox 0 0 28 28
        let sx = w / 28.0
        let sy = h / 28.0

        // 绘制静态路径
        updateBell(cx: 14, cy: 16, topY: 5, scaleX: sx, scaleY: sy)
        updateInnerGlow(cx: 14, cy: 12, rx: 4, ry: 3, scaleX: sx, scaleY: sy)
        updateTentacles(scaleX: sx, scaleY: sy)
    }

    private func transform(_ x: CGFloat, _ y: CGFloat, sx: CGFloat, sy: CGFloat) -> CGPoint {
        CGPoint(x: x * sx, y: y * sy)
    }

    // MARK: - 钟体路径

    private func bellPath(cx: CGFloat, cy: CGFloat, topY: CGFloat, leftX: CGFloat, midX: CGFloat, rightX: CGFloat, bottomMidy: CGFloat) -> CGPath {
        let path = CGMutablePath()
        // M leftX,cy Q leftX,topY midX,topY
        path.move(to: CGPoint(x: leftX, y: cy))
        path.addQuadCurve(to: CGPoint(x: midX, y: topY), control: CGPoint(x: leftX, y: topY))
        // Q rightX,topY rightX,cy
        path.addQuadCurve(to: CGPoint(x: rightX, y: cy), control: CGPoint(x: rightX, y: topY))
        // Q bottomOuterX,bottomMidy midX,bottomInnerY
        let bottomOuterX = cx + (rightX - cx) * 0.56
        let bottomInnerY = cy + 1
        path.addQuadCurve(to: CGPoint(x: midX, y: bottomInnerY), control: CGPoint(x: bottomOuterX, y: bottomMidy))
        // Q bottomInnerX,bottomMidy leftX,cy
        let bottomInnerX = cx - (rightX - cx) * 0.56
        path.addQuadCurve(to: CGPoint(x: leftX, y: cy), control: CGPoint(x: bottomInnerX, y: bottomMidy))
        path.closeSubpath()
        return path
    }

    private func updateBell(cx: CGFloat, cy: CGFloat, topY: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        let leftX = cx - 9
        let midX = cx
        let rightX = cx + 9
        let bottomMidy = cy + 3

        bellLayer.path = bellPath(cx: cx * scaleX, cy: cy * scaleY,
                                   topY: topY * scaleY,
                                   leftX: leftX * scaleX,
                                   midX: midX * scaleX,
                                   rightX: rightX * scaleX,
                                   bottomMidy: bottomMidy * scaleY)
    }

    // MARK: - 内部光晕

    private func ellipsePath(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    private func updateInnerGlow(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        innerGlowLayer.path = ellipsePath(cx: cx * scaleX, cy: cy * scaleY, rx: rx * scaleX, ry: ry * scaleY)
    }

    // MARK: - 触须路径

    private func tentaclePath(x1: CGFloat, y1: CGFloat, _ cpx: CGFloat, _ cpy: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: cpx, y: cpy))
        return path
    }

    private func updateTentacles(scaleX: CGFloat, scaleY: CGFloat) {
        let tentacleDefs: [(x1: CGFloat, y1: CGFloat, cpx: CGFloat, cpy: CGFloat, x2: CGFloat, y2: CGFloat)] = [
            (8, 16.5, 6, 22, 8, 27),
            (11, 17, 9, 23, 10, 28),
            (14, 17.5, 13, 24, 14, 28),
            (17, 17, 19, 23, 18, 28),
            (20, 16.5, 22, 22, 20, 27),
        ]
        for (i, def) in tentacleDefs.enumerated() {
            tentacleLayers[i].path = tentaclePath(
                x1: def.x1 * scaleX, y1: def.y1 * scaleY,
                def.cpx * scaleX, def.cpy * scaleY,
                def.x2 * scaleX, def.y2 * scaleY
            )
        }
    }

    // MARK: - 动画

    func startAnimation() {
        stopAnimation()

        let sx = bounds.width / 28.0
        let sy = bounds.height / 28.0

        // --- 钟体呼吸（路径形变） ---
        let bellAnim = CAKeyframeAnimation(keyPath: "path")
        bellAnim.values = [
            bellPath(cx: 14*sx, cy: 16*sy, topY: 5*sy, leftX: 5*sx, midX: 14*sx, rightX: 23*sx, bottomMidy: 19*sy),
            bellPath(cx: 14*sx, cy: 15*sy, topY: 7*sy, leftX: 6*sx, midX: 14*sx, rightX: 23*sx, bottomMidy: 17*sy),
            bellPath(cx: 14*sx, cy: 16*sy, topY: 5*sy, leftX: 5*sx, midX: 14*sx, rightX: 23*sx, bottomMidy: 19*sy),
        ]
        bellAnim.keyTimes = [0, 0.5, 1]
        bellAnim.duration = 2
        bellAnim.repeatCount = .infinity
        bellAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bellLayer.add(bellAnim, forKey: "breathe")

        // --- 内部光晕脉动（纵轴缩放） ---
        let glowAnim = CAKeyframeAnimation(keyPath: "transform.scale.y")
        glowAnim.values = [1.0, 0.67, 1.0]
        glowAnim.keyTimes = [0, 0.5, 1]
        glowAnim.duration = 2
        glowAnim.repeatCount = .infinity
        glowAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        innerGlowLayer.add(glowAnim, forKey: "pulse")

        // --- 触须飘摇 ---
        let tentacleKeyframes: [[(cpx: CGFloat, cpy: CGFloat, x2: CGFloat, y2: CGFloat)]] = [
            // Rest → Sway → Rest
            [(6, 22, 8, 27), (5, 21, 7, 26), (6, 22, 8, 27)],           // tentacle 0
            [(9, 23, 10, 28), (8, 22, 9, 27), (9, 23, 10, 28)],         // tentacle 1
            [(13, 24, 14, 28), (12, 23, 13, 27), (13, 24, 14, 28)],     // tentacle 2
            [(19, 23, 18, 28), (20, 22, 19, 27), (19, 23, 18, 28)],     // tentacle 3
            [(22, 22, 20, 27), (23, 21, 21, 26), (22, 22, 20, 27)],     // tentacle 4
        ]
        let tentacleDurations: [CFTimeInterval] = [2.5, 2.2, 2.0, 2.2, 2.5]
        let tentacleDefs: [(x1: CGFloat, y1: CGFloat)] = [
            (8, 16.5), (11, 17), (14, 17.5), (17, 17), (20, 16.5),
        ]

        for i in 0..<5 {
            let def = tentacleDefs[i]
            let kf = tentacleKeyframes[i]
            let durations = tentacleDurations[i]

            let paths = kf.map { kf in
                tentaclePath(x1: def.x1 * sx, y1: def.y1 * sy,
                             kf.cpx * sx, kf.cpy * sy,
                             kf.x2 * sx, kf.y2 * sy)
            }
            let anim = CAKeyframeAnimation(keyPath: "path")
            anim.values = paths
            anim.keyTimes = [0, 0.5, 1]
            anim.duration = durations
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tentacleLayers[i].add(anim, forKey: "sway")
        }

        // --- 整体上下浮动 ---
        let swimAnim = CAKeyframeAnimation(keyPath: "transform.translation.y")
        swimAnim.values = [0, -2, 0]
        swimAnim.keyTimes = [0, 0.5, 1]
        swimAnim.duration = 2
        swimAnim.repeatCount = .infinity
        swimAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(swimAnim, forKey: "swim")
    }

    func stopAnimation() {
        bellLayer.removeAllAnimations()
        innerGlowLayer.removeAllAnimations()
        tentacleLayers.forEach { $0.removeAllAnimations() }
        layer?.removeAllAnimations()
    }
}
