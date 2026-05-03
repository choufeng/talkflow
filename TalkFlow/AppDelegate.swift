import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        impureSetupMenuBarIcon()
        impureShowMainWindow()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
