import AppKit

// MARK: - 协议

protocol PasteIO {
    /// ⚠️ 含副作用：模拟 Cmd+V 粘贴，依赖辅助功能权限
    func paste() -> Bool
}

// MARK: - 实现

/// 通过 CGEvent 模拟 Cmd+V 粘贴
final class CGEventPasteIO: PasteIO {

    /// ⚠️ CGEventPost 写入系统事件流
    func paste() -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }
}
