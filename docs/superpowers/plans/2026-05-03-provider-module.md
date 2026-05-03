# Provider 模块实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 TalkFlow LLM Provider 模块——首版接入 Vertex AI，架构预留多 Provider 扩展点。

**Architecture:** `ProviderIO` 协议定义对话补全接口，`VertexAIIO` 实现 Google Cloud Vertex AI REST 调用。认证通过 ServiceAccount JSON 文件 + JWT/OAuth2。提示词由默认配置与用户补充合并。纯函数层（ADT、解析、格式转换）与副作用层（网络、Token 获取）严格分离。

**Tech Stack:** Swift 5.9+, macOS 14.0, Foundation (URLSession, JSONDecoder), Security (SecKey for JWT RS256), CryptoKit (SHA-256)

---

### Task 1: ChatMessage ADT 数据类型

**Files:**
- Create: `TalkFlow/Utils/ChatMessage.swift`
- Create: `TalkFlowTests/Pure/ChatMessageTests.swift`

- [ ] **Step 1: 创建 ChatMessage.swift**

```swift
import Foundation

// MARK: - 消息角色

enum MessageRole: String, Codable, Equatable {
    case system
    case user
}

// MARK: - 聊天消息

struct ChatMessage: Codable, Equatable {
    let role: MessageRole
    let content: String
}

// MARK: - 聊天请求

struct ChatRequest: Codable, Equatable {
    let messages: [ChatMessage]
}

// MARK: - 聊天响应

struct ChatResponse: Equatable {
    let content: String
}
```

- [ ] **Step 2: 创建 ChatMessageTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class ChatMessageTests: XCTestCase {

    // MARK: - Codable 往返测试

    func test_messageCodable_roundTrip_system() throws {
        let msg = ChatMessage(role: .system, content: "你是一个助手")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded, msg)
    }

    func test_messageCodable_roundTrip_user() throws {
        let msg = ChatMessage(role: .user, content: "你好")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded, msg)
    }

    func test_messageJSON_representation() throws {
        let msg = ChatMessage(role: .user, content: "hello")
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(json["role"], "user")
        XCTAssertEqual(json["content"], "hello")
    }

    // MARK: - ChatRequest Codable

    func test_requestCodable_roundTrip() throws {
        let req = ChatRequest(messages: [
            ChatMessage(role: .system, content: "system"),
            ChatMessage(role: .user, content: "user"),
        ])
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: data)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].role, .system)
        XCTAssertEqual(decoded.messages[1].role, .user)
    }

    func test_requestEmpty_messages() {
        let req = ChatRequest(messages: [])
        XCTAssertTrue(req.messages.isEmpty)
    }
}
```

- [ ] **Step 3: 添加 ChatMessage.swift 到 Xcode 项目**

用 Xcode 或手动编辑 `project.pbxproj` 将 `TalkFlow/Utils/ChatMessage.swift` 加入 TalkFlow target 编译，`TalkFlowTests/Pure/ChatMessageTests.swift` 加入 TalkFlowTests target。

- [ ] **Step 4: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(ChatMessage|TEST|passed|failed)"
```

期望：所有 ChatMessageTests 通过。

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/ChatMessage.swift TalkFlowTests/Pure/ChatMessageTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ChatMessage / ChatRequest / ChatResponse ADT 数据类型"
```

---

### Task 2: PromptConfig 提示词配置

**Files:**
- Create: `TalkFlow/Utils/PromptConfig.swift`
- Create: `TalkFlowTests/Pure/PromptConfigTests.swift`

- [ ] **Step 1: 创建 PromptConfig.swift**

```swift
import Foundation

/// 提示词配置：默认系统提示词 + 用户补充内容
struct PromptConfig: Codable, Equatable {
    let defaultPrompt: String
    var userSupplement: String
}

// MARK: - 纯函数

