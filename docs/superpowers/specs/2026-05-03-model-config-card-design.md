# 模型配置卡片设计

日期: 2026-05-03

## 概述

在 TalkFlow 主窗口新增「模型」卡片，支持选择 LLM 服务商并配置连接参数。

当前仅支持 Vertex AI，通过 ADC（Application Default Credentials）自动检测本机 gcloud 信息。

## UI 设计

```
┌─ 模型 ──────────────────────────────────────┐
│                                              │
│  模型服务:  [Vertex AI ▾]                    │
│                                              │
│  ── Vertex AI 配置 ──                        │
│  Project ID:   my-project-123  (只读)        │
│  模型名称:     [gemini-2.0-flash-001    ]    │
│                                              │
│  [ 测试连接 ]                                │
│  ✅ 连接成功 / ❌ 连接失败: <原因>            │
└──────────────────────────────────────────────┘
```

- 模型名称：自由文本输入框，默认 `gemini-2.0-flash-001`
- 连接测试按钮：独立一行，发送 hello 消息验证 API 可达
- Project ID：只读（从 ADC 自动检测），若检测失败则变为可编辑
- location：硬编码 `us-central1`，不暴露

## 架构

### 新增文件

| 文件 | 角色 |
|------|------|
| `TalkFlow/Views/ModelSettingsView.swift` | 模型卡片内容视图（下拉 + 配置区 + 测试按钮） |
| `TalkFlow/Utils/ADCParser.swift` | `parseADC` 纯函数（project_id 可选） |
| `TalkFlow/IO/ADCLoaderIO.swift` | `impureLoadADCFromDefaultPath()` 读 ADC 文件（副作用） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `TalkFlow/AppDelegate.swift` | 新增 ModelSettingsView 卡片 |
| `TalkFlow.xcodeproj/project.pbxproj` | 注册新文件 |

### 依赖关系

```
AppDelegate
  └─ CardView(title: "模型")
       └─ ModelSettingsView
            ├─ impureLoadADCFromDefaultPath() → ADCParsedInfo? (副作用 + 纯解析)
            └─ impureTestConnection() → 调用 VertexAIIO.send()
```

## 组件详情

### ADCParser（Utils，纯函数）

```swift
/// ADC 解析结果（project_id 可选）
struct ADCParsedInfo: Equatable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String
    let projectID: String?  // 可选
}

/// 从 ADC JSON 字典解析（纯函数）
func parseADC(from json: [String: Any]) throws -> ADCParsedInfo
```

### ADCLoaderIO（IO，副作用）

```swift
/// 读 ~/.config/gcloud/application_default_credentials.json
func impureLoadADCFromDefaultPath() -> ADCParsedInfo?
```

ADC JSON 格式：
```json
{
  "client_email": "xxx@developer.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----...",
  "token_uri": "https://oauth2.googleapis.com/token",
  "project_id": "my-project"  // 可选
}
```

### ModelSettingsView

NSView 子类，持有可变 UI 状态：

```swift
private var selectedProvider: ModelProvider = .vertexAI
private var detectedProjectID: String?   // ADC 自动检测结果
private var editedModelName: String = "gemini-2.0-flash-001"
private var connectionStatus: ConnectionTestStatus = .idle
private var isTesting = false
```

子视图：
- `providerDropdown`: NSPopUpButton（选项列表）
- `vertexAIContainer`: NSView（条件显示），内含：
  - `projectIDField`: NSTextField（只读，ADC 检测失败时变可编辑）
  - `modelNameField`: NSTextField（可编辑）
- `testButton`: NSButton（"测试连接"）
- `statusLabel`: NSTextField（连接结果文本/颜色）

### 连接测试

```swift
// ModelSettingsView 内
func impureTestConnection() {
    // 1. 读取当前 UI 配置
    let projectID = ...
    let modelName = ...
    // 2. 构造 VertexAIIO
    // 3. 发送 hello 消息
    // 4. 更新 connectionStatus → 渲染
}
```

测试消息：`ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])`

### ProviderConfig 模型

```swift
struct VertexAIConfig: Equatable {
    let projectID: String
    let modelName: String
    let location: String  // 硬编码 us-central1
}
```

## 副作用标记

遵循项目第 13 条铁律，所有副作用方法标 `impure` 前缀：
- `impureLoadADCFromDefaultPath()` — 文件读写
- `impureTestConnection()` — 网络请求
- UI 构建方法统一 `impureSetupUI()`、`impureRender()`

## 错误处理

| 场景 | 处理 |
|------|------|
| ADC 文件不存在 | Project ID 字段变可编辑，用户手动输入 |
| ADC 解析失败 | 同上 |
| 连接测试网络错误 | 显示 ❌ + 错误信息 |
| 连接测试认证失败 | 显示 ❌ + "认证失败: …" |
| 连接测试 API 错误 | 显示 ❌ + HTTP 状态码 + 错误信息 |

## 测试策略

- `ADCDetectorIO` 单元测试：有效/无效 ADC JSON、缺失字段、文件不存在
- `ModelSettingsView` 不单独测试（纯 UI 组件，配合手动测试）
- 边界：连接测试超时 10s
