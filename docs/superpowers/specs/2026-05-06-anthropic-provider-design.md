# AnthropicAIIO Provider 设计

日期：2026-05-06

## 概述

新增 `AnthropicAIIO`，实现 `ProviderIO` 协议，使用 Anthropic Messages API 兼容端点，为转写润色和翻译工作流提供替代 Provider。与现有 `VertexAIIO` 平行，用户在 ModelSettingsView 中切换。

## 架构

### 新增文件

| 文件 | 职责 |
|------|------|
| `IO/AnthropicAIIO.swift` | `ProviderIO` 实现，发起 Anthropic Messages API 请求 |
| `IO/AnthropicMessageAdapter.swift` | 纯函数：`ChatRequest` → Anthropic JSON 请求体，响应 JSON → 文本 |
| `IO/KeychainIO.swift` | 协议 `KeychainIO` + `SecItemKeychainIO` 实现，API Key 存取 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Utils/AppConfig.swift` | 新增 `AnthropicConfig`（baseUrl、modelName、thinkingBudget） |
| `Utils/ChatMessage.swift` | 不变 |
| `Views/ModelSettingsView.swift` | 新增 `ModelProvider.anthropic`，新增 Anthropic 配置容器 + 连接测试 |
| `AppDelegate.swift` | 新增 `impureMakeAnthropicProvider(polish:)` 工厂方法 |

### 依赖

```
AppConfig.AnthropicConfig ──→ ModelSettingsView (UI)
                                    │
AppDelegate ──→ KeychainIO ──→ AnthropicAIIO ──→ Anthropic Messages API
               PromptConfig ──→              │
                               AnthropicMessageAdapter (纯函数)
```

## AnthropicAIIO

### 构造函数

```swift
init(baseUrl: String,
     model: String,
     promptConfig: PromptConfig,
     thinkingBudget: Int = 0,
     keychainIO: KeychainIO,
     session: URLSession = .shared)
```

### send() 流程

1. 从 `keychainIO.get("com.talkflow.anthropic")` 读取 API Key
2. `mergePrompts(promptConfig)` → system prompt 文本
3. `AnthropicMessageAdapter.convert(messages, systemPrompt, thinkingBudget)` → 请求体
4. POST `{baseUrl}/v1/messages`
   - Headers: `x-api-key: {key}`, `anthropic-version: 2023-06-01`, `Content-Type: application/json`
5. `AnthropicMessageAdapter.parseResponse(data)` → 提取 `content[0].text`
6. 错误映射到 `ProviderError`

### 错误映射

| HTTP / 异常 | ProviderError |
|-------------|---------------|
| 401, 403 | `.authenticationFailed("API Key 无效或被拒")` |
| Keychain 读取失败 | `.authenticationFailed("未找到 API Key")` |
| 4xx | `.apiError(statusCode:, message:)` |
| 5xx | `.apiError(statusCode:, message:)` |
| 网络错误 | `.networkError(...)` |
| JSON 解析失败 | `.responseParsingFailed(...)` |

### Thinking 参数

- `thinkingBudget == 0`: `"thinking": { "type": "disabled" }`
- `thinkingBudget > 0`: `"thinking": { "type": "enabled", "budget_tokens": <thinkingBudget> }`

## AnthropicMessageAdapter（纯函数）

### convert()

```swift
static func convert(
    messages: [ChatMessage],
    systemPrompt: String,
    thinkingBudget: Int
) -> AnthropicRequestBody
```

`AnthropicRequestBody` 为 Codable struct:

```json
{
  "model": "{model}",
  "max_tokens": 4096,
  "system": "{systemPrompt}",
  "messages": [
    { "role": "user", "content": "..." }
  ],
  "thinking": { "type": "disabled" }
}
```

- `messages` 仅包含 role 为 `.user` 的消息，content 直接映射
- `system` 为 Anthropic API 顶层字段，非 messages 数组成员

### parseResponse()

```swift
static func parseResponse(_ data: Data) throws -> String
```

解析 Anthropic Messages API 成功响应，提取 `content[0].text`。若 `content` 为空或无 text 类型块，抛 `.responseParsingFailed`。

## KeychainIO

### 协议

```swift
protocol KeychainIO {
    func get(_ key: String) throws -> String
    func set(_ key: String, value: String) throws
    func delete(_ key: String) throws
}
```

### 默认实现

`SecItemKeychainIO` 使用 Keychain Services API：

- 存储类型：`kSecClassGenericPassword`
- Service: `com.talkflow.anthropic`
- Account: 传入的 `key` 参数
- 操作：`SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete`

API Key 在 `ModelSettingsView` 中通过 `NSSecureTextField` 输入，保存时写入 Keychain。读取仅在 `AnthropicAIIO.send()` 调用时发生。

## 配置

### AppConfig 新增

```swift
struct AnthropicConfig: Codable, Equatable {
    var baseUrl: String = "https://api.anthropic.com"
    var modelName: String = "claude-sonnet-4-20250514"
    var thinkingBudget: Int = 0
}
```

`AppConfig` 新增 `var anthropic: AnthropicConfig = AnthropicConfig()`。

API Key **不**存储在 AppConfig 中，仅在 Keychain。

### ModelProvider 枚举

```swift
enum ModelProvider: String, CaseIterable {
    case vertexAI = "Vertex AI"
    case anthropic = "Anthropic"
}
```

## Provider 选择存储

`AppConfig` 新增 `var selectedProvider: String = "vertexAI"`，存储用户对 provider 的选择。`ModelSettingsView` 在 `impureProviderChanged()` 中写入。`AppDelegate` 的工厂方法根据此字段分支。

## UI

### ModelSettingsView 变更

- 新增 `anthropicContainer`（NSView），条件显示当 `selectedProvider == .anthropic`
- 输入框：
  - Base URL: `NSTextField`，默认值 `https://api.anthropic.com`
  - API Key: `NSSecureTextField`
  - Model ID: `NSTextField`
