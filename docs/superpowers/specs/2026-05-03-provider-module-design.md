# Provider 模块设计规范

> 状态：已确认 | 日期：2026-05-03

## 概述

为 TalkFlow 接入大语言模型对话补全能力。首版支持 Vertex AI（Google Cloud），架构预留多 Provider 扩展点。

核心流程：提示词（默认 + 用户补充）+ 用户语音文本 → LLM → 整理后文本。

## 架构

```
调用侧 (AppDelegate / ConversationManager)
    │ 依赖 ProviderIO 协议
    ▼
ProviderIO 协议  ────  MockProviderIO（测试）
    │ 实现
    ▼
VertexAIIO
    │
    ├── TokenProviderIO 协议  ────  MockTokenProviderIO（测试）
    │       │ 实现
    │       ▼
    │   JWTTokenProvider（SA 私钥 → JWT → OAuth2 token）
    │
    ├── ServiceAccount（纯数据类型）
    └── PromptConfig（纯数据类型）
```

## 目录结构

```
TalkFlow/
  IO/
    ProviderIO.swift            # 协议 + ProviderError
    TokenProviderIO.swift       # Token 获取协议（预留扩展）
    VertexAIIO.swift            # Vertex AI 实现
  Utils/
    ChatMessage.swift            # ChatMessage / ChatRequest / ChatResponse（ADT）
    PromptConfig.swift           # 提示词配置 + 合并纯函数
    ServiceAccount.swift         # SA JSON 解析（纯函数）
    VertexMessageAdapter.swift   # ChatMessage → Vertex contents 格式转换（纯函数）
```

## 数据类型（ADT）

### ChatMessage / ChatRequest / ChatResponse

```swift
enum MessageRole: String, Codable, Equatable {
    case system
    case user
}

struct ChatMessage: Codable, Equatable {
    let role: MessageRole
    let content: String
}

struct ChatRequest: Codable, Equatable {
    let messages: [ChatMessage]
}

struct ChatResponse: Equatable {
    let content: String
}
```

- `ChatRequest` 不暴露 `model` 字段——由各 Provider 实现内部固定。
- `ChatResponse` 仅含 `content`，错误通过 `throws` 传播。

### PromptConfig

```swift
struct PromptConfig: Codable, Equatable {
    let defaultPrompt: String
    var userSupplement: String
}

func mergePrompts(_ config: PromptConfig) -> String
```

- `defaultPrompt`：内置默认系统提示词。
- `userSupplement`：用户补充内容，持久化记录。
- `mergePrompts`：纯函数合并——补充为空则仅返回默认，否则用换行拼接。

### ServiceAccount

```swift
struct ServiceAccount: Equatable {
    let projectID: String
    let privateKey: String       // PEM 格式
    let clientEmail: String
    let tokenURI: String
}

func parseServiceAccount(fromPath path: String) throws -> ServiceAccount
```

- 纯函数：读 JSON → 解 `project_id` / `private_key` / `client_email` / `token_uri`。
- 不持有文件句柄或网络连接。

## 协议

### ProviderIO

```swift
protocol ProviderIO {
    func send(_ request: ChatRequest) async throws -> ChatResponse
}
```

极简协议——一个方法。新增 Provider 只需协议实现。

### TokenProviderIO

```swift
protocol TokenProviderIO {
    func getAccessToken() async throws -> String
}
```

- 隔离认证细节，使 `VertexAIIO` 核心逻辑可测。
- 首版仅 `JWTTokenProvider` 实现（SA 私钥 → JWT RS256 签名 → OAuth2 token）。
- 未来可增加 API Key 等认证方式。

## 错误类型

```swift
enum ProviderError: Error, Equatable {
    case authenticationFailed(String)
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case responseParsingFailed(String)
}
```

- Sum type（enum 带关联值），穷尽模式匹配。
- Equatable，测试断言友好。

## Vertex AI 实现

### REST 路径

```
POST https://{location}-aiplatform.googleapis.com/v1/
     projects/{projectID}/locations/{location}/
     publishers/google/models/{model}:generateContent
```

### 数据流

```
ChatRequest.messages
    → VertexMessageAdapter.convert → Vertex contents 格式（纯函数）
    → 注入 Authorization: Bearer {token}
    → URLSession POST
    → 解析 JSON → ChatResponse
```

### 配置项

- SA JSON 文件路径（唯一必填配置）
- location（如 `us-central1`，默认值）
- model（如 `gemini-2.0-flash-001`，默认值）
- promptConfig（默认提示词 + 用户补充）

## 测试

| 层级 | 被测对象 | 依赖 | 测试方式 |
|------|---------|------|----------|
| 纯函数 | `parseServiceAccount` | 无 | 合法 / 缺失字段 / 格式错误 |
| 纯函数 | `mergePrompts` | 无 | 有补充 / 无补充 / 空白 |
| 纯函数 | `VertexMessageAdapter.convert` | 无 | 单条 / 多条 / system+user 组合 |
| 纯函数 | `ChatMessage` Codable | 无 | 编解码往返 |
| 协议 | `MockProviderIO` | 无 | 预设返回值 / 抛错 / 记录调用 |
| 协议 | `MockTokenProviderIO` | 无 | 预设返回值 |
| 核心逻辑 | `VertexAIIO.send()` | `MockTokenProviderIO` | 请求构建 / 响应解析 / 错误映射 |

### VertexAIIO 测试覆盖点

- 正确调用 tokenProvider 获取 token
- 请求 URL / body 构建正确
- HTTP 200 → ChatResponse 解析正确
- HTTP 401/429/500 → `apiError`
- JSON 格式错误 → `responseParsingFailed`
- token 获取失败 → `authenticationFailed`

`JWTTokenProvider` 不做单元测试——仅封装 URLSession 调用，无独立业务逻辑。

## 非目标（首版）

- 流式输出（streaming）
- 多模态（图片/音频）
- 多轮对话记忆
- Provider 动态切换 UI
- 模型列表/管理