/// 合并默认提示词与用户补充
/// - 无补充时仅返回默认提示词
/// - 有补充时以换行拼接
func mergePrompts(_ config: PromptConfig) -> String {
    if config.userSupplement.isEmpty {
        return config.defaultPrompt
    }
    return "\(config.defaultPrompt)\n\(config.userSupplement)"
}
```

- [ ] **Step 2: 创建 PromptConfigTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class PromptConfigTests: XCTestCase {

    func test_merge_noSupplement_returnsDefault() {
        let config = PromptConfig(defaultPrompt: "你是翻译助手", userSupplement: "")
        let result = mergePrompts(config)
        XCTAssertEqual(result, "你是翻译助手")
    }

    func test_merge_withSupplement_joinsWithNewline() {
        let config = PromptConfig(defaultPrompt: "你是翻译助手", userSupplement: "请翻译成英文")
        let result = mergePrompts(config)
        XCTAssertEqual(result, "你是翻译助手\n请翻译成英文")
    }

    func test_merge_supplementOnlyWhitespace_returnsDefault() {
        let config = PromptConfig(defaultPrompt: "你是翻译助手", userSupplement: "   ")
        let result = mergePrompts(config)
        // userSupplement 含空格但非空——视为有补充
        XCTAssertEqual(result, "你是翻译助手\n   ")
    }

    func test_codable_roundTrip() throws {
        var config = PromptConfig(defaultPrompt: "你是助手", userSupplement: "用中文回答")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PromptConfig.self, from: data)
        XCTAssertEqual(decoded.defaultPrompt, config.defaultPrompt)
        XCTAssertEqual(decoded.userSupplement, config.userSupplement)
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

- [ ] **Step 4: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(PromptConfig|TEST|passed|failed)"
```

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/PromptConfig.swift TalkFlowTests/Pure/PromptConfigTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: PromptConfig 提示词配置 + mergePrompts 纯函数"
```

---

### Task 3: ServiceAccount JSON 解析

**Files:**
- Create: `TalkFlow/Utils/ServiceAccount.swift`
- Create: `TalkFlowTests/Pure/ServiceAccountTests.swift`

- [ ] **Step 1: 创建 ServiceAccount.swift**

```swift
import Foundation

/// Google Cloud Service Account 信息（从 JSON 密钥文件解析）
struct ServiceAccount: Equatable {
    let projectID: String
    let privateKey: String       // PEM 格式，含 -----BEGIN/END PRIVATE KEY-----
    let clientEmail: String
    let tokenURI: String
}

// MARK: - 错误

enum ServiceAccountError: Error, Equatable {
    case fileNotFound(path: String)
    case invalidJSON
    case missingField(String)
}

// MARK: - 纯函数解析

/// 从 Service Account JSON 文件路径解析
func parseServiceAccount(fromPath path: String) throws -> ServiceAccount {
    guard FileManager.default.fileExists(atPath: path) else {
        throw ServiceAccountError.fileNotFound(path: path)
    }

    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw ServiceAccountError.fileNotFound(path: path)
    }

    let json: [String: Any]
    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceAccountError.invalidJSON
        }
        json = dict
    } catch {
        throw ServiceAccountError.invalidJSON
    }

    guard let projectID = json["project_id"] as? String else {
        throw ServiceAccountError.missingField("project_id")
    }
    guard let privateKey = json["private_key"] as? String else {
        throw ServiceAccountError.missingField("private_key")
    }
    guard let clientEmail = json["client_email"] as? String else {
        throw ServiceAccountError.missingField("client_email")
    }
    guard let tokenURI = json["token_uri"] as? String else {
        throw ServiceAccountError.missingField("token_uri")
    }

    return ServiceAccount(
        projectID: projectID,
        privateKey: privateKey,
        clientEmail: clientEmail,
        tokenURI: tokenURI
    )
}
```

- [ ] **Step 2: 创建 ServiceAccountTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class ServiceAccountTests: XCTestCase {

    // 合法 SA JSON 示例
    private func validSAJSON() -> [String: Any] {
        return [
            "type": "service_account",
            "project_id": "my-project-123",
            "private_key_id": "abc123",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADAN...\n-----END PRIVATE KEY-----\n",
            "client_email": "test@my-project-123.iam.gserviceaccount.com",
            "client_id": "12345",
            "token_uri": "https://oauth2.googleapis.com/token",
        ]
    }

    private func writeTempJSON(_ dict: [String: Any]) -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".json"
        let data = try! JSONSerialization.data(withJSONObject: dict)
        try! data.write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - 合法解析

    func test_parse_validSA_success() throws {
        let path = writeTempJSON(validSAJSON())
        let sa = try parseServiceAccount(fromPath: path)
        XCTAssertEqual(sa.projectID, "my-project-123")
        XCTAssertTrue(sa.privateKey.contains("BEGIN PRIVATE KEY"))
        XCTAssertEqual(sa.clientEmail, "test@my-project-123.iam.gserviceaccount.com")
        XCTAssertEqual(sa.tokenURI, "https://oauth2.googleapis.com/token")
    }

    // MARK: - 文件不存在

    func test_parse_fileNotFound_throws() {
        XCTAssertThrowsError(try parseServiceAccount(fromPath: "/nonexistent/sa.json")) { error in
            guard case ServiceAccountError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound")
            }
        }
    }

    // MARK: - 缺失字段

    func test_parse_missingProjectID_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "project_id")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("project_id") = error else {
                return XCTFail("Expected missingField project_id")
            }
        }
    }

    func test_parse_missingPrivateKey_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "private_key")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("private_key") = error else {
                return XCTFail("Expected missingField private_key")
            }
        }
    }

    func test_parse_missingClientEmail_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "client_email")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("client_email") = error else {
                return XCTFail("Expected missingField client_email")
            }
        }
    }

    func test_parse_missingTokenURI_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "token_uri")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("token_uri") = error else {
                return XCTFail("Expected missingField token_uri")
            }
        }
    }

    // MARK: - 格式错误

    func test_parse_invalidJSON_throws() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON")
            }
        }
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

- [ ] **Step 4: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(ServiceAccount|TEST|passed|failed)"
```

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/ServiceAccount.swift TalkFlowTests/Pure/ServiceAccountTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ServiceAccount JSON 解析纯函数"
```

---

### Task 4: VertexMessageAdapter 消息格式转换

**Files:**
- Create: `TalkFlow/Utils/VertexMessageAdapter.swift`
- Create: `TalkFlowTests/Pure/VertexMessageAdapterTests.swift`

- [ ] **Step 1: 创建 VertexMessageAdapter.swift**

```swift
import Foundation

