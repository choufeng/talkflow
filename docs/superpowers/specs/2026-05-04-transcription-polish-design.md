# 转写润色功能设计

## 概述

在语音转文字（STT）完成后，若用户开启"转写润色"，调用当前选中的 LLM Provider 对文本进行润色，再将结果写入剪贴板并粘贴。润色失败时降级使用原始 STT 文本。

## 配置扩展

`AppConfig.TranscriptionConfig` 新增 `polishPrompt` 字段：

```swift
struct TranscriptionConfig: Codable, Equatable {
    var useLLM: Bool = false
    var polishPrompt: String = ""  // 用户个性化润色要求
}
```

向后兼容：旧配置文件无此字段时 JSONDecoder 使用默认值 `""`。

## 固定提示词

纯函数 `makePolishingSystemPrompt()` 返回硬编码字符串，不可通过 UI 编辑：

```
去除中文口语中常见的无意义语气词和填充词，包括但不限于：
"嗯"、"啊"、"额"、"呃"、"那个"、"就是"、"然后"、"对吧"、"的话"、"怎么说呢"。
注意保留有实际语义的词语，例如"然后"在表示时间顺序时应保留。不要改变原文的语义和语气。

识别并修正文本中的错别字、同音错误和常见输入法导致的文字错误。
只修正明确的错误，不要对有歧义的内容做主观改动。
常见的同音错误示例："的/地/得"、"做/作"、"在/再"、"已/以"、"即/既"。
```

## 管线变更

### 当前流程

```
录音 → STT → .speech(text) → 写剪贴板 → Cmd+V
```

### 新流程

```
录音 → STT → .speech(text) →
  useLLM=true  → LLM 润色
    ├─ 成功 → 润色后文本
    └─ 失败 → 原始 text（降级，日志记录错误）
  useLLM=false → 原始 text
  → 写剪贴板 → Cmd+V
```

### LLM 调用

复用 `VertexAIIO`，构造 `PromptConfig` 拼接固定提示词与用户提示词：

```swift
let promptConfig = PromptConfig(
    defaultPrompt: makePolishingSystemPrompt(),
    userSupplement: config.transcription.polishPrompt
)
```

`mergePrompts()` 已有逻辑：无补充时仅返回默认提示词，有补充时以换行拼接。

请求仅包含一条 user message（原始 STT 文本），系统提示词由 `VertexMessageAdapter` 注入。

## UI 变更

`TranscriptionSettingsView` 在 checkbox 下方新增多行输入框：

- `NSScrollView` 包裹 `NSTextView`
- placeholder: `"输入个性化润色要求，例如：保持口语化风格"`
- 输入内容保存到 `config.transcription.polishPrompt`
- `impureLoadCheckboxState` 扩展为加载 polishPrompt 并设置 textView 内容
- checkbox toggle 同样触发 polishPrompt 字段保存

## 错误处理

| 场景 | 行为 |
|------|------|
| LLM 网络错误 | `[Pipeline]` 日志 → 降级用原始 STT 文本 |
| API 返回错误 | `[Pipeline]` 日志 → 降级用原始 STT 文本 |
| Token 过期 | `[Pipeline]` 日志 → 降级用原始 STT 文本 |
| 响应解析失败 | `[Pipeline]` 日志 → 降级用原始 STT 文本 |

任何异常均不中断管线，用户无感降级。

## 不涉及

- 不新增 PipelinePhase（润色在 transcribing 阶段内完成，状态窗无需感知）
- 不改变 ModelSettingsView 或 Provider 选择逻辑
- 不影响 silence / failure 分支
