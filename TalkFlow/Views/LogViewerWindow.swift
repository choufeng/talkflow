import AppKit

/// 日志查看器窗口 — 左右分栏
final class LogViewerWindow {

    private var window: NSWindow?
    private let logFileIO: LogFileIO

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let listView = LogEntryListView(logFileIO: logFileIO)
        let detailView = LogEntryDetailView()

        listView.setUp { [weak detailView] entry, fileName in
            detailView?.show(entry: entry, sourceFile: fileName)
        }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(listView)
        splitView.addArrangedSubview(detailView)
        splitView.setPosition(400, ofDividerAt: 0)

        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 600)
        let win = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "日志查看器"
        win.contentView = splitView
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = WindowDelegate { [weak self] in
            self?.window = nil
        }

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 窗口关闭委托

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