/// Vertex AI 消息格式适配器
/// 将 ChatMessage 数组转换为 Vertex AI generateContent 请求格式
enum VertexMessageAdapter {

    /// 单条消息内容部分
    struct ContentPart: Codable, Equatable {
        let text: String
    }

    /// 单条消息
    struct Content: Codable, Equatable {
        let role: String
        let parts: [ContentPart]
    }

    /// 系统指令
    struct SystemInstruction: Codable, Equatable {
        let parts: [ContentPart]
    }

    /// Vertex AI 请求体
    struct RequestBody: Codable, Equatable {
        let contents: [Content]
        let systemInstruction: SystemInstruction?
    }

    // MARK: - 纯函数转换

    /// 将 ChatMessage 数组转换为 Vertex RequestBody
    static func convert(messages: [ChatMessage], systemPrompt: String) -> RequestBody {
        let contents = messages
            .filter { $0.role == .user }
            .map { msg in
                Content(role: "user", parts: [ContentPart(text: msg.content)])
            }

        let sysInstruction: SystemInstruction?
        if !systemPrompt.isEmpty {
            sysInstruction = SystemInstruction(parts: [ContentPart(text: systemPrompt)])
        } else {
            sysInstruction = nil
        }

        return RequestBody(contents: contents, systemInstruction: sysInstruction)
    }
}

// MARK: - 响应解析

/// Vertex AI generateContent 响应的 candidates 部分
struct VertexCandidate: Codable {
    struct ResponseContent: Codable {
        struct Part: Codable {
            let text: String
        }
        let role: String
        let parts: [Part]
    }
    let content: ResponseContent
}

struct VertexGenerateContentResponse: Codable {
    let candidates: [VertexCandidate]
}

