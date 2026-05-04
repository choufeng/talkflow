import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

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
        impureLoadPromptState()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // 提示词标签
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
            promptLabel.topAnchor.constraint(equalTo: topAnchor),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadPromptState() {
        let config = impureLoadAppConfig()
        if !config.transcription.polishPrompt.isEmpty {
            textView.string = config.transcription.polishPrompt
        }
    }

    // MARK: - ⚠️ 事件

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
