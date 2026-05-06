# macOS 26.4.1 输入框兼容性修复 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 macOS 26.4.1 上翻译输入框无法聚焦 + 转写输入框文字不可见

**Architecture:** 两文件微调 — TranslationSettingsView 补 `viewDidMoveToWindow` 重响应链；TranscriptionSettingsView / TranslationSettingsView 用 `NSColor(name:dynamicProvider:)` 替代语义色

**Tech Stack:** AppKit, Swift 5

---

### Task 1: 修复 TranslationSettingsView 输入框无法聚焦

**Files:**
- Modify: `TalkFlow/Views/TranslationSettingsView.swift:51-55`（textView 属性声明区域附近）

- [ ] **Step 1: 添加 `viewDidMoveToWindow` 重写**

在 `TranslationSettingsView` 的 extension 或类体内添加：

```swift
// MARK: - 响应链修复 (macOS 26.4)

override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    textView.isEditable = true
    textView.isSelectable = true
}
```

插入位置：`setUp()` 方法之后、`impureSetupUI()` 之前。

- [ ] **Step 2: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -configuration Debug build 2>&1 | tail -5
```

预期：BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TalkFlow/Views/TranslationSettingsView.swift
git commit -m "fix: TranslationSettingsView NSTextView 响应链修复，macOS 26.4 上 viewDidMoveToWindow 强制重置 isEditable"
```

---

### Task 2: 修复 TranscriptionSettingsView 文字颜色=背景色

**Files:**
- Modify: `TalkFlow/Views/TranscriptionSettingsView.swift:51-53`（textView 属性赋值处）

- [ ] **Step 1: 替换 textColor / backgroundColor 为显式动态色**

将 `impureSetupUI()` 中：

```swift
textView.textColor = .textColor
textView.backgroundColor = .textBackgroundColor
```

替换为：

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

- [ ] **Step 2: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -configuration Debug build 2>&1 | tail -5
```

预期：BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TalkFlow/Views/TranscriptionSettingsView.swift
git commit -m "fix: TranscriptionSettingsView textColor/backgroundColor 语义色 → 显式动态色，修复 macOS 26.4 文字不可见"
```

---

### Task 3: 预防性修复 TranslationSettingsView 文字颜色

**Files:**
- Modify: `TalkFlow/Views/TranslationSettingsView.swift:75-76`（textView 属性赋值处）

- [ ] **Step 1: 同 Task 2 替换语义色**

将 `impureSetupUI()` 中：

```swift
textView.textColor = .textColor
textView.backgroundColor = .textBackgroundColor
```

替换为与 Task 2 完全相同的显式动态色代码（见 Task 2 Step 1）。

- [ ] **Step 2: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -configuration Debug build 2>&1 | tail -5
```

预期：BUILD SUCCEEDED

- [ ] **Step 3: 运行全部测试**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | tail -10
```

预期：All tests passed

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/Views/TranslationSettingsView.swift
git commit -m "fix: TranslationSettingsView textColor/backgroundColor 同步改为显式动态色，预防 macOS 26.4 同色问题"
```