/// 从 Vertex AI JSON 响应解析 ChatResponse
func parseVertexResponse(data: Data) throws -> ChatResponse {
    let decoder = JSONDecoder()
    let response = try decoder.decode(VertexGenerateContentResponse.self, from: data)

    guard let firstCandidate = response.candidates.first else {
        throw ProviderError.responseParsingFailed("响应中无候选内容")
    }

    let text = firstCandidate.content.parts.map(\.text).joined(separator: "\n")
    guard !text.isEmpty else {
        throw ProviderError.responseParsingFailed("候选内容为空")
    }

    return ChatResponse(content: text)
}
```

- [ ] **Step 2: 创建 VertexMessageAdapterTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class VertexMessageAdapterTests: XCTestCase {

    // MARK: - 请求转换

    func test_convert_singleUserMessage() {
        let messages = [ChatMessage(role: .user, content: "你好")]
        let body = VertexMessageAdapter.convert(messages: messages, systemPrompt: "你是助手")

        XCTAssertEqual(body.contents.count, 1)
        XCTAssertEqual(body.contents[0].role, "user")
        XCTAssertEqual(body.contents[0].parts[0].text, "你好")
        XCTAssertNotNil(body.systemInstruction)
        XCTAssertEqual(body.systemInstruction?.parts[0].text, "你是助手")
    }

    func test_convert_multipleUserMessages() {
        let messages = [
            ChatMessage(role: .user, content: "第一句"),
            ChatMessage(role: .user, content: "第二句"),
        ]
        let body = VertexMessageAdapter.convert(messages: messages, systemPrompt: "你是助手")

        XCTAssertEqual(body.contents.count, 2)
        XCTAssertEqual(body.contents[0].parts[0].text, "第一句")
        XCTAssertEqual(body.contents[1].parts[0].text, "第二句")
    }

    func test_convert_filtersSystemMessages() {
        let messages = [
            ChatMessage(role: .system, content: "内部指令"),
            ChatMessage(role: .user, content: "用户消息"),
        ]
        let body = VertexMessageAdapter.convert(messages: messages, systemPrompt: "你是助手")

        XCTAssertEqual(body.contents.count, 1)
        XCTAssertEqual(body.contents[0].parts[0].text, "用户消息")
    }

    func test_convert_emptySystemPrompt_noInstruction() {
        let messages = [ChatMessage(role: .user, content: "hello")]
        let body = VertexMessageAdapter.convert(messages: messages, systemPrompt: "")

        XCTAssertNil(body.systemInstruction)
    }

    func test_convert_emptyMessages() {
        let body = VertexMessageAdapter.convert(messages: [], systemPrompt: "你是助手")
        XCTAssertTrue(body.contents.isEmpty)
        XCTAssertNotNil(body.systemInstruction)
    }

    // MARK: - 响应解析

    func test_parse_response_success() throws {
        let json = """
        {
          "candidates": [
            {
              "content": {
                "role": "model",
                "parts": [{"text": "你好！有什么可以帮你的？"}]
              }
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try parseVertexResponse(data: data)
        XCTAssertEqual(response.content, "你好！有什么可以帮你的？")
    }

    func test_parse_response_multiPart_success() throws {
        let json = """
        {
          "candidates": [
            {
              "content": {
                "role": "model",
                "parts": [{"text": "第一段"}, {"text": "第二段"}]
              }
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try parseVertexResponse(data: data)
        XCTAssertEqual(response.content, "第一段\n第二段")
    }

    func test_parse_response_emptyCandidates_throws() {
        let json = """
        {"candidates": []}
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try parseVertexResponse(data: data)) { error in
            guard case ProviderError.responseParsingFailed = error else {
                return XCTFail("Expected responseParsingFailed")
            }
        }
    }

    func test_parse_response_malformedJSON_throws() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try parseVertexResponse(data: data)) { error in
            guard case ProviderError.responseParsingFailed = error else {
                return XCTFail("Expected responseParsingFailed")
            }
        }
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

- [ ] **Step 4: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(VertexMessage|VertexGenerate|TEST|passed|failed)"
```

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/VertexMessageAdapter.swift TalkFlowTests/Pure/VertexMessageAdapterTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: VertexMessageAdapter 消息格式转换 + 响应解析"
```

---

### Task 5: ProviderIO 协议 + ProviderError

**Files:**
- Create: `TalkFlow/IO/ProviderIO.swift`

- [ ] **Step 1: 创建 ProviderIO.swift**

```swift
import Foundation

// MARK: - ProviderIO 协议

protocol ProviderIO {
    /// 发送对话请求，返回模型输出文本
    /// - Parameter request: 包含了消息列表的请求
    /// - Returns: 模型响应的文本内容
    /// - Throws: ProviderError
    func send(_ request: ChatRequest) async throws -> ChatResponse
}

// MARK: - Provider 错误类型

