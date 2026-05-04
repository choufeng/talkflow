import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var modelCard: CardView?

    // 日志模块
    private let logger: LoggerIO = impureMakeLogger()
    private let logFileIO: LogFileIO = DefaultLogFileIO()
    private var logViewerWindow: LogViewerWindow?

    // 录音模块
    private var hotkeyIO: HotkeyIO?
    private let audioRecorder: AudioRecorderIO = AVAudioRecorderIO()
    private let filePathIO: FilePathIO = AppSupportFilePathIO()
    private let statusWindow = PipelineStatusWindow()
    private var recordingPhase: RecordingPhase = .idle
    private var lastToggleTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private let minRecordingDuration: TimeInterval = 1.0

    // STT 模块
    private let sttEngine: SenseVoiceIO = impureMakeSenseVoiceEngine()
    private var sttTask: Task<Void, Never>?
    // 粘贴模块
    private let pasteIO: PasteIO = CGEventPasteIO()

    // 当前工作流（纯数据类型，用于快捷键触发热键后分流）
    private var currentWorkflow: Workflow = .transcription

    /// 录音完成回调 — 供后续工作流（语音转写）接入
    var onRecordingComplete: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        impureSetupMenuBarIcon()
        impureShowMainWindow()
        impureSetupSTT()

        // 监听转写快捷键触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleTranscriptionHotkey),
            name: .talkFlowHotkeyTriggered,
            object: nil
        )
        // 监听翻译快捷键触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleTranslationHotkey),
            name: .talkFlowTranslationHotkeyTriggered,
            object: nil
        )

        // 清理两周前的日志和录音
        logFileIO.cleanOldLogs(before: 14)
        let filePathIO = AppSupportFilePathIO()
        cleanOldRecordings(fileIO: filePathIO, before: 14)
    }

    private func impureSetupSTT() {
        onRecordingComplete = { [weak self] url in
            self?.logger.info(tag: "Pipeline", "录音文件: \(url.path)")
            self?.sttTask = Task { [weak self] in
                guard let self else { return }
                self.logger.info(tag: "Pipeline", "开始 STT 转写...")
                do {
                    let result = try await self.sttEngine.transcribe(url: url)

                    let finalResult: STTResult
                    switch result {
                    case .speech(let text, let language):
                        switch self.currentWorkflow {
                        case .transcription:
                            if let provider = self.impureMakePolishingProvider() {
                                self.logger.info(tag: "Pipeline", "开始 LLM 润色...")
                                do {
                                    let request = ChatRequest(messages: [
                                        ChatMessage(role: .user, content: text)
                                    ])
                                    let response = try await provider.send(request)
                                    self.logger.info(tag: "Pipeline", "润色完成: \(response.content.prefix(60))...")
                                    finalResult = .speech(text: response.content, language: language)
                                } catch {
                                    self.logger.warning(tag: "Pipeline", "润色失败，降级使用原文: \(error)")
                                    finalResult = result
                                }
                            } else {
                                finalResult = result
                            }

                        case .translation:
                            if let provider = self.impureMakeTranslationProvider() {
                                self.logger.info(tag: "Pipeline", "开始 LLM 润色+翻译...")
                                do {
                                    let request = ChatRequest(messages: [
                                        ChatMessage(role: .user, content: text)
                                    ])
                                    let response = try await provider.send(request)
                                    self.logger.info(tag: "Pipeline", "润色+翻译完成: \(response.content.prefix(60))...")
                                    finalResult = .speech(text: response.content, language: language)
                                } catch {
                                    self.logger.warning(tag: "Pipeline", "翻译失败，降级使用原文: \(error)")
                                    finalResult = result
                                }
                            } else {
                                finalResult = result
                            }
                        }
                    default:
                        finalResult = result
                    }

                    await MainActor.run {
                        self.logger.info(tag: "Pipeline", "管线完成: \(finalResult)")
                        switch finalResult {
                        case .speech(let text, let language):
                            self.logger.info(tag: "Pipeline", "识别文本 (\(language)): \(text)")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            self.logger.info(tag: "Pipeline", "已写入剪贴板")
                            let pasted = self.pasteIO.paste()
                            if pasted {
                                self.logger.info(tag: "Pipeline", "Cmd+V 粘贴成功")
                                self.statusWindow.dismiss()
                            } else {
                                self.logger.error(tag: "Pipeline", "Cmd+V 粘贴失败")
                                self.statusWindow.show(phase: .pasteFailed)
                                self.statusWindow.dismissAfter(seconds: 3)
                            }
                        case .silence:
                            self.logger.info(tag: "Pipeline", "静音 — 跳过粘贴")
                            self.statusWindow.dismiss()
                        case .failure(let error):
                            self.logger.error(tag: "Pipeline", "STT 失败: \(error)")
                            self.statusWindow.show(phase: .pasteFailed)
                            self.statusWindow.dismissAfter(seconds: 3)
                        }
                    }
                } catch {
                    self.logger.error(tag: "Pipeline", "STT 异常: \(error)")
                    await MainActor.run {
                        self.statusWindow.dismiss()
                    }
                }
            }
        }

        // ✕ 按钮回调
        statusWindow.onCancel = { [weak self] in
            guard let self else { return }
            switch self.statusWindow.currentPhase {
            case .recording:
                self.impureCancelRecording()
            case .transcribing:
                self.sttTask?.cancel()
                self.statusWindow.dismiss()
            case .pasteFailed:
                self.statusWindow.dismiss()
            }
        }
    }

    // MARK: - ⚠️ 菜单栏图标（含副作用：系统状态栏注册）

    private func impureSetupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "TalkFlow")
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "TalkFlow"
            button.action = #selector(impureToggleWindow)
            button.target = self
        }
    }

    @objc private func impureToggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - ⚠️ 主窗口（含副作用：窗口创建 + 视图挂载）

    private func impureShowMainWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 800, height: 700)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "TalkFlow"
        window?.center()

        // 根视图
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false

        // 权限管理卡片
        let ios: [PermissionIO] = [MicrophonePermissionIO(), AccessibilityPermissionIO()]
        let permissionList = PermissionListView(ios: ios)
        permissionList.setUp()

        let permissionCard = CardView(title: "权限管理", contentView: permissionList)
        permissionCard.setUp()
        rootView.addSubview(permissionCard)

        // 快捷键卡片（包含转写快捷键 + 翻译快捷键）
        let hotkeyIO = CarbonHotkeyIO()
        self.hotkeyIO = hotkeyIO
        let hotkeyView = HotkeySettingsView(io: hotkeyIO)
        hotkeyView.setUp()

        let hotkeyCard = CardView(title: "快捷键", contentView: hotkeyView)
        hotkeyCard.setUp()
        rootView.addSubview(hotkeyCard)

        // 转写设置卡片
        let transcriptionView = TranscriptionSettingsView()
        transcriptionView.setUp()

        let transcriptionCard = CardView(title: "转写", contentView: transcriptionView)
        transcriptionCard.setUp()
        rootView.addSubview(transcriptionCard)

        // 翻译设置卡片
        let translationView = TranslationSettingsView()
        translationView.setUp()

        let translationCard = CardView(title: "翻译", contentView: translationView)
        translationCard.setUp()
        rootView.addSubview(translationCard)

        // 模型配置卡片
        let modelView = ModelSettingsView()
        modelView.setUp()
        let mc = CardView(title: "模型", contentView: modelView)
        mc.setUp()
        self.modelCard = mc
        rootView.addSubview(mc)

        // 模型卡片始终可见
        mc.isHidden = false

        // 日志卡片
        let logCardView = LogCardView(logFileIO: logFileIO)
        logViewerWindow = LogViewerWindow(logFileIO: logFileIO)
        logCardView.setUp { [weak self] in
            self?.logViewerWindow?.show()
        }
        rootView.addSubview(logCardView)

        NSLayoutConstraint.activate([
            // 权限卡片：顶部固定
            permissionCard.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            permissionCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            permissionCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 快捷键卡片：位于权限卡片下方
            hotkeyCard.topAnchor.constraint(equalTo: permissionCard.bottomAnchor, constant: 16),
            hotkeyCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            hotkeyCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 转写卡片：位于快捷键卡片下方
            transcriptionCard.topAnchor.constraint(equalTo: hotkeyCard.bottomAnchor, constant: 16),
            transcriptionCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            transcriptionCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 翻译卡片：位于转写卡片下方
            translationCard.topAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: 16),
            translationCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            translationCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 模型卡片：位于翻译卡片下方
            mc.topAnchor.constraint(equalTo: translationCard.bottomAnchor, constant: 16),
            mc.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            mc.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 日志卡片：位于模型卡片下方，底部固定
            logCardView.topAnchor.constraint(equalTo: mc.bottomAnchor, constant: 16),
            logCardView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            logCardView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            logCardView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
        ])

        // 包裹滚动视图
        let scrollView = NSScrollView()
        scrollView.documentView = rootView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        window?.contentView = scrollView

        // rootView 宽度绑定到 scrollView，保持水平自适应
        NSLayoutConstraint.activate([
            rootView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - ⚠️ 快捷键处理（分流）

    @objc private func impureHandleTranscriptionHotkey() {
        currentWorkflow = .transcription
        impureHandleHotkeySignal()
    }

    @objc private func impureHandleTranslationHotkey() {
        currentWorkflow = .translation
        impureHandleHotkeySignal()
    }

    private func impureHandleHotkeySignal() {
        let now = Date()

        guard shouldAcceptToggle(lastToggleTime: lastToggleTime, now: now, debounce: debounceInterval) else {
            logger.debug(tag: "Pipeline", "防抖忽略（间隔 < \(debounceInterval)s）")
            return
        }
        lastToggleTime = now

        let nextPhase = recordingPhaseFromToggle(recordingPhase, now: now)
        recordingPhase = nextPhase

        logger.debug(tag: "Pipeline", "快捷键触发（\(currentWorkflow)）→ 切换到 \(nextPhase)")
        switch nextPhase {
        case .idle:
            impureStopRecording()
        case .recording:
            impureStartRecording()
        }
    }

    // MARK: - ⚠️ 录音协调

    private func impureStartRecording() {
        let url = filePathIO.nextRecordingURL()
        logger.info(tag: "Pipeline", "🎤 开始录音 → \(url.lastPathComponent)")
        do {
            try audioRecorder.startRecording(to: url)
            statusWindow.show(phase: .recording)
            impureUpdateMenuBarIcon(isRecording: true)
            hotkeyIO?.registerEscHotkey { [weak self] in
                self?.impureCancelRecording()
            }
        } catch {
            logger.error(tag: "Pipeline", "录音启动失败: \(error)")
            recordingPhase = .idle
        }
    }

    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        let savedURL = audioRecorder.recordingURL
        logger.info(tag: "Pipeline", "⏹ 停止录音 时长=\(String(format: "%.1f", duration))s")
        statusWindow.show(phase: .transcribing)
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)

        if shouldSave(duration: duration, minDuration: minRecordingDuration),
           let url = savedURL {
            onRecordingComplete?(url)
        } else {
            logger.info(tag: "Pipeline", "录音太短(< \(minRecordingDuration)s) — 丢弃")
            statusWindow.dismiss()
            if let url = savedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func impureCancelRecording() {
        audioRecorder.cancelRecording()
        statusWindow.dismiss()
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)
        recordingPhase = .idle
    }

    // MARK: - ⚠️ 菜单栏图标状态

    private func impureUpdateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = isRecording ? "mic.circle.fill" : "mic.fill"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRecording ? "TalkFlow (录制中)" : "TalkFlow"
        )
        button.image?.size = NSSize(width: 18, height: 18)
    }

    // MARK: - ⚠️ Provider 工厂

    private func impureMakePolishingProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            logger.info(tag: "Pipeline", "润色 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            logger.info(tag: "Pipeline", "润色 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

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

        let promptConfig = PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: config.transcription.polishPrompt
        )

        return VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: promptConfig,
            thinkingBudget: config.vertexAI.thinkingBudget
        )
    }

    private func impureMakeTranslationProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            logger.info(tag: "Pipeline", "翻译 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            logger.info(tag: "Pipeline", "翻译 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

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

        // 合并润色+翻译系统提示词，作为翻译流程的 system prompt
        let systemPrompt = mergeTranslationPrompts(
            polishConfig: PromptConfig(
                defaultPrompt: makePolishingSystemPrompt(),
                userSupplement: config.transcription.polishPrompt
            ),
            translationConfig: PromptConfig(
                defaultPrompt: makeTranslationSystemPrompt(language: config.transcription.translationLanguage),
                userSupplement: config.transcription.translationPrompt
            )
        )
        let promptConfig = PromptConfig(
            defaultPrompt: systemPrompt,
            userSupplement: ""
        )

        return VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: promptConfig,
            thinkingBudget: config.vertexAI.thinkingBudget
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
