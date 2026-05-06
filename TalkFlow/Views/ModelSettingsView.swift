import AppKit

// MARK: - 模型服务商

enum ModelProvider: String, CaseIterable {
    case vertexAI = "Vertex AI"
    case anthropic = "Anthropic"
}

// MARK: - 连接测试状态

enum ConnectionTestStatus: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

// MARK: - 模型设置视图

/// 模型卡片内容 — 下拉选择 + Vertex AI 配置 + 连接测试
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class ModelSettingsView: NSView, NSTextFieldDelegate {

    // MARK: - 可变状态

    private var selectedProvider: ModelProvider = .vertexAI
    private var adcInfo: ADCCredential? = nil
    private var connectionStatus: ConnectionTestStatus = .idle
    private var isTesting = false

    // MARK: - 子视图

    private let providerLabel = NSTextField(labelWithString: "模型服务:")
    private let providerDropdown = NSPopUpButton()

    // Vertex AI 配置容器（条件显示）
    private let vertexAIContainer = NSView()
    private let vertexAISeparator = NSBox()
    private let projectIDLabel = NSTextField(labelWithString: "Project ID:")
    private let projectIDField = NSTextField()
    private let modelNameLabel = NSTextField(labelWithString: "模型名称:")
    private let modelNameField = NSTextField()
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    // Anthropic 配置容器（条件显示）
    private let anthropicContainer = NSView()
    private let anthropicSeparator = NSBox()
    private let baseUrlLabel = NSTextField(labelWithString: "API Base URL:")
    private let baseUrlField = NSTextField()
    private let apiKeyLabel = NSTextField(labelWithString: "API Key:")
    private let apiKeyField = NSSecureTextField()
    private let anthropicModelLabel = NSTextField(labelWithString: "Model ID:")
    private let anthropicModelField = NSTextField()
    private let anthropicTestButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let anthropicStatusLabel = NSTextField(labelWithString: "")
    private var anthropicConnectionStatus: ConnectionTestStatus = .idle
    private var isAnthropicTesting = false

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
        impureDetectADC()
        impureRender()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // — 模型服务选择 —
        providerLabel.font = NSFont.systemFont(ofSize: 13)
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(providerLabel)

        providerDropdown.addItems(withTitles: ModelProvider.allCases.map(\.rawValue))
        providerDropdown.font = NSFont.systemFont(ofSize: 13)
        providerDropdown.target = self
        providerDropdown.action = #selector(impureProviderChanged)
        providerDropdown.translatesAutoresizingMaskIntoConstraints = false
        addSubview(providerDropdown)

        // — Vertex AI 配置区 —
        vertexAIContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vertexAIContainer)

        vertexAISeparator.boxType = .separator
        vertexAISeparator.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(vertexAISeparator)

        projectIDLabel.font = NSFont.systemFont(ofSize: 12)
        projectIDLabel.textColor = .secondaryLabelColor
        projectIDLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(projectIDLabel)

        projectIDField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        projectIDField.textColor = .controlTextColor
        projectIDField.isEditable = true
        projectIDField.placeholderString = "输入 Google Cloud Project ID"
        projectIDField.delegate = self
        projectIDField.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(projectIDField)

        modelNameLabel.font = NSFont.systemFont(ofSize: 12)
        modelNameLabel.textColor = .secondaryLabelColor
        modelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(modelNameLabel)

        modelNameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        modelNameField.textColor = .controlTextColor
        modelNameField.isEditable = true
        modelNameField.placeholderString = "gemini-2.5-flash"
        modelNameField.delegate = self
        modelNameField.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(modelNameField)

        testButton.bezelStyle = .rounded
        testButton.font = NSFont.systemFont(ofSize: 13)
        testButton.target = self
        testButton.action = #selector(impureTestConnection)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(testButton)

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(statusLabel)

        // — Anthropic 配置区 —
        anthropicContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(anthropicContainer)

        anthropicSeparator.boxType = .separator
        anthropicSeparator.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicSeparator)

        baseUrlLabel.font = NSFont.systemFont(ofSize: 12)
        baseUrlLabel.textColor = .secondaryLabelColor
        baseUrlLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(baseUrlLabel)

        baseUrlField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        baseUrlField.isEditable = true
        baseUrlField.placeholderString = "https://api.anthropic.com"
        baseUrlField.delegate = self
        baseUrlField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(baseUrlField)

        apiKeyLabel.font = NSFont.systemFont(ofSize: 12)
        apiKeyLabel.textColor = .secondaryLabelColor
        apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(apiKeyLabel)

        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        apiKeyField.isEditable = true
        apiKeyField.placeholderString = "sk-ant-..."
        apiKeyField.delegate = self
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(apiKeyField)

        anthropicModelLabel.font = NSFont.systemFont(ofSize: 12)
        anthropicModelLabel.textColor = .secondaryLabelColor
        anthropicModelLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicModelLabel)

        anthropicModelField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        anthropicModelField.isEditable = true
        anthropicModelField.placeholderString = "claude-sonnet-4-20250514"
        anthropicModelField.delegate = self
        anthropicModelField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicModelField)

        anthropicTestButton.bezelStyle = .rounded
        anthropicTestButton.font = NSFont.systemFont(ofSize: 13)
        anthropicTestButton.target = self
        anthropicTestButton.action = #selector(impureTestAnthropicConnection)
        anthropicTestButton.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicTestButton)

        anthropicStatusLabel.font = NSFont.systemFont(ofSize: 12)
        anthropicStatusLabel.lineBreakMode = .byWordWrapping
        anthropicStatusLabel.maximumNumberOfLines = 3
        anthropicStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicStatusLabel)

        NSLayoutConstraint.activate([
            // 顶层：providerLabel + providerDropdown
            providerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            providerLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            providerLabel.centerYAnchor.constraint(equalTo: providerDropdown.centerYAnchor),

            providerDropdown.leadingAnchor.constraint(equalTo: providerLabel.trailingAnchor, constant: 12),
            providerDropdown.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            providerDropdown.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            // vertexAIContainer
            vertexAIContainer.topAnchor.constraint(equalTo: providerDropdown.bottomAnchor, constant: 12),
            vertexAIContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            vertexAIContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            vertexAIContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            // 分隔线
            vertexAISeparator.topAnchor.constraint(equalTo: vertexAIContainer.topAnchor),
            vertexAISeparator.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            vertexAISeparator.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // Project ID
            projectIDLabel.topAnchor.constraint(equalTo: vertexAISeparator.bottomAnchor, constant: 8),
            projectIDLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            projectIDField.topAnchor.constraint(equalTo: projectIDLabel.bottomAnchor, constant: 4),
            projectIDField.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            projectIDField.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // 模型名称
            modelNameLabel.topAnchor.constraint(equalTo: projectIDField.bottomAnchor, constant: 12),
            modelNameLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            modelNameField.topAnchor.constraint(equalTo: modelNameLabel.bottomAnchor, constant: 4),
            modelNameField.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            modelNameField.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // 测试按钮
            testButton.topAnchor.constraint(equalTo: modelNameField.bottomAnchor, constant: 12),
            testButton.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            // 状态标签
            statusLabel.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: vertexAIContainer.bottomAnchor),

            // anthropicContainer 与 vertexAIContainer 同位置（互斥显示）
            anthropicContainer.topAnchor.constraint(equalTo: providerDropdown.bottomAnchor, constant: 12),
            anthropicContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            anthropicContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            anthropicContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            anthropicSeparator.topAnchor.constraint(equalTo: anthropicContainer.topAnchor),
            anthropicSeparator.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            anthropicSeparator.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            baseUrlLabel.topAnchor.constraint(equalTo: anthropicSeparator.bottomAnchor, constant: 8),
            baseUrlLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            baseUrlField.topAnchor.constraint(equalTo: baseUrlLabel.bottomAnchor, constant: 4),
            baseUrlField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            baseUrlField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            apiKeyLabel.topAnchor.constraint(equalTo: baseUrlField.bottomAnchor, constant: 12),
            apiKeyLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            apiKeyField.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 4),
            apiKeyField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            anthropicModelLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 12),
            anthropicModelLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            anthropicModelField.topAnchor.constraint(equalTo: anthropicModelLabel.bottomAnchor, constant: 4),
            anthropicModelField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            anthropicModelField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            anthropicTestButton.topAnchor.constraint(equalTo: anthropicModelField.bottomAnchor, constant: 12),
            anthropicTestButton.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            anthropicStatusLabel.topAnchor.constraint(equalTo: anthropicTestButton.bottomAnchor, constant: 8),
            anthropicStatusLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            anthropicStatusLabel.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),
            anthropicStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: anthropicContainer.bottomAnchor),
        ])
    }

    // MARK: - ⚠️ ADC 检测

    private func impureLoadConfig() {
        let config = impureLoadAppConfig()
        if !config.vertexAI.modelName.isEmpty {
            modelNameField.stringValue = config.vertexAI.modelName
        }
        if !config.vertexAI.projectID.isEmpty && projectIDField.stringValue.isEmpty {
            projectIDField.stringValue = config.vertexAI.projectID
        }
        if !config.anthropic.baseUrl.isEmpty && config.anthropic.baseUrl != "https://api.anthropic.com" {
            baseUrlField.stringValue = config.anthropic.baseUrl
        }
        if !config.anthropic.modelName.isEmpty {
            anthropicModelField.stringValue = config.anthropic.modelName
        }
        if config.selectedProvider == "anthropic" {
            providerDropdown.selectItem(withTitle: "Anthropic")
            selectedProvider = .anthropic
        }
    }

    private func impureDetectADC() {
        let log = impureMakeLogger()
        guard let adc = impureLoadADCFromDefaultPath() else {
            log.info(tag: "ModelSettings", "ADC 未检测到")
            adcInfo = nil
            return
        }
        adcInfo = adc

        let pid: String?
        switch adc {
        case .serviceAccount(_, _, _, let projectID):
            pid = projectID
            log.info(tag: "ModelSettings", "ADC 检测成功 — service_account, projectID: \(pid ?? "无")")
        case .authorizedUser(_, _, _, let projectID):
            pid = projectID
            log.info(tag: "ModelSettings", "ADC 检测成功 — authorized_user, projectID: \(pid ?? "无")")
        }

        if let pid = pid {
            projectIDField.stringValue = pid
            projectIDField.isEditable = false
            impureSaveConfig()
        } else {
            projectIDField.placeholderString = "未检测到 — 请手动输入 Project ID"
        }
    }

    // MARK: - ⚠️ 事件处理

    @objc private func impureProviderChanged() {
        guard let title = providerDropdown.selectedItem?.title,
              let provider = ModelProvider(rawValue: title) else { return }
        selectedProvider = provider
        impureRender()
    }

    @objc private func impureTestConnection() {
        guard !isTesting else { return }

        let projectID = projectIDField.stringValue.trimmingCharacters(in: .whitespaces)
        let modelName = modelNameField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !projectID.isEmpty, !modelName.isEmpty else {
            connectionStatus = .failure("请填写 Project ID 和模型名称")
            impureRender()
            return
        }

        guard let adc = adcInfo else {
            connectionStatus = .failure("未检测到 ADC 凭据，请运行 gcloud auth application-default login")
            impureRender()
            return
        }

        isTesting = true
        connectionStatus = .testing
        impureRender()

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(
                projectID: projectID,
                privateKey: privateKey,
                clientEmail: clientEmail,
                tokenURI: tokenURI
            )
            tokenProvider = JWTTokenProvider(sa: sa)

        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(
                clientID: clientID,
                clientSecret: clientSecret,
                refreshToken: refreshToken
            )
        }

        let provider = VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: "")
        )

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
                let response = try await provider.send(request)
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .success("✅ 连接成功")
                    self.impureRender()
                    impureMakeLogger().info(tag: "ModelSettings", "连接测试成功 — 响应: \(response.content.prefix(50))")
                }
            } catch let error as ProviderError {
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .failure("❌ \(error.displayMessage)")
                    self.impureRender()
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .failure("❌ 未知错误: \(error.localizedDescription)")
                    self.impureRender()
                }
            }
        }
    }

    // MARK: - ⚠️ 渲染

    private func impureRender() {
        let showVertexAI = selectedProvider == .vertexAI
        vertexAIContainer.isHidden = !showVertexAI
        anthropicContainer.isHidden = showVertexAI

        switch connectionStatus {
        case .idle:
            statusLabel.stringValue = ""
            statusLabel.textColor = .secondaryLabelColor
            testButton.isEnabled = true
            testButton.title = "测试连接"
        case .testing:
            statusLabel.stringValue = "⏳ 正在测试连接..."
            statusLabel.textColor = .secondaryLabelColor
            testButton.isEnabled = false
            testButton.title = "测试中..."
        case .success(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .systemGreen
            testButton.isEnabled = true
            testButton.title = "测试连接"
        case .failure(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .systemRed
            testButton.isEnabled = true
            testButton.title = "测试连接"
        }

        switch anthropicConnectionStatus {
        case .idle:
            anthropicStatusLabel.stringValue = ""
            anthropicStatusLabel.textColor = .secondaryLabelColor
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        case .testing:
            anthropicStatusLabel.stringValue = "⏳ 正在测试连接..."
            anthropicStatusLabel.textColor = .secondaryLabelColor
            anthropicTestButton.isEnabled = false
            anthropicTestButton.title = "测试中..."
        case .success(let msg):
            anthropicStatusLabel.stringValue = msg
            anthropicStatusLabel.textColor = .systemGreen
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        case .failure(let msg):
            anthropicStatusLabel.stringValue = msg
            anthropicStatusLabel.textColor = .systemRed
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ notification: Notification) {
        impureSaveConfig()
    }

    // MARK: - ⚠️ 持久化

    private func impureSaveConfig() {
        let modelName = modelNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let projectID = projectIDField.stringValue.trimmingCharacters(in: .whitespaces)
        let baseUrl = baseUrlField.stringValue.trimmingCharacters(in: .whitespaces)
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let anthropicModel = anthropicModelField.stringValue.trimmingCharacters(in: .whitespaces)

        var config = impureLoadAppConfig()
        if !modelName.isEmpty {
            config.vertexAI.modelName = modelName
        }
        if !projectID.isEmpty {
            config.vertexAI.projectID = projectID
        }
        if !baseUrl.isEmpty {
            config.anthropic.baseUrl = baseUrl
        }
        if !anthropicModel.isEmpty {
            config.anthropic.modelName = anthropicModel
        }
        config.selectedProvider = selectedProvider.rawValue
        impureSaveAppConfig(config)

        if !apiKey.isEmpty {
            let keychain = SecItemKeychainIO()
            try? keychain.set("api-key", value: apiKey)
        }
    }

    private final class InMemoryKeychainIO: KeychainIO {
        private var storage: [String: String] = [:]
        func get(_ key: String) throws -> String {
            guard let v = storage[key] else { throw KeychainError.itemNotFound }
            return v
        }
        func set(_ key: String, value: String) throws { storage[key] = value }
        func delete(_ key: String) throws { storage.removeValue(forKey: key) }
    }

    @objc private func impureTestAnthropicConnection() {
        guard !isAnthropicTesting else { return }

        let baseUrl = baseUrlField.stringValue.trimmingCharacters(in: .whitespaces)
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let modelID = anthropicModelField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !baseUrl.isEmpty, !apiKey.isEmpty, !modelID.isEmpty else {
            anthropicConnectionStatus = .failure("请填写 Base URL、API Key 和 Model ID")
            impureRender()
            return
        }

        isAnthropicTesting = true
        anthropicConnectionStatus = .testing
        impureRender()

        let keychain = InMemoryKeychainIO()
        try? keychain.set("api-key", value: apiKey)

        let provider = AnthropicAIIO(
            baseUrl: baseUrl,
            model: modelID,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
            thinkingBudget: 0,
            keychainIO: keychain
        )

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
                let response = try await provider.send(request)
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .success("✅ 连接成功")
                    self.impureRender()
                    impureMakeLogger().info(tag: "ModelSettings", "Anthropic 连接测试成功")
                }
            } catch let error as ProviderError {
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .failure("❌ \(error.displayMessage)")
                    self.impureRender()
                }
            } catch {
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .failure("❌ 未知错误: \(error.localizedDescription)")
                    self.impureRender()
                }
            }
        }
    }
}