enum ProviderError: Error, Equatable {
    /// 认证失败（SA 文件不存在 / 格式错误 / 私钥无效 / token 获取失败）
    case authenticationFailed(String)
    /// 网络错误（连接失败 / 超时等）
    case networkError(String)
    /// API 返回错误（含 HTTP 状态码与错误信息）
    case apiError(statusCode: Int, message: String)
    /// 响应解析失败
    case responseParsingFailed(String)
}
```

- [ ] **Step 2: 添加到 Xcode 项目**

- [ ] **Step 3: 运行测试验证编译通过（无新增测试——仅协议定义）**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(TEST|passed|failed|BUILD)"
```

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/IO/ProviderIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ProviderIO 协议 + ProviderError 错误类型"
```

---

### Task 6: MockProviderIO + ProviderIO 协议测试

**Files:**
- Create: `TalkFlowTests/Mocks/MockProviderIO.swift`
- Create: `TalkFlowTests/IO/ProviderIOTests.swift`

- [ ] **Step 1: 创建 MockProviderIO.swift**

```swift
import Foundation
@testable import TalkFlow

final class MockProviderIO: ProviderIO {

    var sendCallCount = 0
    var sendLastRequest: ChatRequest?

    var stubbedResponse: ChatResponse?
    var stubbedError: ProviderError?

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        sendCallCount += 1
        sendLastRequest = request

        if let error = stubbedError {
            throw error
        }

        guard let response = stubbedResponse else {
            throw ProviderError.networkError("Mock: 未预设返回值")
        }

        return response
    }
}
```

- [ ] **Step 2: 创建 ProviderIOTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class ProviderIOTests: XCTestCase {

    // MARK: - MockProviderIO

    func test_mock_returnsStubbedResponse() async throws {
        let mock = MockProviderIO()
        mock.stubbedResponse = ChatResponse(content: "mock response")

        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hello")])
        let response = try await mock.send(request)

        XCTAssertEqual(response.content, "mock response")
        XCTAssertEqual(mock.sendCallCount, 1)
    }

    func test_mock_throwsStubbedError() async {
        let mock = MockProviderIO()
        mock.stubbedError = .apiError(statusCode: 500, message: "Server error")

        let request = ChatRequest(messages: [])
        do {
            _ = try await mock.send(request)
            XCTFail("Expected error")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .apiError(statusCode: 500, message: "Server error"))
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func test_mock_recordsLastRequest() async throws {
        let mock = MockProviderIO()
        mock.stubbedResponse = ChatResponse(content: "")

        let request = ChatRequest(messages: [
            ChatMessage(role: .user, content: "test message"),
        ])
        _ = try await mock.send(request)

        XCTAssertEqual(mock.sendLastRequest?.messages.count, 1)
        XCTAssertEqual(mock.sendLastRequest?.messages[0].content, "test message")
    }

    func test_mock_throwsWhenNoStubSet() async {
        let mock = MockProviderIO()
        let request = ChatRequest(messages: [])
        do {
            _ = try await mock.send(request)
            XCTFail("Expected error")
        } catch {
            // 预期抛错
        }
    }

    // MARK: - ProviderError Equatable

    func test_providerError_authenticationFailed_equatable() {
        let a = ProviderError.authenticationFailed("bad key")
        let b = ProviderError.authenticationFailed("bad key")
        let c = ProviderError.authenticationFailed("other")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_providerError_apiError_equatable() {
        let a = ProviderError.apiError(statusCode: 429, message: "rate limit")
        let b = ProviderError.apiError(statusCode: 429, message: "rate limit")
        let c = ProviderError.apiError(statusCode: 500, message: "rate limit")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

- [ ] **Step 4: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(ProviderIO|TEST|passed|failed)"
```

- [ ] **Step 5: 提交**

```bash
git add TalkFlowTests/Mocks/MockProviderIO.swift TalkFlowTests/IO/ProviderIOTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: MockProviderIO + ProviderIO 协议测试"
```

---

### Task 7: TokenProviderIO 协议 + MockTokenProviderIO

**Files:**
- Create: `TalkFlow/IO/TokenProviderIO.swift`
- Create: `TalkFlowTests/Mocks/MockTokenProviderIO.swift`

- [ ] **Step 1: 创建 TokenProviderIO.swift**

```swift
import Foundation

protocol TokenProviderIO {
    /// 获取访问令牌
    /// - Returns: Bearer token 字符串
    /// - Throws: ProviderError
    func getAccessToken() async throws -> String
}
```

- [ ] **Step 2: 创建 MockTokenProviderIO.swift**