- 连接测试按钮：与 Vertex AI 测试逻辑平行，创建临时 `AnthropicAIIO` 发 "hi" 验证连接
- `controlTextDidEndEditing` 保存 `AppConfig.anthropic` + Keychain（仅 API Key 字段）
- UI 布局与 `vertexAIContainer` 平行，label 文字对应修改

### Vertex AI 容器默认隐藏

当首次打开设置窗口且无 ADC 凭据时，可保持 `vertexAIContainer` 可见。选择 Anthropic 后互斥显示。此行为与现有逻辑一致：`vertexAIContainer.isHidden` 由 `selectedProvider` 驱动。

## AppDelegate 变更

### 工厂方法

```swift
private func impureMakeAnthropicProvider(polish: Bool) -> AnthropicAIIO? {
    let config = impureLoadAppConfig()
    guard !config.anthropic.baseUrl.isEmpty,
          !config.anthropic.modelName.isEmpty else { return nil }

    let promptConfig = polish
        ? PromptConfig(defaultPrompt: makePolishingSystemPrompt(),
                       userSupplement: config.transcription.polishPrompt)
        : PromptConfig(
            defaultPrompt: mergeTranslationPrompts(
                polishConfig: PromptConfig(
                    defaultPrompt: makePolishingSystemPrompt(),
                    userSupplement: config.transcription.polishPrompt
                ),
                translationConfig: PromptConfig(
                    defaultPrompt: makeTranslationSystemPrompt(language: config.transcription.translationLanguage),
                    userSupplement: config.transcription.translationPrompt
                )
            ),
            userSupplement: "")

    return AnthropicAIIO(
        baseUrl: config.anthropic.baseUrl,
        model: config.anthropic.modelName,
        promptConfig: promptConfig,
        thinkingBudget: config.anthropic.thinkingBudget,
        keychainIO: SecItemKeychainIO()
    )
}
```

### 调用方修改

`impureMakePolishingProvider()` 和 `impureMakeTranslationProvider()` 从 `AppConfig.selectedProvider` 读取并分支：

- `"vertexAI"` 或未识别 → 现有逻辑不变
- `"anthropic"` → 调用 `impureMakeAnthropicProvider(polish:)`

## 测试要点

### 单元测试

| 测试 | 内容 |
|------|------|
| `AnthropicMessageAdapterTests` | convert() 输出格式验证（system 顶层、user 消息映射、thinking 参数） |
| `AnthropicMessageAdapterTests` | parseResponse() 正常/异常 JSON 解析 |
| `AnthropicAIIOTests` | 使用 MockURLProtocol，验证请求 URL/Headers/Body，模拟成功/失败响应 |

### 集成测试

- 用真实 API 端点验证完整 `send()` 流程
- 连接测试按钮在 ModelSettingsView 中验证 Keychain 读写 + API 连通性

## 不变部分

- `ProviderIO` 协议不变
- `ChatRequest` / `ChatMessage` / `ChatResponse` 不变
- `PromptConfig` / `mergePrompts` / `mergeTranslationPrompts` 不变
- `PromptOptimizerIO` / `LLMEvaluatorIO` 不变（它们依赖 `ProviderIO` 协议）
- `SenseVoiceIO` / `AudioRecorderIO` / `HotkeyIO` / `PasteIO` / `ClipboardIO` 无关
