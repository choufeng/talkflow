import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

    private let useLLMCheckbox = NSButton(checkboxWithTitle: "通过远程大语言模型对文本进行修饰和加工", target: nil, action: nil)
    private let promptLabel = NSTextField(labelWithString: "润色要求:")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    // MARK: - 构造

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 显式副作用入口

    func setUp() {
        impureSetupUI()
        impureLoadCheckboxState()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        useLLMCheckbox.font = NSFont.systemFont(ofSize: 13)
        useLLMCheckbox.target = self
        useLLMCheckbox.action = #selector(impureCheckboxToggled)
        useLLMCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(useLLMCheckbox)

        // 提示词标签
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.isHidden = true
        addSubview(promptLabel)

        // 多行输入框
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            useLLMCheckbox.topAnchor.constraint(equalTo: topAnchor),
            useLLMCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            useLLMCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            promptLabel.topAnchor.constraint(equalTo: useLLMCheckbox.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadCheckboxState() {
        let config = impureLoadAppConfig()
        useLLMCheckbox.state = config.transcription.useLLM ? .on : .off
        impureUpdatePromptVisibility()

        if !config.transcription.polishPrompt.isEmpty {
            textView.string = config.transcription.polishPrompt
        }
    }

    private func impureUpdatePromptVisibility() {
        let isOn = useLLMCheckbox.state == .on
        promptLabel.isHidden = !isOn
        scrollView.isHidden = !isOn
    }

    // MARK: - ⚠️ 事件

    @objc private func impureCheckboxToggled() {
        let isOn = useLLMCheckbox.state == .on
        var config = impureLoadAppConfig()
        config.transcription.useLLM = isOn
        impureSaveAppConfig(config)
        impureUpdatePromptVisibility()
        NotificationCenter.default.post(name: .talkFlowUseLLMChanged, object: isOn)
    }

    private func impureSavePromptConfig() {
        var config = impureLoadAppConfig()
        config.transcription.polishPrompt = textView.string
        impureSaveAppConfig(config)
    }
}

// MARK: - NSTextViewDelegate

extension TranscriptionSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSavePromptConfig()
    }
}