```swift
import Foundation
@testable import TalkFlow

final class MockTokenProviderIO: TokenProviderIO {

    var getTokenCallCount = 0

    var stubbedToken: String?
    var stubbedError: ProviderError?

    func getAccessToken() async throws -> String {
        getTokenCallCount += 1

        if let error = stubbedError {
            throw error
        }

        guard let token = stubbedToken else {
            throw ProviderError.authenticationFailed("Mock: 未预设 token")
        }

        return token
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

- [ ] **Step 4: 运行测试验证编译通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(TEST|passed|failed|BUILD)"
```

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/IO/TokenProviderIO.swift TalkFlowTests/Mocks/MockTokenProviderIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: TokenProviderIO 协议 + MockTokenProviderIO"
```

---

### Task 8: JWTTokenProvider 实现（JWT + OAuth2 Token 获取）

**Files:**
- Create: `TalkFlow/IO/JWTTokenProvider.swift`

- [ ] **Step 1: 创建 JWTTokenProvider.swift**

```swift
import Foundation
import Security
import CryptoKit

/// 基于 Google Service Account 的 JWT + OAuth2 令牌获取器
final class JWTTokenProvider: TokenProviderIO {

    private let sa: ServiceAccount
    private let scope: String
    private let session: URLSession

    init(sa: ServiceAccount,
         scope: String = "https://www.googleapis.com/auth/cloud-platform",
         session: URLSession = .shared) {
        self.sa = sa
        self.scope = scope
        self.session = session
    }

    func getAccessToken() async throws -> String {
        let jwt = try createJWT()
        return try await exchangeJWTForToken(jwt)
    }

    // MARK: - JWT 生成

    private func createJWT() throws -> String {
        let header = try base64URLEncode(json: ["alg": "RS256", "typ": "JWT"])

        let now = Int(Date().timeIntervalSince1970)
        let claimSet: [String: Any] = [
            "iss": sa.clientEmail,
            "scope": scope,
            "aud": sa.tokenURI,
            "exp": now + 3600,
            "iat": now,
        ]
        let payload = try base64URLEncode(json: claimSet)

        let signingInput = "\(header).\(payload)"
        guard let signature = try signRS256(input: signingInput, privateKeyPEM: sa.privateKey) else {
            throw ProviderError.authenticationFailed("JWT 签名失败")
        }

        return "\(signingInput).\(signature)"
    }

    // MARK: - OAuth2 token 交换

