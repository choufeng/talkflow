import AppKit

// MARK: - 转写中水母动画

/// 水母状呼吸动画 — 钟体脉动 + 触须飘摇
/// 参照 TalkShow jellyfish SVG 动画
final class JellyfishView: NSView {

    // 图层
    private let bellLayer = CAShapeLayer()       // 钟体
    private let innerGlowLayer = CAShapeLayer()   // 内部光晕椭圆
    private var tentacleLayers = [CAShapeLayer]() // 5 条触须

    // 颜色 — 跟随系统强调色
    private var accentColor: NSColor { .controlAccentColor }

    private func applyAccentColors() {
        let accent = accentColor
        let accentCG = accent.cgColor
        let glowCG = accent.withAlphaComponent(0.15).cgColor
        let fillCG = accent.withAlphaComponent(0.08).cgColor

        bellLayer.fillColor = fillCG
        bellLayer.strokeColor = accentCG
        bellLayer.shadowColor = accentCG
        innerGlowLayer.fillColor = glowCG
        innerGlowLayer.shadowColor = accentCG
        tentacleLayers.forEach {
            $0.strokeColor = accentCG
            $0.shadowColor = accentCG
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // 钟体
        bellLayer.lineWidth = 1.2
        bellLayer.shadowRadius = 2.5
        bellLayer.shadowOpacity = 1.0
        bellLayer.shadowOffset = .zero
        layer?.addSublayer(bellLayer)

        // 内部光晕
        innerGlowLayer.strokeColor = nil
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
            t.lineWidth = tentacleWidths[i]
            t.lineCap = .round
            t.opacity = tentacleOpacities[i]
            t.shadowRadius = 1.5
            t.shadowOpacity = 1.0
            t.shadowOffset = .zero
            tentacleLayers.append(t)
            layer?.addSublayer(t)
        }

        applyAccentColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccentColors()
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        // 坐标系转换：SVG Y 朝下，CALayer Y 朝上 → 翻转 Y
        let sx = w / 28.0
        let sy = h / 28.0

        // 绘制静态路径（SVG 坐标 → CALayer 翻转 Y）
        updateBell(scaleX: sx, scaleY: sy)
        updateInnerGlow(scaleX: sx, scaleY: sy)
        updateTentacles(scaleX: sx, scaleY: sy)
    }

    /// SVG Y 坐标转换为 CALayer Y（翻转）
    private func cal(_ svgY: CGFloat, scaleY: CGFloat) -> CGFloat {
        bounds.height - svgY * scaleY
    }

    // MARK: - 钟体路径

