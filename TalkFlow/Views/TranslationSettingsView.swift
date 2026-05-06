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
    private let optimizeButton = NSButton(title: "✨ 优化并保存", target: nil, action: nil)
    private var isOptimizing = false
    private var optimizeTask: Task<Void, Never>?

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

    // MARK: - 响应链修复 (macOS 26.4)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        textView.isEditable = true
        textView.isSelectable = true
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
        textView.textColor = NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark,
                 .accessibilityHighContrastDarkAqua,
                 .accessibilityHighContrastVibrantDark:
                return NSColor.white
            default:
                return NSColor.black
            }
        }
        textView.backgroundColor = NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark,
                 .accessibilityHighContrastDarkAqua,
                 .accessibilityHighContrastVibrantDark:
                return NSColor(white: 0.15, alpha: 1.0)
            default:
                return NSColor.white
            }
        }
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
        ])

        // 优化按钮
        optimizeButton.bezelStyle = .rounded
        optimizeButton.font = NSFont.systemFont(ofSize: 12)
        optimizeButton.target = self
        optimizeButton.action = #selector(impureOptimizeTapped)
        optimizeButton.translatesAutoresizingMaskIntoConstraints = false
        optimizeButton.toolTip = "调用 LLM 优化提示词，可能消耗 API 配额"
        addSubview(optimizeButton)

        NSLayoutConstraint.activate([
            optimizeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            optimizeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            optimizeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    // MARK: - ⚠️ 优化逻辑

    @objc private func impureOptimizeTapped() {
        guard !isOptimizing else { return }
        let rawPrompt = textView.string

        guard let adc = impureLoadADCFromDefaultPath() else {
            impureMakeLogger().warning(tag: "TranslationSettings", "ADC 未检测到，无法优化")
            NSSound.beep()
            return
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName
        guard !projectID.isEmpty, !modelName.isEmpty else {
            impureMakeLogger().warning(tag: "TranslationSettings", "ProjectID/ModelName 未配置")
            NSSound.beep()
            return
        }

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(projectID: projectID, privateKey: privateKey, clientEmail: clientEmail, tokenURI: tokenURI)
            tokenProvider = JWTTokenProvider(sa: sa)
        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
        }

        let provider = VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: "")
        )
        let optimizer = PromptOptimizerIO(provider: provider)

        isOptimizing = true
        optimizeButton.title = "⏳ 优化中..."
        optimizeButton.isEnabled = false

        optimizeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let optimized = try await optimizer.optimize(rawPrompt)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if !optimized.isEmpty {
                        self.textView.string = optimized
                    }
                    self.impureSaveTranslationPrompt()
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().info(tag: "TranslationSettings", "提示词优化完成")
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().error(tag: "TranslationSettings", "优化失败: \(error.localizedDescription)")
                    NSSound.beep()
                }
            }
        }
    }
}

// MARK: - NSTextViewDelegate

extension TranslationSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSaveTranslationPrompt()
    }
}
