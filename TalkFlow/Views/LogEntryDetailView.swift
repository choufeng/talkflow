import AppKit

/// 日志详情 — 显示选中条目的完整信息
final class LogEntryDetailView: NSView {

    private var placeholderLabel: NSTextField?
    private var detailContainer: NSView?
    private var levelBadge: NSTextField?
    private var timestampLabel: NSTextField?
    private var metaLabel: NSTextField?
    private var messageTextView: NSTextView?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp() {
        impureSetupUI()
    }

    func show(entry: LogEntry?, sourceFile: String = "") {
        guard let entry else {
            placeholderLabel?.isHidden = false
            detailContainer?.isHidden = true
            return
        }

        placeholderLabel?.isHidden = true
        detailContainer?.isHidden = false

        levelBadge?.stringValue = entry.level.rawValue.uppercased()
        levelBadge?.textColor = colorForLevel(entry.level)
        levelBadge?.font = NSFont.boldSystemFont(ofSize: 11)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        timestampLabel?.stringValue = fmt.string(from: entry.timestamp)
        timestampLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timestampLabel?.textColor = .secondaryLabelColor

        metaLabel?.stringValue = "标签: [\(entry.tag)]  |  来源: \(sourceFile)"
        metaLabel?.font = NSFont.systemFont(ofSize: 11)
        metaLabel?.textColor = .tertiaryLabelColor

        messageTextView?.string = entry.message
    }

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // 占位文字
        let placeholder = NSTextField(labelWithString: "选择一条日志查看详情")
        placeholder.font = NSFont.systemFont(ofSize: 14)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        self.placeholderLabel = placeholder

        // 详情容器（默认隐藏）
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        addSubview(container)
        self.detailContainer = container

        // 级别 badge
        let badge = NSTextField(labelWithString: "")
        badge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)
        self.levelBadge = badge

        // 时间戳
        let ts = NSTextField(labelWithString: "")
        ts.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(ts)
        self.timestampLabel = ts

        // 元信息
        let meta = NSTextField(labelWithString: "")
        meta.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(meta)
        self.metaLabel = meta

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        // 消息体
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .controlBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        container.addSubview(scrollView)
        self.messageTextView = textView

        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),

            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            ts.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 8),
            ts.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            meta.topAnchor.constraint(equalTo: ts.bottomAnchor, constant: 4),
            meta.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            separator.topAnchor.constraint(equalTo: meta.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
    }

    private func colorForLevel(_ level: LogLevel) -> NSColor {
        switch level {
        case .debug:   return .tertiaryLabelColor
        case .info:    return .systemBlue
        case .warning: return .systemOrange
        case .error:   return .systemRed
        }
    }
}
