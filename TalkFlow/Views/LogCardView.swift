import AppKit

/// 主窗体底部日志卡片 — 复用 CardView，显示错误/警告计数 + 打开按钮
final class LogCardView: NSView {

    private let logFileIO: LogFileIO
    private var onOpen: (() -> Void)?
    private var summaryLabel: NSTextField?

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        impureSetupUI()
        refreshCounts()
    }

    func refreshCounts() {
        let latestURL = logFileIO.logsDirectory.appendingPathComponent("latest.log")
        let entries = logFileIO.entries(from: latestURL)
        let errors = entries.filter { $0.level == .error }.count
        let warnings = entries.filter { $0.level == .warning }.count

        if errors == 0 && warnings == 0 {
            summaryLabel?.stringValue = "暂无错误"
        } else {
            var parts: [String] = []
            if errors > 0 { parts.append("\(errors) error") }
            if warnings > 0 { parts.append("\(warnings) warning") }
            summaryLabel?.stringValue = parts.joined(separator: " · ")
        }
    }

    private func impureSetupUI() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "暂无错误")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        self.summaryLabel = label

        let openButton = NSButton(title: "打开", target: self, action: #selector(impureOpenTapped))
        openButton.bezelStyle = .rounded
        openButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(openButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            openButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            openButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(equalToConstant: 28),
        ])

        let card = CardView(title: "日志", contentView: contentView)
        card.setUp()
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func impureOpenTapped() {
        onOpen?()
    }
}
