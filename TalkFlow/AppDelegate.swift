import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    // 录音模块
    private var hotkeyIO: HotkeyIO?
    private let audioRecorder: AudioRecorderIO = AVAudioRecorderIO()
    private let filePathIO: FilePathIO = AppSupportFilePathIO()
    private let statusWindow = RecordingStatusWindow()
    private var recordingPhase: RecordingPhase = .idle
    private var lastToggleTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private let minRecordingDuration: TimeInterval = 1.0

    // STT 模块
    private let sttEngine: SenseVoiceIO = impureMakeSenseVoiceEngine()

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
    }

    // MARK: - ⚠️ STT 集成

    private func impureSetupSTT() {
        onRecordingComplete = { [weak self] url in
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.sttEngine.transcribe(url: url)
                    await MainActor.run {
                        switch result {
                        case .speech(let text, let language):
                            print("[STT] \(language): \(text)")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        case .silence:
                            print("[STT] Silence — ignored")
                        case .failure(let error):
                            print("[STT] Error: \(error)")
                        }
                    }
                } catch {
                    print("[STT] Exception: \(error)")
                }
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
        let windowRect = NSRect(x: 0, y: 0, width: 800, height: 600)
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

        NSLayoutConstraint.activate([
            // 权限卡片：顶部固定
            permissionCard.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            permissionCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            permissionCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            // 快捷键卡片：位于权限卡片下方
            hotkeyCard.topAnchor.constraint(equalTo: permissionCard.bottomAnchor, constant: 16),
            hotkeyCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            hotkeyCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
        ])

        window?.contentView = rootView
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - ⚠️ 录音协调

    @objc private func impureHandleHotkeyTrigger() {
        let now = Date()

        guard shouldAcceptToggle(lastToggleTime: lastToggleTime, now: now, debounce: debounceInterval) else {
            return
        }
        lastToggleTime = now

        let nextPhase = recordingPhaseFromToggle(recordingPhase, now: now)
        recordingPhase = nextPhase

        switch nextPhase {
        case .idle:
            impureStopRecording()
        case .recording:
            impureStartRecording()
        }
    }

    private func impureStartRecording() {
        let url = filePathIO.nextRecordingURL()
        do {
            try audioRecorder.startRecording(to: url)
            statusWindow.show()
            impureUpdateMenuBarIcon(isRecording: true)
            hotkeyIO?.registerEscHotkey { [weak self] in
                self?.impureCancelRecording()
            }
        } catch {
            recordingPhase = .idle
        }
    }

    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        let savedURL = audioRecorder.recordingURL
        statusWindow.dismiss()
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)

        if shouldSave(duration: duration, minDuration: minRecordingDuration),
           let url = savedURL {
            onRecordingComplete?(url)
        } else {
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
