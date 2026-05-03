import AppKit

/// 可复用的卡片组件
/// - init 仅赋值（rule 16），setUp() 显式构建 UI
/// - 卡片：圆角背景 + 标题 + 内容区（内边框）
final class CardView: NSView {

    private let title: String
    private let contentView: NSView

    /// 构造仅做属性赋值
    init(title: String, contentView: NSView) {
        self.title = title
        self.contentView = contentView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp() {
        impureSetupUI()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // 内边框容器：plain NSView + layer border（约束可正确传播 intrinsic size）
        let innerContainer = NSView()
        innerContainer.wantsLayer = true
        innerContainer.layer?.borderWidth = 0.5
        innerContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        innerContainer.layer?.cornerRadius = 6
        innerContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(contentView)

        // 内容与内边框之间留 padding
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: innerContainer.topAnchor, constant: 10),
            contentView.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor, constant: 12),
            contentView.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor, constant: -12),
            contentView.bottomAnchor.constraint(equalTo: innerContainer.bottomAnchor, constant: -10),
        ])

        let stack = NSStackView(views: [titleLabel, separator, innerContainer])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        // equalSpacing：每个子视图使用自身 intrinsic height，不会被挤压
        stack.distribution = .equalSpacing
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            innerContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}
