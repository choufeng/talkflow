import AppKit
import os.log

// MARK: - 日志

private let log = OSLog(subsystem: "im.xiajia.TalkFlow", category: "HotkeyView")

private func uiLog(_ msg: String) {
    os_log("%{public}@", log: log, type: .info, msg)
    print("[TalkFlow.HotkeyUI] \(msg)")
}

// MARK: - 快捷键行内部状态

private struct HotkeyRowState {
    var binding: HotkeyBinding? = nil
    var isRecording = false
}

// MARK: - 快捷键设置内容视图

/// 快捷键设置视图 — 包含转写快捷键与翻译快捷键两行
/// init 仅赋值 HotkeyIO（rule 16），setUp() 显式触发副作用
final class HotkeySettingsView: NSView {

    // MARK: - Dependency

    private let io: HotkeyIO

    // MARK: - 可变状态

    private var transcriptionState = HotkeyRowState()
    private var translationState = HotkeyRowState()

    // MARK: - Subviews（转写行）

    private let transcriptionDesc = NSTextField(labelWithString: "")
    private let transcriptionLabel = NSTextField(labelWithString: "")
    private let transcriptionRecordBtn = NSButton(title: "", target: nil, action: nil)
    private let transcriptionClearBtn = NSButton(title: "", target: nil, action: nil)
    private let transcriptionStatus = NSTextField(labelWithString: "")

    // MARK: - Subviews（翻译行）

    private let translationDesc = NSTextField(labelWithString: "")
    private let translationLabel = NSTextField(labelWithString: "")
    private let translationRecordBtn = NSButton(title: "", target: nil, action: nil)
    private let translationClearBtn = NSButton(title: "", target: nil, action: nil)
    private let translationStatus = NSTextField(labelWithString: "")

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
        impureRenderAll()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // — 转写行 —
        impureSetupHotkeyRow(
            desc: transcriptionDesc,
            label: transcriptionLabel,
            recordBtn: transcriptionRecordBtn,
            clearBtn: transcriptionClearBtn,
            status: transcriptionStatus,
            recordAction: #selector(impureTranscriptionRecordClicked),
            clearAction: #selector(impureTranscriptionClearClicked)
        )

        // — 翻译行 —
        impureSetupHotkeyRow(
            desc: translationDesc,
            label: translationLabel,
            recordBtn: translationRecordBtn,
            clearBtn: translationClearBtn,
            status: translationStatus,
            recordAction: #selector(impureTranslationRecordClicked),
            clearAction: #selector(impureTranslationClearClicked)
        )

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            // 转写行
            transcriptionDesc.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            transcriptionDesc.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionLabel.topAnchor.constraint(equalTo: transcriptionDesc.bottomAnchor, constant: 10),
            transcriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            transcriptionRecordBtn.leadingAnchor.constraint(equalTo: transcriptionLabel.trailingAnchor, constant: 16),
            transcriptionRecordBtn.centerYAnchor.constraint(equalTo: transcriptionLabel.centerYAnchor),
            transcriptionRecordBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            transcriptionClearBtn.leadingAnchor.constraint(equalTo: transcriptionRecordBtn.trailingAnchor, constant: 8),
            transcriptionClearBtn.centerYAnchor.constraint(equalTo: transcriptionLabel.centerYAnchor),
            transcriptionStatus.topAnchor.constraint(equalTo: transcriptionLabel.bottomAnchor, constant: 6),
            transcriptionStatus.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionStatus.trailingAnchor.constraint(equalTo: trailingAnchor),

