import AppKit

// MARK: - 模型服务商

enum ModelProvider: String, CaseIterable {
    case vertexAI = "Vertex AI"
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
final class ModelSettingsView: NSView {

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
        projectIDField.isEditable = true
        projectIDField.placeholderString = "输入 Google Cloud Project ID"
        projectIDField.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(projectIDField)

        modelNameLabel.font = NSFont.systemFont(ofSize: 12)
        modelNameLabel.textColor = .secondaryLabelColor
        modelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(modelNameLabel)

        modelNameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        modelNameField.isEditable = true
        modelNameField.placeholderString = "gemini-2.0-flash-001"
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
            vertexAIContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

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
        ])
    }

    // MARK: - ⚠️ ADC 检测

    private func impureDetectADC() {
        guard let adc = impureLoadADCFromDefaultPath() else {
            print("[ModelSettings] ADC 未检测到")
            adcInfo = nil
            return
        }
        adcInfo = adc

        // 提取 projectID
        let pid: String?
        switch adc {
        case .serviceAccount(_, _, _, let projectID):
            pid = projectID
            print("[ModelSettings] ADC 检测成功 — service_account, projectID: \(pid ?? "无")")
        case .authorizedUser(_, _, _, let projectID):
            pid = projectID
            print("[ModelSettings] ADC 检测成功 — authorized_user, projectID: \(pid ?? "无")")
        }

        if let pid = pid {
            projectIDField.stringValue = pid
            projectIDField.isEditable = false
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
                    print("[ModelSettings] 连接测试成功 — 响应: \(response.content.prefix(50))")
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
    }
}
