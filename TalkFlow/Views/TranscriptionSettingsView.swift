import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

    private let useLLMCheckbox = NSButton(checkboxWithTitle: "启用 LLM 润色", target: nil, action: nil)
    private let promptLabel = NSTextField(labelWithString: "润色要求:")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let optimizeButton = NSButton(title: "✨ 优化并保存", target: nil, action: nil)
    private var isOptimizing = false
    private var optimizeTask: Task<Void, Never>?

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
        impureLoadConfigState()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // checkbox
        useLLMCheckbox.font = NSFont.systemFont(ofSize: 12)
        useLLMCheckbox.target = self
        useLLMCheckbox.action = #selector(impureToggleUseLLM)
        useLLMCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(useLLMCheckbox)

        NSLayoutConstraint.activate([
            useLLMCheckbox.topAnchor.constraint(equalTo: topAnchor),
            useLLMCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])

        // 提示词标签
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
            promptLabel.topAnchor.constraint(equalTo: useLLMCheckbox.bottomAnchor, constant: 12),
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

    private func impureLoadConfigState() {
        let config = impureLoadAppConfig()
        if !config.transcription.polishPrompt.isEmpty {
            textView.string = config.transcription.polishPrompt
        }
        useLLMCheckbox.state = config.transcription.useLLM ? .on : .off
    }

    // MARK: - ⚠️ 事件

    private func impureSavePromptConfig() {
        var config = impureLoadAppConfig()
        config.transcription.polishPrompt = textView.string
        impureSaveAppConfig(config)
    }

    @objc private func impureToggleUseLLM() {
        var config = impureLoadAppConfig()
        config.transcription.useLLM = (useLLMCheckbox.state == .on)
        impureSaveAppConfig(config)
    }

    // MARK: - ⚠️ 优化逻辑

    @objc private func impureOptimizeTapped() {
        guard !isOptimizing else { return }
        let rawPrompt = textView.string

        guard let adc = impureLoadADCFromDefaultPath() else {
            impureMakeLogger().warning(tag: "TranscriptionSettings", "ADC 未检测到，无法优化")
            NSSound.beep()
            return
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName
        guard !projectID.isEmpty, !modelName.isEmpty else {
            impureMakeLogger().warning(tag: "TranscriptionSettings", "ProjectID/ModelName 未配置")
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
                    self.impureSavePromptConfig()
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().info(tag: "TranscriptionSettings", "提示词优化完成")
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().error(tag: "TranscriptionSettings", "优化失败: \(error.localizedDescription)")
                    NSSound.beep()
                }
            }
        }
    }
}

// MARK: - NSTextViewDelegate

extension TranscriptionSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSavePromptConfig()
    }
}
