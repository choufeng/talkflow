import AppKit

// MARK: - 翻译设置内容视图

/// 翻译设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranslationSettingsView: NSView {

    // MARK: - Subviews

    private let languageLabel = NSTextField(labelWithString: "目标语言:")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let promptLabel = NSTextField(labelWithString: "翻译要求:")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    // MARK: - 语言选项

    private let languageOptions = ["英文", "越南语", "西班牙语", "日文", "韩语"]

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
        impureLoadConfig()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // 语言标签
        languageLabel.font = NSFont.systemFont(ofSize: 12)
        languageLabel.textColor = .secondaryLabelColor
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(languageLabel)

        // 语言选择框
        languagePopup.addItems(withTitles: languageOptions)
        languagePopup.font = NSFont.systemFont(ofSize: 13)
        languagePopup.target = self
        languagePopup.action = #selector(impureLanguageChanged)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(languagePopup)

        // 翻译要求标签
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)

        // 多行输入框
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            languageLabel.topAnchor.constraint(equalTo: topAnchor),
            languageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            languagePopup.leadingAnchor.constraint(equalTo: languageLabel.trailingAnchor, constant: 8),
            languagePopup.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            languagePopup.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            promptLabel.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadConfig() {
        let config = impureLoadAppConfig()
        if let idx = languageOptions.firstIndex(of: config.transcription.translationLanguage) {
            languagePopup.selectItem(at: idx)
        }
        if !config.transcription.translationPrompt.isEmpty {
            textView.string = config.transcription.translationPrompt
        }
    }

    // MARK: - ⚠️ 事件

    @objc private func impureLanguageChanged() {
        var config = impureLoadAppConfig()
        config.transcription.translationLanguage = languagePopup.titleOfSelectedItem ?? "英文"
        impureSaveAppConfig(config)
    }

    private func impureSaveTranslationPrompt() {
        var config = impureLoadAppConfig()
        config.transcription.translationPrompt = textView.string
        impureSaveAppConfig(config)
    }
}

// MARK: - NSTextViewDelegate

extension TranslationSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSaveTranslationPrompt()
    }
}
