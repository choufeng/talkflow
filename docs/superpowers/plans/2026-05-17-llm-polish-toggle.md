# LLM 润色开关实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在转写设置卡片添加"启用 LLM 润色"勾选框，取消勾选时跳过 LLM 润色和翻译

**Architecture:** `TranscriptionSettingsView` 顶部加 `NSButton(.switch)`，绑定已有 `AppConfig.TranscriptionConfig.useLLM`；`AppDelegate` 管线中检查 `useLLM` 决定是否调用 LLM

**Tech Stack:** Swift, AppKit, macOS

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `TalkFlow/Views/TranscriptionSettingsView.swift` | 加 checkbox UI + 读写 `useLLM` |
| `TalkFlow/AppDelegate.swift` | `onRecordingComplete` 闭包中加 `useLLM` 检查 |

---

### Task 1: TranscriptionSettingsView 添加 useLLM checkbox

**Files:**
- Modify: `TalkFlow/Views/TranscriptionSettingsView.swift`

- [ ] **Step 1: 添加 checkbox 子视图属性**

在 `TranscriptionSettingsView` 的 `Subviews` 标记区域（`private let optimizeButton` 之前）添加：

```swift
private let useLLMCheckbox = NSButton(checkboxWithTitle: "启用 LLM 润色", target: nil, action: nil)
```

- [ ] **Step 2: 在 impureSetupUI() 中添加 checkbox 布局**

在 `impureSetupUI()` 中，`translatesAutoresizingMaskIntoConstraints = false` 之后、`promptLabel` 之前插入 checkbox 的配置和约束，并将原有 `promptLabel.topAnchor` 改为相对 checkbox 底部：

```swift
// checkbox
useLLMCheckbox.font = NSFont.systemFont(ofSize: 12)
useLLMCheckbox.target = self
useLLMCheckbox.action = #selector(impureToggleUseLLM)
useLLMCheckbox.translatesAutoresizingMaskIntoConstraints = false
addSubview(useLLMCheckbox)

NSLayoutConstraint.activate([
    useLLMCheckbox.topAnchor.constraint(equalTo: topAnchor),
    useLLMCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
])
```

同时将 `promptLabel.topAnchor` 约束从：
```swift
promptLabel.topAnchor.constraint(equalTo: topAnchor),
```
改为：
```swift
promptLabel.topAnchor.constraint(equalTo: useLLMCheckbox.bottomAnchor, constant: 12),
```

- [ ] **Step 3: 在 impureLoadPromptState() 中加载 useLLM 值**

在 `impureLoadPromptState()` 末尾添加：

```swift
useLLMCheckbox.state = config.transcription.useLLM ? .on : .off
```

- [ ] **Step 4: 添加 toggle 事件方法**

在 `impureSavePromptConfig()` 方法后面添加：

```swift
@objc private func impureToggleUseLLM() {
    var config = impureLoadAppConfig()
    config.transcription.useLLM = (useLLMCheckbox.state == .on)
    impureSaveAppConfig(config)
}
```

- [ ] **Step 5: 构建验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add TalkFlow/Views/TranscriptionSettingsView.swift
git commit -m "feat: 转写设置添加 LLM 润色勾选框"
```

---

### Task 2: AppDelegate 管线检查 useLLM

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 在转写模式分支加 useLLM 检查**

在 `impureSetupSTT()` 的 `onRecordingComplete` 闭包中，找到 `.transcription` case 内的：

```swift
if let provider = self.impureMakeProvider(polish: true) {
```

改为：

```swift
if config.transcription.useLLM, let provider = self.impureMakeProvider(polish: true) {
```

但需要先取 config。在 `.transcription` case 内的 `switch self.currentWorkflow` 之前（即 `case .speech(let text, let language):` 之后、`switch self.currentWorkflow {` 之前），添加：

```swift
let config = impureLoadAppConfig()
```

- [ ] **Step 2: 在翻译模式分支加 useLLM 检查**

找到 `.translation` case 内的：

```swift
if let provider = self.impureMakeProvider(polish: false) {
```

改为：

```swift
if config.transcription.useLLM, let provider = self.impureMakeProvider(polish: false) {
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 运行测试**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: 管线检查 useLLM，关闭时跳过 LLM 润色和翻译"
```
