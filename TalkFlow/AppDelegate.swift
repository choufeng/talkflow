import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var modelCard: CardView?

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

    /// 录音完成回调 — 供后续工作流（语音转写）接入
    var onRecordingComplete: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        impureSetupMenuBarIcon()
        impureShowMainWindow()
        impureSetupSTT()

        // 监听主快捷键触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleHotkeyTrigger),
            name: .talkFlowHotkeyTriggered,
            object: nil
        )
        // 监听 LLM 开关变化 → 显示/隐藏模型卡片
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleUseLLMChanged(_:)),
            name: .talkFlowUseLLMChanged,
            object: nil
        )
    }

    private func impureSetupSTT() {
        onRecordingComplete = { [weak self] url in
            print("[Pipeline] 录音文件: \(url.path)")
            self?.sttTask = Task { [weak self] in
                guard let self else { return }
                print("[Pipeline] 开始 STT 转写...")
                do {
                    let result = try await self.sttEngine.transcribe(url: url)

                    // 润色步骤（异步，在主线程 UI 更新前执行）
                    let finalResult: STTResult
                    switch result {
                    case .speech(let text, let language):
                        let config = impureLoadAppConfig()
                        if config.transcription.useLLM,
                           let provider = self.impureMakePolishingProvider() {
                            print("[Pipeline] 开始 LLM 润色...")
                            do {
                                let request = ChatRequest(messages: [
                                    ChatMessage(role: .user, content: text)
                                ])
                                let response = try await provider.send(request)
                                print("[Pipeline] 润色完成: \(response.content.prefix(60))...")
                                finalResult = .speech(text: response.content, language: language)
                            } catch {
                                print("[Pipeline] 润色失败，降级使用原文: \(error)")
                                finalResult = result
                            }
                        } else {
                            finalResult = result
                        }
                    default:
                        finalResult = result
                    }

                    await MainActor.run {
                        print("[Pipeline] STT 转写完成: \(finalResult)")
                        switch finalResult {
                        case .speech(let text, let language):
                            print("[Pipeline] 识别文本 (\(language)): \(text)")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            print("[Pipeline] 已写入剪贴板")
                            let pasted = self.pasteIO.paste()
                            if pasted {
                                print("[Pipeline] Cmd+V 粘贴✅ 成功")
                                self.statusWindow.dismiss()
                            } else {
                                print("[Pipeline] Cmd+V 粘贴❌ 失败")
                                self.statusWindow.show(phase: .pasteFailed)
                                self.statusWindow.dismissAfter(seconds: 3)
                            }
                        case .silence:
                            print("[Pipeline] 静音 — 跳过粘贴")
                            self.statusWindow.dismiss()
                        case .failure(let error):
                            print("[Pipeline] STT 失败: \(error)")
                            self.statusWindow.show(phase: .pasteFailed)
                            self.statusWindow.dismissAfter(seconds: 3)
                        }
                    }
                } catch {
                    print("[Pipeline] STT 异常: \(error)")
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

    @objc private func impureHandleUseLLMChanged(_ notification: Notification) {
        guard let isOn = notification.object as? Bool else { return }
        modelCard?.isHidden = !isOn
    }

    // MARK: - ⚠️ 主窗口（含副作用：窗口创建 + 视图挂载）

    private func impureShowMainWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 800, height: 800)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "TalkFlow"
        window?.center()

        // 根视图
        let rootView = NSView(frame: windowRect)

        // 权限管理卡片
        let ios: [PermissionIO] = [MicrophonePermissionIO(), AccessibilityPermissionIO()]
        let permissionList = PermissionListView(ios: ios)
        permissionList.setUp()

        let permissionCard = CardView(title: "权限管理", contentView: permissionList)
        permissionCard.setUp()
        rootView.addSubview(permissionCard)

        // 全局快捷键卡片
        let hotkeyIO = CarbonHotkeyIO()
        self.hotkeyIO = hotkeyIO
        let hotkeyView = HotkeySettingsView(io: hotkeyIO)
        hotkeyView.setUp()

        let hotkeyCard = CardView(title: "全局快捷键", contentView: hotkeyView)
        hotkeyCard.setUp()
        rootView.addSubview(hotkeyCard)

        // 转写设置卡片
        let transcriptionView = TranscriptionSettingsView()
        transcriptionView.setUp()

        let transcriptionCard = CardView(title: "转写", contentView: transcriptionView)
        transcriptionCard.setUp()
        rootView.addSubview(transcriptionCard)

        // 模型配置卡片
        let modelView = ModelSettingsView()
        modelView.setUp()
        let mc = CardView(title: "模型", contentView: modelView)
        mc.setUp()
        self.modelCard = mc
        rootView.addSubview(mc)

        // 初始可见性：根据 useLLM 配置
        let initialUseLLM = impureLoadAppConfig().transcription.useLLM
        mc.isHidden = !initialUseLLM

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

            // 模型卡片：位于转写卡片下方
            mc.topAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: 16),
            mc.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            mc.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            mc.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -20),
        ])

        window?.contentView = rootView
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - ⚠️ 录音协调

    @objc private func impureHandleHotkeyTrigger() {
        let now = Date()

        guard shouldAcceptToggle(lastToggleTime: lastToggleTime, now: now, debounce: debounceInterval) else {
            print("[Pipeline] 防抖忽略（间隔 < \(debounceInterval)s）")
            return
        }
        lastToggleTime = now

        let nextPhase = recordingPhaseFromToggle(recordingPhase, now: now)
        recordingPhase = nextPhase

        print("[Pipeline] 快捷键触发 → 切换到 \(nextPhase)")
        switch nextPhase {
        case .idle:
            impureStopRecording()
        case .recording:
            impureStartRecording()
        }
    }

    private func impureStartRecording() {
        let url = filePathIO.nextRecordingURL()
        print("[Pipeline] 🎤 开始录音 → \(url.lastPathComponent)")
        do {
            try audioRecorder.startRecording(to: url)
            statusWindow.show(phase: .recording)
            impureUpdateMenuBarIcon(isRecording: true)
            hotkeyIO?.registerEscHotkey { [weak self] in
                self?.impureCancelRecording()
            }
        } catch {
            print("[Pipeline] ❌ 录音启动失败: \(error)")
            recordingPhase = .idle
        }
    }

    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        let savedURL = audioRecorder.recordingURL
        print("[Pipeline] ⏹ 停止录音 时长=\(String(format: "%.1f", duration))s")
        statusWindow.show(phase: .transcribing)
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)

        if shouldSave(duration: duration, minDuration: minRecordingDuration),
           let url = savedURL {
            onRecordingComplete?(url)
        } else {
            print("[Pipeline] 录音太短(< \(minRecordingDuration)s) — 丢弃")
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

    // MARK: - ⚠️ 润色 Provider 工厂

    private func impureMakePolishingProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            print("[Pipeline] 润色 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            print("[Pipeline] 润色 — ProjectID 或 modelName 为空，跳过")
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
