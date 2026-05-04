import AppKit

/// 日志详情 — 显示选中条目的完整信息
final class LogEntryDetailView: NSView {

    private let levelBadge = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let messageTextView = NSTextView()
    private var placeholderLabel: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        impureSetupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(entry: LogEntry?, sourceFile: String = "") {
        subviews.forEach { $0.isHidden = entry == nil }
        placeholderLabel?.isHidden = entry != nil

        guard let entry else { return }

        levelBadge.stringValue = entry.level.rawValue.uppercased()
        levelBadge.textColor = colorForLevel(entry.level)
        levelBadge.font = NSFont.boldSystemFont(ofSize: 11)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        timestampLabel.stringValue = fmt.string(from: entry.timestamp)
        timestampLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor

        metaLabel.stringValue = "标签: [\(entry.tag)]  |  来源: \(sourceFile)"
        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = .tertiaryLabelColor

        messageTextView.string = entry.message
    }

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let placeholder = NSTextField(labelWithString: "选择一条日志查看详情")
        placeholder.font = NSFont.systemFont(ofSize: 14)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        self.placeholderLabel = placeholder

        levelBadge.translatesAutoresizingMaskIntoConstraints = false
        levelBadge.isHidden = true
        addSubview(levelBadge)

        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.isHidden = true
        addSubview(timestampLabel)

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.isHidden = true
        addSubview(metaLabel)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = true
        addSubview(separator)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true

        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        messageTextView.textColor = .labelColor
        messageTextView.backgroundColor = .controlBackgroundColor
        messageTextView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = messageTextView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),

            levelBadge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            levelBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            timestampLabel.topAnchor.constraint(equalTo: levelBadge.bottomAnchor, constant: 8),
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            metaLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            separator.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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