            // 分隔线
            separator.topAnchor.constraint(equalTo: transcriptionStatus.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            // 翻译行
            translationDesc.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            translationDesc.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationLabel.topAnchor.constraint(equalTo: translationDesc.bottomAnchor, constant: 10),
            translationLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            translationRecordBtn.leadingAnchor.constraint(equalTo: translationLabel.trailingAnchor, constant: 16),
            translationRecordBtn.centerYAnchor.constraint(equalTo: translationLabel.centerYAnchor),
            translationRecordBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            translationClearBtn.leadingAnchor.constraint(equalTo: translationRecordBtn.trailingAnchor, constant: 8),
            translationClearBtn.centerYAnchor.constraint(equalTo: translationLabel.centerYAnchor),
            translationStatus.topAnchor.constraint(equalTo: translationLabel.bottomAnchor, constant: 6),
            translationStatus.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationStatus.trailingAnchor.constraint(equalTo: trailingAnchor),
            translationStatus.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func impureSetupHotkeyRow(
        desc: NSTextField,
        label: NSTextField,
        recordBtn: NSButton,
        clearBtn: NSButton,
        status: NSTextField,
        recordAction: Selector,
        clearAction: Selector
    ) {
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.translatesAutoresizingMaskIntoConstraints = false
        addSubview(desc)

        label.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        recordBtn.bezelStyle = .rounded
        recordBtn.font = NSFont.systemFont(ofSize: 13)
        recordBtn.target = self
        recordBtn.action = recordAction
        recordBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recordBtn)

        clearBtn.bezelStyle = .rounded
        clearBtn.font = NSFont.systemFont(ofSize: 13)
        clearBtn.controlSize = .small
        clearBtn.target = self
        clearBtn.action = clearAction
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearBtn)

        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .tertiaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
    }

    // MARK: - ⚠️ 启动时加载 + 注册

    private func impureLoadAndRegister() {
        if let binding = io.loadBinding() {
            transcriptionState.binding = binding
            let ok = io.registerHotkey(binding)
            if ok {
                uiLog("启动时注册转写快捷键成功: \(formatHotkey(binding))")
            } else {
                uiLog("⚠️ 启动时注册转写快捷键失败: \(formatHotkey(binding))")
            }
        } else {
            uiLog("未检测到已保存的转写快捷键")
        }

        if let binding = io.loadTranslationBinding() {
            translationState.binding = binding
            let ok = io.registerTranslationHotkey(binding)
            if ok {
                uiLog("启动时注册翻译快捷键成功: \(formatHotkey(binding))")
            } else {
                uiLog("⚠️ 启动时注册翻译快捷键失败: \(formatHotkey(binding))")
            }
        } else {
            uiLog("未检测到已保存的翻译快捷键")
        }
    }

    // MARK: - ⚠️ 转写快捷键事件

    @objc private func impureTranscriptionRecordClicked() {
        if transcriptionState.isRecording {
            io.stopRecording()
            transcriptionState.isRecording = false
            impureRenderAll()
            return
        }

        transcriptionState.isRecording = true
        impureRenderAll()
        uiLog("等待用户按下转写快捷键...")

        io.startRecording { [weak self] binding in
            guard let self = self else { return }
            self.transcriptionState.isRecording = false
            self.io.saveBinding(binding)
            self.io.unregisterHotkey()
            let ok = self.io.registerHotkey(binding)
            self.transcriptionState.binding = binding

            if ok {
                uiLog("✅ 转写快捷键已更新: \(formatHotkey(binding))")
            } else {
                uiLog("❌ 转写快捷键注册失败: \(formatHotkey(binding))")
            }
            self.impureRenderAll()
        }
    }

    @objc private func impureTranscriptionClearClicked() {
        io.unregisterHotkey()
        io.clearBinding()
        transcriptionState.binding = nil
        uiLog("转写快捷键已清除")
        impureRenderAll()
    }

    // MARK: - ⚠️ 翻译快捷键事件

    @objc private func impureTranslationRecordClicked() {
        if translationState.isRecording {
            io.stopTranslationRecording()
            translationState.isRecording = false
            impureRenderAll()
            return
        }

        translationState.isRecording = true
        impureRenderAll()
        uiLog("等待用户按下翻译快捷键...")

        io.startTranslationRecording { [weak self] binding in
            guard let self = self else { return }
            self.translationState.isRecording = false
            self.io.saveTranslationBinding(binding)
            self.io.unregisterTranslationHotkey()
            let ok = self.io.registerTranslationHotkey(binding)
            self.translationState.binding = binding

            if ok {
                uiLog("✅ 翻译快捷键已更新: \(formatHotkey(binding))")
            } else {
                uiLog("❌ 翻译快捷键注册失败: \(formatHotkey(binding))")
            }
            self.impureRenderAll()
        }
    }

    @objc private func impureTranslationClearClicked() {
        io.unregisterTranslationHotkey()
        io.clearTranslationBinding()
        translationState.binding = nil
        uiLog("翻译快捷键已清除")
        impureRenderAll()
    }

    // MARK: - ⚠️ 渲染

    private func impureRenderAll() {
        transcriptionDesc.stringValue = "转写快捷键"

        let tState = produceHotkeyUIState(
            binding: transcriptionState.binding,
            isRecording: transcriptionState.isRecording
        )
        transcriptionLabel.stringValue = tState.displayText
        transcriptionLabel.textColor = tState.isSet ? .systemGreen : .placeholderTextColor
        transcriptionRecordBtn.title = tState.isRecording ? "停止录制" : "录制快捷键"
        transcriptionRecordBtn.isEnabled = true
        transcriptionClearBtn.title = "清除"
        transcriptionClearBtn.isHidden = !tState.isSet
        transcriptionStatus.stringValue = tState.statusMessage

        translationDesc.stringValue = "翻译快捷键"

        let tlState = produceHotkeyUIState(
            binding: translationState.binding,
            isRecording: translationState.isRecording
        )
        translationLabel.stringValue = tlState.displayText
        translationLabel.textColor = tlState.isSet ? .systemGreen : .placeholderTextColor
        translationRecordBtn.title = tlState.isRecording ? "停止录制" : "录制快捷键"
        translationRecordBtn.isEnabled = true
        translationClearBtn.title = "清除"
        translationClearBtn.isHidden = !tlState.isSet
        translationStatus.stringValue = tlState.statusMessage
    }
}
