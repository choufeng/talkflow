# ClipboardIO 模块设计

**日期：** 2026-05-03
**分支：** feature/copy

## 概述

对 macOS 系统剪贴板操作的协议抽象，遵循现有 `PermissionIO` / `AudioRecorderIO` 模式。纯文本操作，覆盖 write（写入）+ paste（⌘V 模拟）+ read（读取验证）。

## 架构

```
ClipboardIO (协议)
  ├── NSPasteboardClipboardIO  — 真实现，操作 NSPasteboard + CGEvent
  └── MockClipboardIO          — 测试用 Mock
```

## 协议

```swift
protocol ClipboardIO {
    func write(_ text: String)   // ⚠️ 写入系统剪贴板
    func paste()                 // ⚠️ 发送 ⌘V
    func read() -> String?       // ⚠️ 读取剪贴板内容
}
```

`read()` 非核心功能，但简化测试：paste 后验证剪贴板内容无需 mock CGEvent 系统。

## 实现细节

### NSPasteboardClipboardIO

- `write` → `NSPasteboard.general.clearContents()` + `setString(_:forType:)`
- `paste` → 创建 `CGEvent`（V 键 keyDown + keyUp，含 `.maskCommand`），通过 `.cghidEventTap` 投递
- `read` → `NSPasteboard.general.string(forType:)`

### MockClipboardIO

- `writtenTexts: [String]` — 记录每次 write 的文本
- `pasteCallCount: Int` — paste 被调用次数
- `readCallCount: Int` — read 被调用次数
- `stubbedReadResult: String?` — read 返回值

## 文件清单

| 文件 | 类型 |
|------|------|
| `TalkFlow/IO/ClipboardIO.swift` | 新增 |
| `TalkFlowTests/Mocks/MockClipboardIO.swift` | 新增 |
| `TalkFlowTests/IO/ClipboardIOTests.swift` | 新增 |

不修改任何现有文件。

## 测试覆盖

1. `write` → 文本正确追加到 `writtenTexts`
2. `paste` → `pasteCallCount` 递增
3. `read` → 返回 `stubbedReadResult`，`readCallCount` 递增
4. 多次 `write` → 按顺序累积记录

## 不纳入范围

- 非纯文本类型（图片、富文本、文件）
- 剪贴板变化监听
- `Cmd+C` 复制模拟
- UI 集成
