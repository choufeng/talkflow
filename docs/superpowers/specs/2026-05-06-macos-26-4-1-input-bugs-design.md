# macOS 26.4.1 输入框兼容性修复

## 概述

macOS 26.4.1 引入 AppKit 行为不兼容变更，导致 TalkFlow 两个输入框异常：

| Bug | 表现 | 影响视图 |
|-----|------|---------|
| 输入框无法输入 | NSTextView 无聚焦、无光标、键盘无效 | TranslationSettingsView |
| 文字不可见 | 文字颜色 = 背景颜色 | TranscriptionSettingsView |

macOS 26.3.1 无此问题，26.4.1 深浅模式下均复现。

---

## 根因分析（假设）

### Bug 1：无法聚焦

- NSTextView 设置 `isEditable = true`，但 macOS 26.4 可能修改了深层嵌套视图中的响应链遍历逻辑
- 视图层级：`Window → NSScrollView → rootView → CardView → NSStackView → contentWrapper → TranslationSettingsView → NSScrollView → NSTextView`
- 两层 NSScrollView 嵌套使 NSTextView 在 26.4 的 key view loop 中被跳过

### Bug 2：文字同色

- `.textColor` / `.textBackgroundColor` 是 AppKit 语义动态色
- macOS 26.4 可能在特定视图上下文（嵌套 NSStackView + CardView）中两者解析为同值
- 精确 RGBA 值需在 26.4.1 设备上实测确认

---

## 修复方案

### Bug 1：TranslationSettingsView.swift

在 `viewDidMoveToWindow` 中强制重置 `isEditable` / `isSelectable`，确保窗口就绪后 NSTextView 正确注册到 key view loop：

```swift
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    textView.isEditable = true
    textView.isSelectable = true
}
```

### Bug 2：TranscriptionSettingsView.swift + TranslationSettingsView.swift

用 `NSColor(name:dynamicProvider:)` 显式 dispatch 硬编码 RGB，绕过语义色解析：

```swift
textView.textColor = NSColor(name: nil) { appearance in
    switch appearance.name {
    case .darkAqua, .vibrantDark,
         .accessibilityHighContrastDarkAqua,
         .accessibilityHighContrastVibrantDark:
        return NSColor.white
    default:
        return NSColor.black
    }
}
textView.backgroundColor = NSColor(name: nil) { appearance in
    switch appearance.name {
    case .darkAqua, .vibrantDark,
         .accessibilityHighContrastDarkAqua,
         .accessibilityHighContrastVibrantDark:
        return NSColor(white: 0.15, alpha: 1.0)
    default:
        return NSColor.white
    }
}
```

`TranslationSettingsView` 目前未报告 Bug 2，但使用相同语义色，一并进行预防性修复。

---

## 影响范围

- 仅两文件：`TranslationSettingsView.swift`、`TranscriptionSettingsView.swift`
- 不影响数据流、IO、快捷键、管线逻辑
- 对 macOS 26.3.1 及更早版本无回归风险（动态色在正常系统上解析与原来一致）

---

## 验证方法

1. macOS 26.4.1 上打开翻译/转写卡片，确认输入框可点击、可输入、文字可见
2. macOS 26.3.1 上回归确认深浅模式均正常
3. 切换深浅模式验证颜色正确切换
