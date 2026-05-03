import AppKit

/// 权限检查视图
/// - init 只做属性赋值（rule 16：构造与副作用分离）
/// - setUp() 在构造后显式调用，完成 UI 构建 + 初始渲染 + 事件监听
/// - 副作用通过 MicPermissionIO 协议委托
final class PermissionCheckView: NSView {

    // MARK: - Dependency
    private let io: MicPermissionIO

    // MARK: - Subviews
    private let micStatusLabel = NSTextField(labelWithString: "")
    private let micGrantButton = NSButton(title: "", target: nil, action: nil)

    /// 构造仅做属性赋值，不触发副作用
    init(frame frameRect: NSRect, io: MicPermissionIO = DefaultMicPermissionIO()) {
        self.io = io
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 显式调用完成初始化副作用：build UI → render → observe
    func setUp() {
        impureSetupUI()
        impureRender()
        impureObserveAppActivation()
    }

    // MARK: - ⚠️ 含副作用（UI 构建）

    private func impureSetupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        micStatusLabel.font = NSFont.systemFont(ofSize: 14)
        micStatusLabel.alignment = .center
        micStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(micStatusLabel)

        micGrantButton.bezelStyle = .rounded
        micGrantButton.font = NSFont.systemFont(ofSize: 14)
        micGrantButton.target = self
        micGrantButton.action = #selector(impureButtonClicked)
        micGrantButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(micGrantButton)

        NSLayoutConstraint.activate([
            micStatusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            micStatusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            micStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),

            micGrantButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            micGrantButton.topAnchor.constraint(equalTo: micStatusLabel.bottomAnchor, constant: 16),
        ])
    }

    // MARK: - ⚠️ 含副作用（注册通知监听）

    private func impureObserveAppActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureRender),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - ⚠️ 含副作用（IO + UI 更新）

    @objc private func impureButtonClicked() {
        Task { @MainActor in
            _ = await io.performAction(for: io.currentStatus())
            impureRender()
        }
    }

    // MARK: - ⚠️ 含副作用（读系统状态 + 更新 UI）

    @objc private func impureRender() {
        let status = io.currentStatus()          // ⚠️ 读可变状态
        let state = produceUIState(from: status)  // 纯函数映射

        micStatusLabel.stringValue = state.label
        micStatusLabel.textColor = status == .authorized ? .systemGreen : .secondaryLabelColor
        micGrantButton.title = state.buttonTitle
        micGrantButton.isHidden = !state.buttonVisible
    }
}
