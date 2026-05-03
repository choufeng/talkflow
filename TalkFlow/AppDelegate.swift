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

        // 权限检查模块
        let ios: [PermissionIO] = [MicrophonePermissionIO(), AccessibilityPermissionIO()]
        let permissionView = PermissionListView(frame: windowRect, ios: ios)
        permissionView.setUp()
        window?.contentView = permissionView

        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
