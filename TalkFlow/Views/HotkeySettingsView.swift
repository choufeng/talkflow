import AppKit
import os.log

// MARK: - 日志

private let log = OSLog(subsystem: "im.xiajia.TalkFlow", category: "HotkeyView")

private func uiLog(_ msg: String) {
    os_log("%{public}@", log: log, type: .info, msg)
    print("[TalkFlow.HotkeyUI] \(msg)")
}

// MARK: - 快捷键设置内容视图

/// 快捷键设置视图 — 作为卡片内容使用
/// init 仅赋值 HotkeyIO（rule 16），setUp() 显式触发副作用
final class HotkeySettingsView: NSView {

    // MARK: - Dependency

    private let io: HotkeyIO

    // MARK: - 可变状态（UI 层持有）

    private var currentBinding: HotkeyBinding? = nil
    private var isRecording = false

    // MARK: - Subviews

    private let descriptionLabel = NSTextField(labelWithString: "")
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    // MARK: - 构造

    init(io: HotkeyIO) {
        self.io = io
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 显式副作用入口

    func setUp() {
        impureSetupUI()
        impureLoadAndRegister()
        impureRender()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        descriptionLabel.stringValue = "设置全局快捷键，触发「转写」功能"
        descriptionLabel.font = NSFont.systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descriptionLabel)

        hotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hotkeyLabel)

        recordButton.bezelStyle = .rounded
        recordButton.font = NSFont.systemFont(ofSize: 13)
        recordButton.target = self
        recordButton.action = #selector(impureRecordClicked)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recordButton)

        clearButton.bezelStyle = .rounded
        clearButton.font = NSFont.systemFont(ofSize: 13)
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(impureClearClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            hotkeyLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 10),
            hotkeyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            hotkeyLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),

            recordButton.leadingAnchor.constraint(equalTo: hotkeyLabel.trailingAnchor, constant: 16),
            recordButton.centerYAnchor.constraint(equalTo: hotkeyLabel.centerYAnchor),
            recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            clearButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 8),
            clearButton.centerYAnchor.constraint(equalTo: hotkeyLabel.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: hotkeyLabel.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 启动时加载 + 注册

    private func impureLoadAndRegister() {
        if let binding = io.loadBinding() {
            currentBinding = binding
            let ok = io.registerHotkey(binding)
            if ok {
                uiLog("启动时注册快捷键成功: \(formatHotkey(binding))")
            } else {
                uiLog("⚠️ 启动时注册快捷键失败: \(formatHotkey(binding))")
            }
        } else {
            uiLog("未检测到已保存的快捷键")
        }
    }

    // MARK: - ⚠️ 事件处理

    @objc private func impureRecordClicked() {
        if isRecording {
            io.stopRecording()
            isRecording = false
            impureRender()
            return
        }

        isRecording = true
        impureRender()
        uiLog("等待用户按下快捷键...")

        io.startRecording { [weak self] binding in
            guard let self = self else { return }
            self.isRecording = false

            // 保存绑定
            self.io.saveBinding(binding)

            // 注销旧键，注册新键
            self.io.unregisterHotkey()
            let ok = self.io.registerHotkey(binding)
            self.currentBinding = binding

            if ok {
                uiLog("✅ 快捷键已更新: \(formatHotkey(binding))")
            } else {
                uiLog("❌ 快捷键注册失败: \(formatHotkey(binding)) — 可能已被其他应用占用")
            }
            self.impureRender()
        }
    }

    @objc private func impureClearClicked() {
        io.unregisterHotkey()
        io.clearBinding()
        currentBinding = nil
        uiLog("快捷键已清除")
        impureRender()
    }

    // MARK: - ⚠️ 渲染

    func impureRender() {
        let state = produceHotkeyUIState(
            binding: currentBinding,
            isRecording: isRecording
        )

        hotkeyLabel.stringValue = state.displayText
        hotkeyLabel.textColor = state.isSet ? .systemGreen : .placeholderTextColor

        recordButton.title = state.isRecording ? "停止录制" : "录制快捷键"
        recordButton.isEnabled = true

        clearButton.title = "清除"
        clearButton.isHidden = !state.isSet

        statusLabel.stringValue = state.statusMessage
    }
}
