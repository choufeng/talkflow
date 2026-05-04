# 翻译功能设计

## 概述

新增翻译功能，用户通过翻译快捷键触发与转写相同的录音+STT 前置流程，经 LLM 润色+翻译合并处理后，结果写入剪贴板并自动粘贴。

## 前置变更：移除 useLLM 勾选框

- `TranscriptionSettingsView` 中移除 useLLM checkbox
- `AppConfig.TranscriptionConfig.useLLM` 默认值改为 `true`
- 向后兼容：旧配置文件 `useLLM = false` 时 JSONDecoder 仍可用，新配置始终写 `true`
- 模型卡片始终可见，`talkFlowUseLLMChanged` 通知移除
- 翻译卡片始终可见，翻译快捷键始终可用

## 配置扩展

`AppConfig.TranscriptionConfig` 新增翻译字段：

```swift
struct TranscriptionConfig: Codable, Equatable {
    var useLLM: Bool = true           // 默认值改为 true
    var polishPrompt: String = ""
    var translationLanguage: String = "英文"   // 新增
    var translationPrompt: String = ""         // 新增
}
```

## 管线分流

两个快捷键触发不同管线：

```
转写快捷键 → 录音 → STT → .speech(text) → 润色 → 剪贴板 → Cmd+V
翻译快捷键 → 录音 → STT → .speech(text) → 润色+翻译合并 → 剪贴板 → Cmd+V
```

`silence` / `failure` 分支行为不变。

### 分流机制

- 转写快捷键触发 `talkFlowTranscriptionHotkey` 通知
- 翻译快捷键触发 `talkFlowTranslationHotkey` 通知
- `AppDelegate` 分别监听，记录 `currentWorkflow` 枚举（`.transcription` / `.translation`）
- STT 完成后根据 `currentWorkflow` 选择后续处理：

```swift
enum Workflow: Equatable {
    case transcription
    case translation
}
```

### LLM 调用

转写流程：
```swift
let promptConfig = PromptConfig(
    defaultPrompt: makePolishingSystemPrompt(),
    userSupplement: config.transcription.polishPrompt
)
```

翻译流程：
```swift
let systemPrompt = mergeTranslationPrompts(
    polishConfig: PromptConfig(
        defaultPrompt: makePolishingSystemPrompt(),
        userSupplement: config.transcription.polishPrompt
    ),
    translationConfig: PromptConfig(
        defaultPrompt: makeTranslationSystemPrompt(language: config.transcription.translationLanguage),
        userSupplement: config.transcription.translationPrompt
    )
)
```

### Prompt 合并顺序

```
system_prompt = 润色固定 + 润色用户补充 + 翻译固定 + 翻译用户补充
```

先润色后翻译：原文质量提升后再翻译更准确。

## 翻译固定系统提示词

纯函数 `makeTranslationSystemPrompt(language:)` 返回硬编码字符串：

```
将用户提供的文本翻译为{language}。

要求：
- 保持原文语义和语气，不添加额外解释
- 专业术语保持一致，不随意替换
- 自然流畅，符合目标语言表达习惯
- 仅输出翻译结果，不输出原文或其他内容
```

不可通过 UI 编辑，仅可修改源代码。

## UI 变更

### 快捷键卡片

现有一行重构为两行：

```
┌─ 快捷键 ──────────────────────────┐
│  转写快捷键: [⌘⇧T] [录制快捷键] [清除] │
│  翻译快捷键: [⌘⇧Y] [录制快捷键] [清除] │
└──────────────────────────────────┘
```

- 标题从"全局快捷键"改为"快捷键"
- 第一行标注"转写快捷键"，绑定 `TranscriptionHotkey`
- 第二行标注"翻译快捷键"，绑定 `TranslationHotkey`
- 独立存储 key，独立 Carbon 注册，独立通知
- `HotkeyIO` 协议扩展：新增 `loadTranslationBinding` / `saveTranslationBinding` / `clearTranslationBinding` / `registerTranslationHotkey` / `unregisterTranslationHotkey`
- `HotkeySettingsView` 内部包含两个 `HotkeyRow` 子视图（或等价结构）

### 转写卡片

- 移除 useLLM checkbox
- 润色要求输入框始终显示
- "润色要求:" 标签改为直接可见

### 翻译卡片（新建）

```
┌─ 翻译 ────────────────────────────┐
│  目标语言: [英文 ▾]               │
│  翻译要求:                         │
│  ┌──────────────────────────────┐ │
│  │ (输入自定义翻译补充)           │ │
│  │                              │ │
│  └──────────────────────────────┘ │
└──────────────────────────────────┘
```

- `NSPopUpButton` 语言选择：英文（默认）、越南语、西班牙语、日语、韩语
- `NSTextView` 多行输入框用于翻译补充要求
- 变更保存到 `config.transcription.translationLanguage` / `translationPrompt`
- `impureLoadCheckboxState` → 改为加载翻译配置（language + prompt）

### 卡片布局顺序

```
权限管理 → 快捷键 → 转写 → 翻译 → 模型
```

## 纯函数清单

| 函数 | 位置 | 说明 |
|------|------|------|
| `makeTranslationSystemPrompt(language:)` | `PromptConfig.swift` | 翻译固定提示词 |
| `mergeTranslationPrompts(polishConfig:translationConfig:)` | `PromptConfig.swift` | 合并润色+翻译提示词 |
| `produceHotkeyRowState(binding:isRecording:label:)` | `Hotkey.swift` | 单行快捷键 UI 状态 |
| `translationLanguageOptions()` | 新增 | 返回语言选项列表 |
| `formatLanguage(_:)` | 新增 | 语言格式化显示 |

## 副作用清单

| 函数 | 位置 | 说明 |
|------|------|------|
| `impureHandleTranslationHotkey` | `AppDelegate.swift` | 翻译快捷键触发 |
| `impureMakeTranslationProvider()` | `AppDelegate.swift` | 构造翻译 LLM provider |
| `impureSaveTranslationConfig()` | `TranslationSettingsView` | 保存翻译配置 |
| 快捷键存储/注册 | `HotkeyIO.swift` | 翻译快捷键 I/O |

## 错误处理

| 场景 | 行为 |
|------|------|
| STT 返回 silence | 不处理，dismiss |
| STT 返回 failure | 显示 pasteFailed |
| LLM 调用失败 | 降级使用原始 STT 文本 |
| 翻译快捷键未设置 | 不响应，无操作 |

## 不涉及

- 不新增 PipelinePhase（润色/翻译在 transcribing 阶段内完成）
- 不改变 ModelSettingsView 或 Provider 选择逻辑
- 不改变录音/STT/粘贴逻辑
- 不影响 silence / failure 分支
