// 纯数据类型 — 零副作用，零外部依赖

import AppKit
import Carbon

// MARK: - 代数数据类型（ADT）

/// 快捷键绑定（product type — rule 11）
struct HotkeyBinding: Equatable, Codable {
    /// macOS 虚拟键码（如 kVK_ANSI_A = 0x00）
    let keyCode: UInt16
    /// Carbon 修饰键标志位组合（cmdKey=256, optionKey=2048, controlKey=4096, shiftKey=512）
    let modifiers: UInt
}

/// 快捷键 UI 展示状态（product type — rule 11）
struct HotkeyUIState: Equatable {
    let displayText: String       // 格式化后的快捷键显示文本
    let isRecording: Bool         // 是否正在录制
    let statusMessage: String     // 状态日志（成功/失败）
    let isSet: Bool              // 是否已设置快捷键
}

// MARK: - KeyCode → 可读名称（特殊键映射表）

private let specialKeyNames: [UInt16: String] = [
    0x31: "Space",
    0x24: "↩",        // Return
    0x30: "⇥",        // Tab
    0x33: "⌫",        // Delete
    0x75: "⌦",        // Forward Delete
    0x73: "Home",
    0x77: "End",
    0x74: "PgUp",
    0x79: "PgDn",
    0x7A: "F1",  0x78: "F2",  0x63: "F3",  0x76: "F4",
    0x60: "F5",  0x61: "F6",  0x62: "F7",  0x64: "F8",
    0x65: "F9",  0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    0x7B: "←",   0x7C: "→",   0x7D: "↓",   0x7E: "↑",
    0x35: "⎋",        // Escape
]

// MARK: - 纯函数（引用透明，无副作用）

/// 键码 → 可读按键名称
func keyName(from keyCode: UInt16) -> String {
    if let special = specialKeyNames[keyCode] {
        return special
    }
    // 尝试通过当前键盘布局将键码转为字符
    if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
       let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        var deadKeyState: UInt32 = 0
        let maxChars = 4
        var chars = [UniChar](repeating: 0, count: maxChars)
        var actualLen = 0
        UCKeyTranslate(
            unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self),
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxChars,
            &actualLen,
            &chars
        )
        if actualLen > 0 {
            return String(utf16CodeUnits: chars, count: actualLen).uppercased()
        }
    }
    return "?"
}

/// Carbon 修饰键 → 符号字符串（如 "⌘⌥"）
func modifierSymbols(_ carbonModifiers: UInt) -> String {
    var result = ""
    if carbonModifiers & UInt(cmdKey) != 0     { result += "⌘" }
    if carbonModifiers & UInt(optionKey) != 0  { result += "⌥" }
    if carbonModifiers & UInt(controlKey) != 0 { result += "⌃" }
    if carbonModifiers & UInt(shiftKey) != 0   { result += "⇧" }
    return result
}

/// NSEvent.ModifierFlags → Carbon 修饰键标志位
func nseventModifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt {
    var carbon: UInt = 0
    if flags.contains(.command) { carbon |= UInt(cmdKey) }
    if flags.contains(.option)  { carbon |= UInt(optionKey) }
    if flags.contains(.control) { carbon |= UInt(controlKey) }
    if flags.contains(.shift)   { carbon |= UInt(shiftKey) }
    return carbon
}

/// 格式化快捷键绑定为显示字符串（纯函数）
func formatHotkey(_ binding: HotkeyBinding?) -> String {
    guard let binding = binding else { return "未设置" }
    let syms = modifierSymbols(binding.modifiers)
    let key = keyName(from: binding.keyCode)
    return syms + key
}

/// 快捷键绑定 + 录制状态 → UI 状态（核心纯函数）
func produceHotkeyUIState(
    binding: HotkeyBinding?,
    isRecording: Bool,
    statusMessage: String
) -> HotkeyUIState {
    let displayText = formatHotkey(binding)
    let isSet = binding != nil
    return HotkeyUIState(
        displayText: displayText,
        isRecording: isRecording,
        statusMessage: statusMessage,
        isSet: isSet
    )
}
