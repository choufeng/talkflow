import AppKit
import ObjectiveC

/// 日志列表 — 左侧：文件切换 + 级别筛选 + NSTableView + checkbox + 复制
final class LogEntryListView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    private var entries: [LogEntry] = []
    private var filteredEntries: [LogEntry] = []
    private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    private var checkedIndices: Set<Int> = []
    private var onSelectionChanged: ((LogEntry, String) -> Void)?
    private var logFileIO: LogFileIO
    private var currentFileName: String = "latest.log"

    private let filePopup = NSPopUpButton()
    private let tableView = NSTableView()
    private let copyButton = NSButton()
    private let selectAllButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "共 0 条")

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
        super.init(frame: .zero)
        impureSetupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp(onSelectionChanged: @escaping (LogEntry, String) -> Void) {
        self.onSelectionChanged = onSelectionChanged
        impureRefreshFileList()
        impureLoadCurrentFile()
    }

    func refresh() {
        impureLoadCurrentFile()
    }

    private func impureLoadCurrentFile() {
        let url = logFileIO.logsDirectory.appendingPathComponent(currentFileName)
        entries = logFileIO.entries(from: url)
        checkedIndices = []
        impureApplyFilter()
    }

    private func impureApplyFilter() {
        filteredEntries = entries.filter { selectedLevels.contains($0.level) }
        countLabel.stringValue = "共 \(filteredEntries.count) 条"
        tableView.reloadData()
        impureUpdateCopyButton()
    }

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        filePopup.target = self
        filePopup.action = #selector(impureFileChanged)
        filePopup.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(filePopup)

        let levelStack = NSStackView()
        levelStack.orientation = .horizontal
        levelStack.spacing = 4
        levelStack.translatesAutoresizingMaskIntoConstraints = false

        for level in LogLevel.allCases {
            let btn = NSButton()
            btn.title = level.rawValue.capitalized
            btn.bezelStyle = .inline
            btn.setButtonType(.toggle)
            btn.state = .on
            btn.target = self
            btn.action = #selector(impureLevelToggled(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false

            objc_setAssociatedObject(btn, &AssociatedKeys.level, level, .OBJC_ASSOCIATION_RETAIN)
            levelStack.addArrangedSubview(btn)
        }
        toolbar.addSubview(levelStack)

        NSLayoutConstraint.activate([
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            filePopup.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            filePopup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            levelStack.leadingAnchor.constraint(equalTo: filePopup.trailingAnchor, constant: 12),
            levelStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])

        // TableView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let columns: [(String, CGFloat)] = [
            ("check", 24), ("level", 24), ("time", 65), ("tag", 80), ("message", 200),
        ]
        for (id, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.width = width
            tableView.addTableColumn(col)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = nil
        tableView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = tableView

        // 底部工具栏
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        copyButton.title = "📋 复制勾选"
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false
        copyButton.target = self
        copyButton.action = #selector(impureCopySelected)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(copyButton)

        selectAllButton.title = "☐ 全选"
        selectAllButton.bezelStyle = .inline
        selectAllButton.target = self
        selectAllButton.action = #selector(impureToggleSelectAll)
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(selectAllButton)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(countLabel)

        NSLayoutConstraint.activate([
            bottomBar.heightAnchor.constraint(equalToConstant: 32),

            copyButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 4),
            copyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            selectAllButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            selectAllButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            countLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])

        addSubview(toolbar)
        addSubview(scrollView)
        addSubview(bottomBar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bottomBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    @objc private func impureFileChanged() {
        currentFileName = filePopup.titleOfSelectedItem ?? "latest.log"
        impureLoadCurrentFile()
    }

    @objc private func impureLevelToggled(_ sender: NSButton) {
        guard let level = objc_getAssociatedObject(sender, &AssociatedKeys.level) as? LogLevel else { return }
        if sender.state == .on {
            selectedLevels.insert(level)
        } else {
            selectedLevels.remove(level)
        }
        impureApplyFilter()
    }

    @objc private func impureCopySelected() {
        let selected = checkedIndices.sorted().compactMap { i -> LogEntry? in
            guard i < filteredEntries.count else { return nil }
            return filteredEntries[i]
        }

        let text = selected.map { entry in
            let ts = timeFormatter.string(from: entry.timestamp)
            return "[\(ts)] [\(entry.level.rawValue.uppercased())] [\(entry.tag)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func impureToggleSelectAll() {
        if checkedIndices.count == filteredEntries.count {
            checkedIndices = []
            selectAllButton.title = "☐ 全选"
        } else {
            checkedIndices = Set(0..<filteredEntries.count)
            selectAllButton.title = "☑ 取消全选"
        }
        impureUpdateCopyButton()
        tableView.reloadData()
    }

    private func impureRefreshFileList() {
        filePopup.removeAllItems()
        for file in logFileIO.logFiles() {
            filePopup.addItem(withTitle: file.lastPathComponent)
        }
        filePopup.selectItem(withTitle: "latest.log")
    }

    private func impureUpdateCopyButton() {
        let count = checkedIndices.count
        copyButton.title = count > 0 ? "📋 复制 (\(count))" : "📋 复制勾选"
        copyButton.isEnabled = count > 0
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredEntries.count else { return nil }
        let entry = filteredEntries[row]

        switch tableColumn?.identifier.rawValue {
        case "check":
            let btn = NSButton()
            btn.setButtonType(.switch)
            btn.state = checkedIndices.contains(row) ? .on : .off
            btn.target = self
            btn.action = #selector(impureCheckToggled(_:))
            btn.tag = row
            return btn

        case "level":
            let tf = NSTextField(labelWithString: levelEmoji(entry.level))
            tf.font = NSFont.systemFont(ofSize: 11)
            return tf

        case "time":
            let tf = NSTextField(labelWithString: timeFormatter.string(from: entry.timestamp))
            tf.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            tf.textColor = .secondaryLabelColor
            return tf

        case "tag":
            let tf = NSTextField(labelWithString: "[\(entry.tag)]")
            tf.font = NSFont.systemFont(ofSize: 11)
            tf.textColor = .secondaryLabelColor
            tf.lineBreakMode = .byTruncatingTail
            return tf

        case "message":
            let tf = NSTextField(labelWithString: entry.message)
            tf.font = NSFont.systemFont(ofSize: 11)
            tf.lineBreakMode = .byTruncatingTail
            return tf

        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredEntries.count else { return }
        let entry = filteredEntries[row]
        onSelectionChanged?(entry, currentFileName)
    }

    @objc private func impureCheckToggled(_ sender: NSButton) {
        let row = sender.tag
        if sender.state == .on {
            checkedIndices.insert(row)
        } else {
            checkedIndices.remove(row)
        }
        impureUpdateCopyButton()
    }

    private func levelEmoji(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "⚪"
        case .info: return "🔵"
        case .warning: return "🟠"
        case .error: return "🔴"
        }
    }
}

// MARK: - Associated Object Key

private struct AssociatedKeys {
    static var level: UInt8 = 0
}