    private func exchangeJWTForToken(_ jwt: String) async throws -> String {
        var request = URLRequest(url: URL(string: sa.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: jwt),
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.networkError("Token 请求失败: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("非 HTTP 响应")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.authenticationFailed("Token 交换失败 (HTTP \(httpResponse.statusCode)): \(body.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw ProviderError.authenticationFailed("响应中缺少 access_token")
        }

        return token
    }

    // MARK: - RSA 签名

    private func signRS256(input: String, privateKeyPEM: String) throws -> String? {
        // 去掉 PEM 头尾，提取 Base64 内容
        let lines = privateKeyPEM
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64Key = lines.joined()

        guard let keyData = Data(base64Encoded: base64Key) else {
            throw ProviderError.authenticationFailed("私钥 Base64 解码失败")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) else {
            throw ProviderError.authenticationFailed("SecKey 创建失败")
        }

        let inputData = Data(input.utf8)
        var error: Unmanaged<CFError>?

        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            inputData as CFData,
            &error
        ) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            throw ProviderError.authenticationFailed("RSA 签名失败: \(errMsg)")
        }

        return (signature as Data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Base64URL 编码

    private func base64URLEncode(json dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 2: 添加到 Xcode 项目**

- [ ] **Step 3: 运行测试验证编译通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(TEST|passed|failed|BUILD)"
```

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/IO/JWTTokenProvider.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: JWTTokenProvider — SA 私钥 JWT 签名 + OAuth2 Token 交换"
```

---

### Task 9: VertexAIIO 实现

**Files:**
- Create: `TalkFlow/IO/VertexAIIO.swift`

- [ ] **Step 1: 创建 VertexAIIO.swift**

```swift
import Foundation

final class VertexAIIO: ProviderIO {

    private let tokenProvider: TokenProviderIO
    private let projectID: String
    private let location: String
    private let model: String
    private let promptConfig: PromptConfig
    private let session: URLSession

    init(tokenProvider: TokenProviderIO,
         projectID: String,
         location: String = "us-central1",
         model: String = "gemini-2.0-flash-001",
         promptConfig: PromptConfig,
         session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.projectID = projectID
        self.location = location
        self.model = model
        self.promptConfig = promptConfig
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        let token: String
        do {
            token = try await tokenProvider.getAccessToken()
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.authenticationFailed("Token 获取失败: \(error.localizedDescription)")
        }

        let systemPrompt = mergePrompts(promptConfig)
        let body = VertexMessageAdapter.convert(messages: request.messages, systemPrompt: systemPrompt)

        let urlString = "https://\(location)-aiplatform.googleapis.com/v1/projects/\(projectID)/locations/\(location)/publishers/google/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw ProviderError.networkError("无效 URL: \(urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ProviderError.networkError("请求失败: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("非 HTTP 响应")
        }

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.apiError(statusCode: httpResponse.statusCode, message: bodyText.prefix(500).description)
        }

        do {
            return try parseVertexResponse(data: data)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.responseParsingFailed("解析失败: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: 添加到 Xcode 项目**

- [ ] **Step 3: 运行测试验证编译通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(TEST|passed|failed|BUILD)"
```

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/IO/VertexAIIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: VertexAIIO — Vertex AI Gemini 对话补全实现"
```

---

### Task 10: VertexAIIO 单元测试

**Files:**
- Create: `TalkFlowTests/IO/VertexAIOTests.swift`

- [ ] **Step 1: 创建 VertexAIOTests.swift**

```swift
import XCTest
@testable import TalkFlow

final class VertexAIOTests: XCTestCase {

    private func makeVertexAI(
        mockToken: MockTokenProviderIO,
        projectID: String = "test-project",
        location: String = "us-central1",
        model: String = "gemini-2.0-flash-001"
    ) -> VertexAIIO {
        let config = PromptConfig(defaultPrompt: "你是助手", userSupplement: "")
        return VertexAIIO(
            tokenProvider: mockToken,
            projectID: projectID,
            location: location,
            model: model,
            promptConfig: config,
            session: .shared
        )
    }

    // MARK: - Token 失败

    func test_send_throwsAuthenticationFailed_whenTokenFails() async {
        let mockToken = MockTokenProviderIO()
        mockToken.stubbedError = .authenticationFailed("SA 文件无效")

        let vertex = makeVertexAI(mockToken: mockToken)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])

        do {
            _ = try await vertex.send(request)
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .authenticationFailed("SA 文件无效"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

（注：成功路径及 HTTP 错误测试依赖 MockURLProtocol，在 Step 3 补充）

- [ ] **Step 2: 创建 MockURLProtocol 辅助 —— `TalkFlowTests/Helpers/URLProtocolMock.swift`**

```swift
import Foundation

final class MockURLProtocol: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("MockURLProtocol: requestHandler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 3: 补充 VertexAIOTests.swift 网络相关测试**

在 `VertexAIOTests` 类中追加以下测试方法：

```swift
func test_send_returnsChatResponse_whenAPI200() async throws {
    let mockToken = MockTokenProviderIO()
    mockToken.stubbedToken = "test-token"

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.requestHandler = { request in
        // 验证 Authorization header
        let auth = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Bearer test-token")
        XCTAssertEqual(request.httpMethod, "POST")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let responseJSON = """
        {
          "candidates": [
            {
              "content": {
                "role": "model",
                "parts": [{"text": "你好！有什么可以帮你的？"}]
              }
            }
          ]
        }
        """
        return (response, responseJSON.data(using: .utf8)!)
    }

    let vertex = VertexAIIO(
        tokenProvider: mockToken,
        projectID: "test-project",
        location: "us-central1",
        model: "gemini-2.0-flash-001",
        promptConfig: PromptConfig(defaultPrompt: "你是助手", userSupplement: ""),
        session: session
    )

    let request = ChatRequest(messages: [ChatMessage(role: .user, content: "你好")])
    let response = try await vertex.send(request)

    XCTAssertEqual(response.content, "你好！有什么可以帮你的？")
    XCTAssertEqual(mockToken.getTokenCallCount, 1)
}

func test_send_throwsApiError_whenHTTP500() async {
    let mockToken = MockTokenProviderIO()
    mockToken.stubbedToken = "test-token"

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.requestHandler = { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, "Internal Server Error".data(using: .utf8)!)
    }

    let vertex = VertexAIIO(
        tokenProvider: mockToken,
        projectID: "test-project",
        promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
        session: session
    )

    let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
    do {
        _ = try await vertex.send(request)
        XCTFail("Expected apiError")
    } catch let error as ProviderError {
        guard case .apiError(statusCode: 500, message: _) = error else {
            return XCTFail("Expected apiError(500)")
        }
    }
}

func test_send_throwsApiError_whenHTTP429() async {
    let mockToken = MockTokenProviderIO()
    mockToken.stubbedToken = "test-token"

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.requestHandler = { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, "Rate Limit Exceeded".data(using: .utf8)!)
    }

    let vertex = VertexAIIO(
        tokenProvider: mockToken,
        projectID: "test-project",
        promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
        session: session
    )

    let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
    do {
        _ = try await vertex.send(request)
        XCTFail("Expected apiError")
    } catch let error as ProviderError {
        guard case .apiError(statusCode: 429, message: _) = error else {
            return XCTFail("Expected apiError(429)")
        }
    }
}

func test_send_throwsResponseParsingFailed_whenMalformedJSON() async {
    let mockToken = MockTokenProviderIO()
    mockToken.stubbedToken = "test-token"

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.requestHandler = { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, "not json".data(using: .utf8)!)
    }

    let vertex = VertexAIIO(
        tokenProvider: mockToken,
        projectID: "test-project",
        promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
        session: session
    )

    let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
    do {
        _ = try await vertex.send(request)
        XCTFail("Expected responseParsingFailed")
    } catch let error as ProviderError {
        guard case .responseParsingFailed = error else {
            return XCTFail("Expected responseParsingFailed")
        }
    }
}

func test_send_throwsNetworkError_whenConnectionFails() async {
    let mockToken = MockTokenProviderIO()
    mockToken.stubbedToken = "test-token"

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    MockURLProtocol.requestHandler = { _ in
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    }

    let vertex = VertexAIIO(
        tokenProvider: mockToken,
        projectID: "test-project",
        promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
        session: session
    )

    let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
    do {
        _ = try await vertex.send(request)
        XCTFail("Expected networkError")
    } catch let error as ProviderError {
        guard case .networkError = error else {
            return XCTFail("Expected networkError")
        }
    }
}
```

- [ ] **Step 4: 添加到 Xcode 项目**

- [ ] **Step 5: 运行测试验证通过**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(VertexAIO|MockURL|TEST|passed|failed)"
```

- [ ] **Step 6: 提交**

```bash
git add TalkFlowTests/IO/VertexAIOTests.swift TalkFlowTests/Helpers/URLProtocolMock.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "test: VertexAIIO 单元测试（MockURLProtocol）"
```

---

### Task 11: 全量测试验证 + 收尾

- [ ] **Step 1: 运行全部测试**

```bash
cd .worktrees/provider-module && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | grep -E "(TEST|passed|failed|Executed)"
```

期望：所有测试通过（57 + 新增）

- [ ] **Step 2: 最终审查文件清单**

确认所有文件已加入 Xcode 项目且无缺失：

```bash
cd .worktrees/provider-module
ls TalkFlow/Utils/ChatMessage.swift
ls TalkFlow/Utils/PromptConfig.swift
ls TalkFlow/Utils/ServiceAccount.swift
ls TalkFlow/Utils/VertexMessageAdapter.swift
ls TalkFlow/IO/ProviderIO.swift
ls TalkFlow/IO/TokenProviderIO.swift
ls TalkFlow/IO/JWTTokenProvider.swift
ls TalkFlow/IO/VertexAIIO.swift
ls TalkFlowTests/Pure/ChatMessageTests.swift
ls TalkFlowTests/Pure/PromptConfigTests.swift
ls TalkFlowTests/Pure/ServiceAccountTests.swift
ls TalkFlowTests/Pure/VertexMessageAdapterTests.swift
ls TalkFlowTests/Mocks/MockProviderIO.swift
ls TalkFlowTests/Mocks/MockTokenProviderIO.swift
ls TalkFlowTests/IO/ProviderIOTests.swift
ls TalkFlowTests/IO/VertexAIOTests.swift
ls TalkFlowTests/Helpers/URLProtocolMock.swift
```

---
