import AppKit

/// 可复用的卡片组件
/// - init 仅赋值（rule 16），setUp() 显式构建 UI
/// - 卡片：圆角背景 + 标题 + 内容区
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

        // 内边框容器：包裹内容视图，添加独立边框
        let innerBox = NSBox()
        innerBox.boxType = .custom
        innerBox.borderWidth = 0.5
        innerBox.borderColor = NSColor.separatorColor
        innerBox.cornerRadius = 6
        innerBox.contentViewMargins = NSSize(width: 0, height: 0)
        innerBox.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        innerBox.contentView = contentView

        let stack = NSStackView(views: [titleLabel, separator, innerBox])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            innerBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}
