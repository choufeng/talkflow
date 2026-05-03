import AppKit

// MARK: - 协议

protocol ClipboardIO {
    /// ⚠️ 含副作用：写入系统剪贴板
    func write(_ text: String)

    /// ⚠️ 含副作用：发送 ⌘V 粘贴
    func paste()

    /// ⚠️ 非引用透明：读取剪贴板当前内容
    func read() -> String?
}

// MARK: - 实现

struct NSPasteboardClipboardIO: ClipboardIO {

    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func paste() {
        let src = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags   = CGEventFlags.maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
