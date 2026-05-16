# LLM 润色开关设计

## 概述

为 TalkFlow 转写设置卡片添加"启用 LLM 润色"勾选框，控制是否启用 LLM。`useLLM` 字段已存在于 `AppConfig.TranscriptionConfig`，默认 `true`，仅缺 UI 和管线生效逻辑。

## 数据模型

无需改动。`useLLM` 已在 `AppConfig.TranscriptionConfig` 中，默认 `true`：

```swift
struct TranscriptionConfig: Codable, Equatable {
    var useLLM: Bool  // 默认 true
    // ...
}
```

## UI

在 `TranscriptionSettingsView` 顶部添加 `NSButton`（`buttonType: .switch`）：

```
[✔] 启用 LLM 润色
```

- 默认勾选（对应 `useLLM: true`）
- 勾选状态与 `useLLM` 双向绑定：勾选→保存配置，加载→更新勾选状态

## 行为

### 勾选（默认）
润色、翻译均走 LLM，与现状一致。

### 取消勾选
- **转写模式**：跳过 LLM 润色，直接输出 STT 原文
- **翻译模式**：跳过 LLM，直接输出 STT 原文（无 LLM 无法翻译）

## 涉及改动

### 1. `TranscriptionSettingsView.swift`
- 加 `useLLMCheckbox`（`NSButton`，`.switch` 类型）
- `impureSetupUI()` — 添加 checkbox 布局约束
- `impureLoadPromptState()` — 从配置加载 `useLLM` 值
- `@objc impureToggleUseLLM()` — 保存变更

### 2. `AppDelegate.swift` — 管线
在 `impureSetupSTT()` 的 `onRecordingComplete` 闭包中，添加 `useLLM` 检查：

```swift
// 转写模式
case .transcription:
    if config.transcription.useLLM, let provider = impureMakeProvider(polish: true) {
        // LLM 润色 (现状)
    } else {
        finalResult = result  // 跳过 LLM
    }

// 翻译模式
case .translation:
    if config.transcription.useLLM, let provider = impureMakeProvider(polish: false) {
        // LLM 润色+翻译 (现状)
    } else {
        finalResult = result  // 跳过 LLM
    }
```

## 文件清单

| 文件 | 改动类型 |
|------|---------|
| `TalkFlow/Views/TranscriptionSettingsView.swift` | 加 checkbox + 读写 `useLLM` |
| `TalkFlow/AppDelegate.swift` | 加 `useLLM` 检查，跳过 LLM |
