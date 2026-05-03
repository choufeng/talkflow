import AppKit

// MARK: - 单条权限行视图

/// 单条权限行 — 含 label + 按钮，副作用通过 PermissionIO 协议委托
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class PermissionRowView: NSView {

    // MARK: - Dependency
    private let io: PermissionIO

    // MARK: - Subviews
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    init(io: PermissionIO) {
        self.io = io
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp() {
        impureSetupUI()
        impureRender()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        actionButton.bezelStyle = .rounded
        actionButton.font = NSFont.systemFont(ofSize: 12)
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(impureButtonClicked)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - ⚠️ 事件处理

    @objc private func impureButtonClicked() {
        Task { @MainActor in
            let status = io.currentStatus()
            switch status {
            case .notDetermined:
                _ = await io.requestAccess()
            case .denied:
                io.openSystemSettings()
            case .authorized:
                break
            }
            impureRender()
        }
    }

    // MARK: - ⚠️ 渲染（读系统状态 + 更新 UI）

    @objc func impureRender() {
        let status = io.currentStatus()
        let state = produceUIState(from: PermissionState(kind: io.kind, status: status))

        statusLabel.stringValue = state.label
        statusLabel.textColor = status == .authorized ? .systemGreen : .secondaryLabelColor
        actionButton.title = state.buttonTitle
        actionButton.isHidden = !state.buttonVisible
    }
}

// MARK: - 权限列表内容视图

/// 权限列表 — 垂直排列多个 PermissionRowView，作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class PermissionListView: NSView {

    private let ios: [PermissionIO]

    init(ios: [PermissionIO]) {
        self.ios = ios
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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        ios
            .map { io -> PermissionRowView in
                let row = PermissionRowView(io: io)
                row.setUp()
                return row
            }
            .forEach { row in
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureRefreshAll),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func impureRefreshAll() {
        subviews
            .compactMap { $0 as? NSStackView }
            .flatMap { $0.arrangedSubviews }
            .compactMap { $0 as? PermissionRowView }
            .forEach { $0.impureRender() }
    }
}