    /// 参数均为 SVG 坐标（未经翻转）
    private func bellPathSVG(cx: CGFloat, cy: CGFloat, topY: CGFloat, leftX: CGFloat, midX: CGFloat, rightX: CGFloat, bottomMidy: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: leftX, y: cy))
        path.addQuadCurve(to: CGPoint(x: midX, y: topY), control: CGPoint(x: leftX, y: topY))
        path.addQuadCurve(to: CGPoint(x: rightX, y: cy), control: CGPoint(x: rightX, y: topY))
        let bottomOuterX = cx + (rightX - cx) * 0.56
        let bottomInnerY = cy + 1
        path.addQuadCurve(to: CGPoint(x: midX, y: bottomInnerY), control: CGPoint(x: bottomOuterX, y: bottomMidy))
        let bottomInnerX = cx - (rightX - cx) * 0.56
        path.addQuadCurve(to: CGPoint(x: leftX, y: cy), control: CGPoint(x: bottomInnerX, y: bottomMidy))
        path.closeSubpath()
        return path
    }

    private func updateBell(scaleX: CGFloat, scaleY: CGFloat) {
        let fl = { (svgY: CGFloat) -> CGFloat in self.cal(svgY, scaleY: scaleY) }
        let sc = { (svgX: CGFloat) -> CGFloat in svgX * scaleX }

        let leftX = sc(5)
        let midX = sc(14)
        let rightX = sc(23)
        let cx = sc(14)
        let cy = fl(16)
        let topY = fl(5)
        let bottomMidy = fl(19)

        bellLayer.path = bellPathSVG(cx: cx, cy: cy, topY: topY,
                                      leftX: leftX, midX: midX, rightX: rightX,
                                      bottomMidy: bottomMidy)
    }

    // MARK: - 内部光晕

    private func updateInnerGlow(scaleX: CGFloat, scaleY: CGFloat) {
        let cx = 14 * scaleX
        let cy = cal(12, scaleY: scaleY)
        let rx = 4 * scaleX
        let ry = 3 * scaleY
        innerGlowLayer.path = CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    // MARK: - 触须路径

    private func tentaclePathSVG(x1: CGFloat, y1: CGFloat, _ cpx: CGFloat, _ cpy: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: cpx, y: cpy))
        return path
    }

    private func updateTentacles(scaleX: CGFloat, scaleY: CGFloat) {
        let fl = { (svgY: CGFloat) -> CGFloat in self.cal(svgY, scaleY: scaleY) }
        let sc = { (svgX: CGFloat) -> CGFloat in svgX * scaleX }

        let tentacleDefs: [(x1: CGFloat, y1: CGFloat, cpx: CGFloat, cpy: CGFloat, x2: CGFloat, y2: CGFloat)] = [
            (8, 16.5, 6, 22, 8, 27),
            (11, 17, 9, 23, 10, 28),
            (14, 17.5, 13, 24, 14, 28),
            (17, 17, 19, 23, 18, 28),
            (20, 16.5, 22, 22, 20, 27),
        ]
        for (i, def) in tentacleDefs.enumerated() {
            tentacleLayers[i].path = tentaclePathSVG(
                x1: sc(def.x1), y1: fl(def.y1),
                sc(def.cpx), fl(def.cpy),
                sc(def.x2), fl(def.y2)
            )
        }
    }

    // MARK: - 动画

    func impureStartAnimation() {
        impureStopAnimation()

        let sx = bounds.width / 28.0
        let sy = bounds.height / 28.0
        let fl = { (svgY: CGFloat) -> CGFloat in self.cal(svgY, scaleY: sy) }
        let sc = { (svgX: CGFloat) -> CGFloat in svgX * sx }

        // --- 钟体呼吸 ---
        let bellAnim = CAKeyframeAnimation(keyPath: "path")
        bellAnim.values = [
            bellPathSVG(cx: sc(14), cy: fl(16), topY: fl(5), leftX: sc(5), midX: sc(14), rightX: sc(23), bottomMidy: fl(19)),
            bellPathSVG(cx: sc(14), cy: fl(15), topY: fl(7), leftX: sc(6), midX: sc(14), rightX: sc(23), bottomMidy: fl(17)),
            bellPathSVG(cx: sc(14), cy: fl(16), topY: fl(5), leftX: sc(5), midX: sc(14), rightX: sc(23), bottomMidy: fl(19)),
        ]
        bellAnim.keyTimes = [0, 0.5, 1]
        bellAnim.duration = 2
        bellAnim.repeatCount = .infinity
        bellAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bellLayer.add(bellAnim, forKey: "breathe")

        // --- 内部光晕脉动 ---
        let glowAnim = CAKeyframeAnimation(keyPath: "transform.scale.y")
        glowAnim.values = [1.0, 0.67, 1.0]
        glowAnim.keyTimes = [0, 0.5, 1]
        glowAnim.duration = 2
        glowAnim.repeatCount = .infinity
        glowAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        innerGlowLayer.add(glowAnim, forKey: "pulse")

        // --- 触须飘摇 ---
        let tentacleDefs: [(x1: CGFloat, y1: CGFloat)] = [
            (8, 16.5), (11, 17), (14, 17.5), (17, 17), (20, 16.5),
        ]
        let tentacleKeyframes: [[(cpx: CGFloat, cpy: CGFloat, x2: CGFloat, y2: CGFloat)]] = [
            [(6, 22, 8, 27), (5, 21, 7, 26), (6, 22, 8, 27)],
            [(9, 23, 10, 28), (8, 22, 9, 27), (9, 23, 10, 28)],
            [(13, 24, 14, 28), (12, 23, 13, 27), (13, 24, 14, 28)],
            [(19, 23, 18, 28), (20, 22, 19, 27), (19, 23, 18, 28)],
            [(22, 22, 20, 27), (23, 21, 21, 26), (22, 22, 20, 27)],
        ]
        let tentacleDurations: [CFTimeInterval] = [2.5, 2.2, 2.0, 2.2, 2.5]

        for i in 0..<5 {
            let def = tentacleDefs[i]
            let kf = tentacleKeyframes[i]
            let durations = tentacleDurations[i]

            let paths = kf.map { kf in
                tentaclePathSVG(x1: sc(def.x1), y1: fl(def.y1),
                                sc(kf.cpx), fl(kf.cpy),
                                sc(kf.x2), fl(kf.y2))
            }
            let anim = CAKeyframeAnimation(keyPath: "path")
            anim.values = paths
            anim.keyTimes = [0, 0.5, 1]
            anim.duration = durations
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tentacleLayers[i].add(anim, forKey: "sway")
        }

        // --- 整体上下浮动（macOS CALayer Y 轴朝上，正值 = 上浮） ---
        let swimAnim = CAKeyframeAnimation(keyPath: "transform.translation.y")
        swimAnim.values = [0, 2, 0]
        swimAnim.keyTimes = [0, 0.5, 1]
        swimAnim.duration = 2
        swimAnim.repeatCount = .infinity
        swimAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(swimAnim, forKey: "swim")
    }

    func impureStopAnimation() {
        bellLayer.removeAllAnimations()
        innerGlowLayer.removeAllAnimations()
        tentacleLayers.forEach { $0.removeAllAnimations() }
        layer?.removeAllAnimations()
    }
}
