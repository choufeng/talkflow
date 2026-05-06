# AnthropicAIIO Provider 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `AnthropicAIIO` 实现 `ProviderIO` 协议，通过 Anthropic Messages API 兼容端点提供转写润色和翻译能力，与 `VertexAIIO` 平行。

**Architecture:** 新增 3 个文件（KeychainIO、AnthropicMessageAdapter、AnthropicAIIO），修改 3 个文件（AppConfig、ModelSettingsView、AppDelegate）。`AnthropicAIIO` 接收 `KeychainIO` 从 Keychain 读取 API Key，`AnthropicMessageAdapter` 为纯函数负责请求/响应格式转换。UI 通过 `ModelSettingsView` 下拉切换 provider，配置持久化到 `AppConfig.json` + Keychain。

**Tech Stack:** Swift 5.9+, AppKit, URLSession, Keychain Services (SecItem), XCTest

---

### Task 1: KeychainIO 协议 + Mock + SecItemKeychainIO

**Files:**
- Create: `TalkFlow/IO/KeychainIO.swift`
- Create: `TalkFlowTests/Mocks/MockKeychainIO.swift`
- Create: `TalkFlowTests/IO/KeychainIOTests.swift`

- [ ] **Step 1: 创建 KeychainIO 协议**

```swift
// TalkFlow/IO/KeychainIO.swift
import Foundation

protocol KeychainIO {
    func get(_ key: String) throws -> String
    func set(_ key: String, value: String) throws
    func delete(_ key: String) throws
}

final class SecItemKeychainIO: KeychainIO {
    private let service: String

    init(service: String = "com.talkflow.anthropic") {
        self.service = service
    }

    func get(_ key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return value
    }

    func set(_ key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // 先尝试删除旧值
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }
}

enum KeychainError: Error, Equatable {
    case itemNotFound
    case invalidData
    case saveFailed
    case deleteFailed
}
```

- [ ] **Step 2: 创建 MockKeychainIO**

```swift
// TalkFlowTests/Mocks/MockKeychainIO.swift
import Foundation
@testable import TalkFlow

final class MockKeychainIO: KeychainIO {
    private var storage: [String: String] = [:]

    var getCallCount = 0
    var setCallCount = 0

    func get(_ key: String) throws -> String {
        getCallCount += 1
        guard let value = storage[key] else {
            throw KeychainError.itemNotFound
        }
        return value
    }

    func set(_ key: String, value: String) throws {
        setCallCount += 1
        storage[key] = value
    }

    func delete(_ key: String) throws {
        storage.removeValue(forKey: key)
    }
}
```

- [ ] **Step 3: 编写 KeychainIOTests**

```swift
// TalkFlowTests/IO/KeychainIOTests.swift
import XCTest
@testable import TalkFlow

final class KeychainIOTests: XCTestCase {
    func test_mock_setThenGet_returnsValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "v")
        let v = try mock.get("k")
        XCTAssertEqual(v, "v")
    }

    func test_mock_getNotFound_throws() {
        let mock = MockKeychainIO()
        XCTAssertThrowsError(try mock.get("nonexistent")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func test_mock_set_overwritesValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "old")
        try mock.set("k", value: "new")
        XCTAssertEqual(try mock.get("k"), "new")
        XCTAssertEqual(mock.setCallCount, 2)
    }

    func test_mock_delete_removesValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "v")
        try mock.delete("k")
        XCTAssertThrowsError(try mock.get("k"))
    }
}
```

- [ ] **Step 4: 运行 KeychainIOTests 验证通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing:TalkFlowTests/KeychainIOTests
```

- [ ] **Step 5: Commit**

```bash
git add TalkFlow/IO/KeychainIO.swift TalkFlowTests/Mocks/MockKeychainIO.swift TalkFlowTests/IO/KeychainIOTests.swift
git commit -m "feat: add KeychainIO protocol + SecItemKeychainIO + MockKeychainIO"
```

---

### Task 2: AnthropicMessageAdapter（纯函数）

**Files:**
- Create: `TalkFlow/IO/AnthropicMessageAdapter.swift`
- Create: `TalkFlowTests/Pure/AnthropicMessageAdapterTests.swift`

- [ ] **Step 1: 编写 AnthropicMessageAdapter 纯函数**

```swift
// TalkFlow/IO/AnthropicMessageAdapter.swift
import Foundation

// MARK: - Anthropic Messages API 请求体

struct AnthropicRequestBody: Codable, Equatable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let thinking: AnthropicThinking?
}

struct AnthropicMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct AnthropicThinking: Codable, Equatable {
    let type: String
    let budget_tokens: Int?
}

// MARK: - Anthropic Messages API 响应

struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

struct AnthropicResponseBody: Codable {
    let content: [AnthropicContentBlock]
}

// MARK: - Adapter

enum AnthropicMessageAdapter {
    /// 将 ChatMessage 数组转换为 Anthropic Messages API 请求体
    static func convert(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String,
        thinkingBudget: Int = 0
    ) -> AnthropicRequestBody {
        let anthropicMessages = messages
            .filter { $0.role == .user }
            .map { AnthropicMessage(role: "user", content: $0.content) }

        let system: String? = systemPrompt.isEmpty ? nil : systemPrompt

        let thinking: AnthropicThinking
        if thinkingBudget > 0 {
            thinking = AnthropicThinking(type: "enabled", budget_tokens: thinkingBudget)
        } else {
            thinking = AnthropicThinking(type: "disabled", budget_tokens: nil)
        }

        return AnthropicRequestBody(
            model: model,
            max_tokens: 4096,
            system: system,
            messages: anthropicMessages,
            thinking: thinking
        )
    }

    /// 从 Anthropic Messages API 响应 JSON 解析文本
    static func parseResponse(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response: AnthropicResponseBody
        do {
            response = try decoder.decode(AnthropicResponseBody.self, from: data)
        } catch {
            throw ProviderError.responseParsingFailed("JSON 解析失败: \(error.localizedDescription)")
        }

        guard let firstBlock = response.content.first else {
            throw ProviderError.responseParsingFailed("响应内容为空")
        }

        guard let text = firstBlock.text, !text.isEmpty else {
            throw ProviderError.responseParsingFailed("文本内容为空")
        }

        return text
    }
}
```

- [ ] **Step 2: 编写 AnthropicMessageAdapterTests**

```swift
// TalkFlowTests/Pure/AnthropicMessageAdapterTests.swift
import XCTest
@testable import TalkFlow

final class AnthropicMessageAdapterTests: XCTestCase {

    // MARK: - convert

    func test_convert_singleUserMessage() {
        let messages = [ChatMessage(role: .user, content: "你好")]
        let body = AnthropicMessageAdapter.convert(
            messages: messages,
            model: "claude-sonnet-4",
            systemPrompt: "你是助手"
        )

        XCTAssertEqual(body.model, "claude-sonnet-4")
        XCTAssertEqual(body.max_tokens, 4096)
        XCTAssertEqual(body.system, "你是助手")
        XCTAssertEqual(body.messages.count, 1)
        XCTAssertEqual(body.messages[0].role, "user")
        XCTAssertEqual(body.messages[0].content, "你好")
        XCTAssertEqual(body.thinking?.type, "disabled")
    }

    func test_convert_multipleUserMessages() {
        let messages = [
            ChatMessage(role: .user, content: "第一句"),
            ChatMessage(role: .user, content: "第二句"),
        ]
        let body = AnthropicMessageAdapter.convert(
            messages: messages,
            model: "m",
            systemPrompt: "sp"
        )
        XCTAssertEqual(body.messages.count, 2)
    }

    func test_convert_filtersSystemMessages() {
        let messages = [
            ChatMessage(role: .system, content: "内部"),
            ChatMessage(role: .user, content: "用户"),
        ]
        let body = AnthropicMessageAdapter.convert(
            messages: messages,
            model: "m",
            systemPrompt: "sp"
        )
        XCTAssertEqual(body.messages.count, 1)
        XCTAssertEqual(body.messages[0].content, "用户")
    }

    func test_convert_emptySystemPrompt_nilSystem() {
        let body = AnthropicMessageAdapter.convert(
            messages: [ChatMessage(role: .user, content: "h")],
            model: "m",
            systemPrompt: ""
        )
        XCTAssertNil(body.system)
    }

    func test_convert_thinkingEnabled() {
        let body = AnthropicMessageAdapter.convert(
            messages: [ChatMessage(role: .user, content: "h")],
            model: "m",
            systemPrompt: "",
            thinkingBudget: 8000
        )
        XCTAssertEqual(body.thinking?.type, "enabled")
        XCTAssertEqual(body.thinking?.budget_tokens, 8000)
    }

    func test_convert_thinkingDisabledByDefault() {
        let body = AnthropicMessageAdapter.convert(
            messages: [ChatMessage(role: .user, content: "h")],
            model: "m",
            systemPrompt: ""
        )
        XCTAssertEqual(body.thinking?.type, "disabled")
        XCTAssertNil(body.thinking?.budget_tokens)
    }

    // MARK: - parseResponse

    func test_parseResponse_success() throws {
        let json = """
        {"content": [{"type": "text", "text": "你好！"}]}
        """
        let text = try AnthropicMessageAdapter.parseResponse(json.data(using: .utf8)!)
        XCTAssertEqual(text, "你好！")
    }

    func test_parseResponse_emptyContent_throws() {
        let json = """
        {"content": []}
        """
        XCTAssertThrowsError(try AnthropicMessageAdapter.parseResponse(json.data(using: .utf8)!)) { error in
            guard case ProviderError.responseParsingFailed = error else {
                return XCTFail("Expected responseParsingFailed")
            }
        }
    }

    func test_parseResponse_malformedJSON_throws() {
        let data = "bad".data(using: .utf8)!
        XCTAssertThrowsError(try AnthropicMessageAdapter.parseResponse(data)) { error in
            guard case ProviderError.responseParsingFailed = error else {
                return XCTFail("Expected responseParsingFailed")
            }
        }
    }
}
```

- [ ] **Step 3: 运行测试验证**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing:TalkFlowTests/AnthropicMessageAdapterTests
```

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/IO/AnthropicMessageAdapter.swift TalkFlowTests/Pure/AnthropicMessageAdapterTests.swift
git commit -m "feat: add AnthropicMessageAdapter pure functions + tests"
```

---

### Task 3: AnthropicAIIO

**Files:**
- Create: `TalkFlow/IO/AnthropicAIIO.swift`
- Create: `TalkFlowTests/IO/AnthropicAIOTests.swift`

- [ ] **Step 1: 编写 AnthropicAIIO**

```swift
// TalkFlow/IO/AnthropicAIIO.swift
import Foundation

final class AnthropicAIIO: ProviderIO {
    private let baseUrl: String
    private let model: String
    private let promptConfig: PromptConfig
    private let thinkingBudget: Int
    private let keychainIO: KeychainIO
    private let session: URLSession

    init(
        baseUrl: String,
        model: String,
        promptConfig: PromptConfig,
        thinkingBudget: Int = 0,
        keychainIO: KeychainIO,
        session: URLSession = .shared
    ) {
        self.baseUrl = baseUrl
        self.model = model
        self.promptConfig = promptConfig
        self.thinkingBudget = thinkingBudget
        self.keychainIO = keychainIO
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey: String
        do {
            apiKey = try keychainIO.get("api-key")
        } catch {
            throw ProviderError.authenticationFailed("未找到 API Key: \(error.localizedDescription)")
        }

        let systemPrompt = mergePrompts(promptConfig)
        let body = AnthropicMessageAdapter.convert(
            messages: request.messages,
            model: model,
            systemPrompt: systemPrompt,
            thinkingBudget: thinkingBudget
        )

        let urlString = buildURL()
        guard let url = URL(string: urlString) else {
            throw ProviderError.networkError("无效 URL: \(urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

        switch httpResponse.statusCode {
        case 200:
            do {
                let text = try AnthropicMessageAdapter.parseResponse(data)
                return ChatResponse(content: text)
            } catch let error as ProviderError {
                throw error
            } catch {
                throw ProviderError.responseParsingFailed("解析失败: \(error.localizedDescription)")
            }
        case 401, 403:
            throw ProviderError.authenticationFailed("API Key 无效或被拒 (\(httpResponse.statusCode))")
        default:
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(bodyText.prefix(500))
            )
        }
    }

    private func buildURL() -> String {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return "\(trimmed)/v1/messages"
    }
}
```

- [ ] **Step 2: 编写 AnthropicAIOTests**

```swift
// TalkFlowTests/IO/AnthropicAIOTests.swift
import XCTest
@testable import TalkFlow

final class AnthropicAIOTests: XCTestCase {

    private func makeAnthropicAIIO(
        mockKeychain: MockKeychainIO,
        baseUrl: String = "https://api.anthropic.com",
        model: String = "claude-sonnet-4",
        thinkingBudget: Int = 0
    ) -> AnthropicAIIO {
        return AnthropicAIIO(
            baseUrl: baseUrl,
            model: model,
            promptConfig: PromptConfig(defaultPrompt: "你是助手", userSupplement: ""),
            thinkingBudget: thinkingBudget,
            keychainIO: mockKeychain,
            session: makeMockSession()
        )
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - 认证失败

    func test_send_throwsAuthenticationFailed_whenKeychainGetFails() async {
        let mockKeychain = MockKeychainIO()
        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)

        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await anthropic.send(request)
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            guard case .authenticationFailed = error else {
                return XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 成功响应

    func test_send_returnsChatResponse_whenAPI200() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "test-key")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.httpMethod, "POST")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let json = """
            {"content": [{"type": "text", "text": "你好！有什么可以帮你的？"}]}
            """
            return (response, json.data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain,
                                           baseUrl: "https://api.anthropic.com",
                                           model: "claude-sonnet-4")
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "你好")])
        let response = try await anthropic.send(request)

        XCTAssertEqual(response.content, "你好！有什么可以帮你的？")
        XCTAssertEqual(mockKeychain.getCallCount, 1)
    }

    // MARK: - HTTP 错误

    func test_send_throwsAuthenticationFailed_when401() async {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "bad-key")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await anthropic.send(request)
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            guard case .authenticationFailed = error else {
                return XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_send_throwsApiError_when500() async {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "Internal Error".data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await anthropic.send(request)
            XCTFail("Expected apiError")
        } catch let error as ProviderError {
            guard case .apiError(statusCode: 500, message: _) = error else {
                return XCTFail("Expected apiError(500), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 解析失败

    func test_send_throwsResponseParsingFailed_whenMalformedJSON() async {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "not json".data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await anthropic.send(request)
            XCTFail("Expected responseParsingFailed")
        } catch let error as ProviderError {
            guard case .responseParsingFailed = error else {
                return XCTFail("Expected responseParsingFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 网络错误

    func test_send_throwsNetworkError_whenConnectionFails() async {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await anthropic.send(request)
            XCTFail("Expected networkError")
        } catch let error as ProviderError {
            guard case .networkError = error else {
                return XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - URL 构造

    func test_send_trimsTrailingSlash() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, """
            {"content": [{"type": "text", "text": "ok"}]}
            """.data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain, baseUrl: "https://custom.api.com/")
        _ = try await anthropic.send(ChatRequest(messages: [ChatMessage(role: .user, content: "hi")]))

        XCTAssertEqual(capturedURL?.absoluteString, "https://custom.api.com/v1/messages")
    }

    // MARK: - Thinking 参数

    func test_send_usesThinkingDisabled_whenBudgetZero() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, """
            {"content": [{"type": "text", "text": "ok"}]}
            """.data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain, thinkingBudget: 0)
        _ = try await anthropic.send(ChatRequest(messages: [ChatMessage(role: .user, content: "hi")]))

        let body = try JSONDecoder().decode(AnthropicRequestBody.self, from: capturedBody!)
        XCTAssertEqual(body.thinking?.type, "disabled")
    }

    func test_send_usesThinkingEnabled_whenBudgetPositive() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, """
            {"content": [{"type": "text", "text": "ok"}]}
            """.data(using: .utf8)!)
        }

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain, thinkingBudget: 4000)
        _ = try await anthropic.send(ChatRequest(messages: [ChatMessage(role: .user, content: "hi")]))

        let body = try JSONDecoder().decode(AnthropicRequestBody.self, from: capturedBody!)
        XCTAssertEqual(body.thinking?.type, "enabled")
        XCTAssertEqual(body.thinking?.budget_tokens, 4000)
    }
}
```

- [ ] **Step 3: 运行测试验证**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing:TalkFlowTests/AnthropicAIOTests
```

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/IO/AnthropicAIIO.swift TalkFlowTests/IO/AnthropicAIOTests.swift
git commit -m "feat: add AnthropicAIIO ProviderIO implementation + tests"
```

---

### Task 4: AppConfig 扩展

**Files:**
- Modify: `TalkFlow/Utils/AppConfig.swift`
- Modify: `TalkFlowTests/Pure/AppConfigTests.swift`

- [ ] **Step 1: 修改 AppConfig，新增 AnthropicConfig**

在 `AppConfig.VertexAIConfig` 定义后添加，并在 `AppConfig` 中新增字段：

```swift
// 在 AppConfig 结构体中，紧接着 VertexAIConfig 定义之后新增：

    /// Anthropic Messages API 配置
    struct AnthropicConfig: Codable, Equatable {
        var baseUrl: String = "https://api.anthropic.com"
        var modelName: String = "claude-sonnet-4-20250514"
        var thinkingBudget: Int = 0
    }
```

在 `AppConfig` 的 `var vertexAI: VertexAIConfig = VertexAIConfig()` 之后新增：

```swift
    var anthropic: AnthropicConfig = AnthropicConfig()
    var selectedProvider: String = "vertexAI"
```

- [ ] **Step 2: 编写向后兼容测试**

在 `AppConfigTests.swift` 末尾添加：

```swift
    // MARK: - AnthropicConfig

    func test_anthropicConfig_defaults() {
        let config = AppConfig.AnthropicConfig()
        XCTAssertEqual(config.baseUrl, "https://api.anthropic.com")
        XCTAssertEqual(config.modelName, "claude-sonnet-4-20250514")
        XCTAssertEqual(config.thinkingBudget, 0)
    }

    func test_codable_oldConfigWithoutAnthropicAndSelectedProvider_decodesWithDefaults() throws {
        let oldJSON = """
        {"vertexAI":{"modelName":"gemini","projectID":"p","thinkingBudget":0},"transcription":{"useLLM":true,"polishPrompt":""}}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.anthropic.baseUrl, "https://api.anthropic.com", "旧配置应有默认 anthropic")
        XCTAssertEqual(decoded.selectedProvider, "vertexAI", "旧配置应有默认 vertexAI")
    }

    func test_codable_anthropicConfig_roundTrip() throws {
        var config = makeDefaultAppConfig()
        config.anthropic.baseUrl = "https://custom.proxy.com"
        config.anthropic.modelName = "claude-opus-4"
        config.anthropic.thinkingBudget = 8000
        config.selectedProvider = "anthropic"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.anthropic.baseUrl, "https://custom.proxy.com")
        XCTAssertEqual(decoded.anthropic.modelName, "claude-opus-4")
        XCTAssertEqual(decoded.anthropic.thinkingBudget, 8000)
        XCTAssertEqual(decoded.selectedProvider, "anthropic")
    }
```

- [ ] **Step 3: 运行全部 AppConfigTests**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing:TalkFlowTests/AppConfigTests
```

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/Utils/AppConfig.swift TalkFlowTests/Pure/AppConfigTests.swift
git commit -m "feat: add AnthropicConfig + selectedProvider to AppConfig"
```

---

### Task 5: ModelSettingsView 扩展

**Files:**
- Modify: `TalkFlow/Views/ModelSettingsView.swift`

> 注意：ModelSettingsView 的现有 ViewTests 通过查找子视图验证 UI 状态。本次修改遵循相同模式。

- [ ] **Step 1: 新增 ModelProvider.anthropic**

在 `ModelProvider` 枚举中新增：

```swift
enum ModelProvider: String, CaseIterable {
    case vertexAI = "Vertex AI"
    case anthropic = "Anthropic"
}
```

- [ ] **Step 2: 新增 Anthropic 配置属性**

在 `ModelSettingsView` 的 `private var` 区域新增：

```swift
    // Anthropic 配置子视图
    private let anthropicContainer = NSView()
    private let anthropicSeparator = NSBox()
    private let baseUrlLabel = NSTextField(labelWithString: "API Base URL:")
    private let baseUrlField = NSTextField()
    private let apiKeyLabel = NSTextField(labelWithString: "API Key:")
    private let apiKeyField = NSSecureTextField()
    private let modelIDLabel = NSTextField(labelWithString: "Model ID:")
    private let modelIDField = NSTextField()
    private let anthropicTestButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let anthropicStatusLabel = NSTextField(labelWithString: "")
    private var anthropicConnectionStatus: ConnectionTestStatus = .idle
    private var isAnthropicTesting = false
```

- [ ] **Step 3: 在 setUp() 中调用 Anthropic UI 构建**

在 `setUp()` 末尾添加：

```swift
        impureSetupAnthropicUI()
```

已在文件中的方法调用 `impureDetectADC()` 之后加。

- [ ] **Step 4: 实现 Anthropic UI 构建方法**

```swift
    private func impureSetupAnthropicUI() {
        anthropicContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(anthropicContainer)

        anthropicSeparator.boxType = .separator
        anthropicSeparator.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicSeparator)

        baseUrlLabel.font = NSFont.systemFont(ofSize: 12)
        baseUrlLabel.textColor = .secondaryLabelColor
        baseUrlLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(baseUrlLabel)

        baseUrlField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        baseUrlField.isEditable = true
        baseUrlField.placeholderString = "https://api.anthropic.com"
        baseUrlField.delegate = self
        baseUrlField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(baseUrlField)

        apiKeyLabel.font = NSFont.systemFont(ofSize: 12)
        apiKeyLabel.textColor = .secondaryLabelColor
        apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(apiKeyLabel)

        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        apiKeyField.isEditable = true
        apiKeyField.placeholderString = "sk-ant-..."
        apiKeyField.delegate = self
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(apiKeyField)

        modelIDLabel.font = NSFont.systemFont(ofSize: 12)
        modelIDLabel.textColor = .secondaryLabelColor
        modelIDLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(modelIDLabel)

        modelIDField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        modelIDField.isEditable = true
        modelIDField.placeholderString = "claude-sonnet-4-20250514"
        modelIDField.delegate = self
        modelIDField.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(modelIDField)

        anthropicTestButton.bezelStyle = .rounded
        anthropicTestButton.font = NSFont.systemFont(ofSize: 13)
        anthropicTestButton.target = self
        anthropicTestButton.action = #selector(impureTestAnthropicConnection)
        anthropicTestButton.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicTestButton)

        anthropicStatusLabel.font = NSFont.systemFont(ofSize: 12)
        anthropicStatusLabel.lineBreakMode = .byWordWrapping
        anthropicStatusLabel.maximumNumberOfLines = 3
        anthropicStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        anthropicContainer.addSubview(anthropicStatusLabel)

        // Layout: 沿用 vertexAIContainer 的布局模式
        // anthropicContainer 约束绑定到 vertexAIContainer 的底部
        NSLayoutConstraint.activate([
            anthropicContainer.topAnchor.constraint(equalTo: vertexAIContainer.topAnchor),
            anthropicContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            anthropicContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            anthropicContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            anthropicSeparator.topAnchor.constraint(equalTo: anthropicContainer.topAnchor),
            anthropicSeparator.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            anthropicSeparator.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            baseUrlLabel.topAnchor.constraint(equalTo: anthropicSeparator.bottomAnchor, constant: 8),
            baseUrlLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            baseUrlField.topAnchor.constraint(equalTo: baseUrlLabel.bottomAnchor, constant: 4),
            baseUrlField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            baseUrlField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            apiKeyLabel.topAnchor.constraint(equalTo: baseUrlField.bottomAnchor, constant: 12),
            apiKeyLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            apiKeyField.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 4),
            apiKeyField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            modelIDLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 12),
            modelIDLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            modelIDField.topAnchor.constraint(equalTo: modelIDLabel.bottomAnchor, constant: 4),
            modelIDField.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            modelIDField.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),

            anthropicTestButton.topAnchor.constraint(equalTo: modelIDField.bottomAnchor, constant: 12),
            anthropicTestButton.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),

            anthropicStatusLabel.topAnchor.constraint(equalTo: anthropicTestButton.bottomAnchor, constant: 8),
            anthropicStatusLabel.leadingAnchor.constraint(equalTo: anthropicContainer.leadingAnchor),
            anthropicStatusLabel.trailingAnchor.constraint(equalTo: anthropicContainer.trailingAnchor),
            anthropicStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: anthropicContainer.bottomAnchor),
        ])
    }
```

- [ ] **Step 5: 修改 render 方法，驱动容器显隐**

修改 `impureRender()` 方法，将：

```swift
        let showVertexAI = selectedProvider == .vertexAI
        vertexAIContainer.isHidden = !showVertexAI
```

扩展为：

```swift
        let showVertexAI = selectedProvider == .vertexAI
        vertexAIContainer.isHidden = !showVertexAI
        anthropicContainer.isHidden = !(selectedProvider == .anthropic)
```

- [ ] **Step 6: 修改 loadConfig，加载 Anthropic 配置**

在 `impureLoadConfig()` 末尾添加：

```swift
        if !config.anthropic.baseUrl.isEmpty && config.anthropic.baseUrl != "https://api.anthropic.com" {
            baseUrlField.stringValue = config.anthropic.baseUrl
        }
        if !config.anthropic.modelName.isEmpty {
            modelIDField.stringValue = config.anthropic.modelName
        }
        if config.selectedProvider == "anthropic" {
            providerDropdown.selectItem(withTitle: "Anthropic")
            selectedProvider = .anthropic
        }
```

- [ ] **Step 7: 实现连接测试**

```swift
    @objc private func impureTestAnthropicConnection() {
        guard !isAnthropicTesting else { return }

        let baseUrl = baseUrlField.stringValue.trimmingCharacters(in: .whitespaces)
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let modelID = modelIDField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !baseUrl.isEmpty, !apiKey.isEmpty, !modelID.isEmpty else {
            anthropicConnectionStatus = .failure("请填写 Base URL、API Key 和 Model ID")
            impureRender()
            return
        }

        isAnthropicTesting = true
        anthropicConnectionStatus = .testing
        impureRender()

        let keychain = MockKeychainIO()
        try? keychain.set("api-key", value: apiKey)

        let provider = AnthropicAIIO(
            baseUrl: baseUrl,
            model: modelID,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: ""),
            thinkingBudget: 0,
            keychainIO: keychain
        )

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
                let response = try await provider.send(request)
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .success("✅ 连接成功")
                    self.impureRender()
                    impureMakeLogger().info(tag: "ModelSettings", "Anthropic 连接测试成功 — 响应: \(response.content.prefix(50))")
                }
            } catch let error as ProviderError {
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .failure("❌ \(error.displayMessage)")
                    self.impureRender()
                }
            } catch {
                await MainActor.run {
                    self.isAnthropicTesting = false
                    self.anthropicConnectionStatus = .failure("❌ 未知错误: \(error.localizedDescription)")
                    self.impureRender()
                }
            }
        }
    }
```

- [ ] **Step 8: 修改渲染方法，加入 Anthropic 状态渲染**

在 `impureRender()` 的 switch 之后，新增 Anthropic 状态的独立 switch（或与现有逻辑合并）。在现有 `connectionStatus` switch 之后添加：

```swift
        // Anthropic 连接状态渲染
        switch anthropicConnectionStatus {
        case .idle:
            anthropicStatusLabel.stringValue = ""
            anthropicStatusLabel.textColor = .secondaryLabelColor
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        case .testing:
            anthropicStatusLabel.stringValue = "⏳ 正在测试连接..."
            anthropicStatusLabel.textColor = .secondaryLabelColor
            anthropicTestButton.isEnabled = false
            anthropicTestButton.title = "测试中..."
        case .success(let msg):
            anthropicStatusLabel.stringValue = msg
            anthropicStatusLabel.textColor = .systemGreen
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        case .failure(let msg):
            anthropicStatusLabel.stringValue = msg
            anthropicStatusLabel.textColor = .systemRed
            anthropicTestButton.isEnabled = true
            anthropicTestButton.title = "测试连接"
        }
```

- [ ] **Step 9: 修改保存逻辑**

在 `impureSaveConfig()` 末尾添加 Anthropic config 保存 + Keychain 写入：

```swift
        let baseUrl = baseUrlField.stringValue.trimmingCharacters(in: .whitespaces)
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let modelID = modelIDField.stringValue.trimmingCharacters(in: .whitespaces)

        if !baseUrl.isEmpty { config.anthropic.baseUrl = baseUrl }
        if !modelID.isEmpty { config.anthropic.modelName = modelID }
        config.selectedProvider = selectedProvider.rawValue

        // 保存 API Key 到 Keychain
        if !apiKey.isEmpty {
            let keychainIO = SecItemKeychainIO()
            try? keychainIO.set("api-key", value: apiKey)
        }
```

- [ ] **Step 10: 运行全量测试**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

- [ ] **Step 11: Commit**

```bash
git add TalkFlow/Views/ModelSettingsView.swift
git commit -m "feat: add Anthropic provider UI config card in ModelSettingsView"
```

---

### Task 6: AppDelegate 扩展

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 新增 Anthropic 工厂方法**

在 `impureMakeTranslationProvider()` 之后添加：

```swift
    private func impureMakeAnthropicProvider(polish: Bool) -> AnthropicAIIO? {
        let config = impureLoadAppConfig()
        let anthroConfig = config.anthropic

        guard !anthroConfig.baseUrl.isEmpty,
              !anthroConfig.modelName.isEmpty else {
            logger.info(tag: "Pipeline", "Anthropic — baseUrl 或 modelName 为空，跳过")
            return nil
        }

        let promptConfig: PromptConfig
        if polish {
            promptConfig = PromptConfig(
                defaultPrompt: makePolishingSystemPrompt(),
                userSupplement: config.transcription.polishPrompt
            )
        } else {
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
            promptConfig = PromptConfig(defaultPrompt: systemPrompt, userSupplement: "")
        }

        return AnthropicAIIO(
            baseUrl: anthroConfig.baseUrl,
            model: anthroConfig.modelName,
            promptConfig: promptConfig,
            thinkingBudget: anthroConfig.thinkingBudget,
            keychainIO: SecItemKeychainIO()
        )
    }
```

- [ ] **Step 2: 修改润色工厂，按 selectedProvider 分支**

修改 `impureMakePolishingProvider()`，在方法体最前面添加 provider 选择：

```swift
    private func impureMakePolishingProvider() -> VertexAIIO? {
        let config = impureLoadAppConfig()
        if config.selectedProvider == "anthropic" {
            // AnthropicAIIO 的签名与 VertexAIIO 不同，需要调整调用方
            return nil // 由调用方处理
        }
        // ... 现有 vertexAI 逻辑不变
```

**关键设计说明：** `impureMakePolishingProvider()` 返回类型是 `VertexAIIO?`，但 AnthropicAIIO 不是 VertexAIIO。需要改为返回 `ProviderIO?`，或者新增 `impureMakeProvider(polish:) -> ProviderIO?` 统一工厂。

**采用方案 — 新增统一工厂方法：**

在现有两个工厂方法之后新增：

```swift
    private func impureMakeProvider(polish: Bool) -> (any ProviderIO)? {
        let config = impureLoadAppConfig()
        if config.selectedProvider == "anthropic" {
            return impureMakeAnthropicProvider(polish: polish)
        }
        return polish ? impureMakePolishingProvider() : impureMakeTranslationProvider()
    }
```

- [ ] **Step 3: 修改 AppDelegate 中的 provider 调用点**

在 `impureSetupSTT()` 中，将两个 `if let provider = self.impureMakePolishingProvider()` 和 `if let provider = self.impureMakeTranslationProvider()` 替换为统一调用：

位置 1：转写润色分支（约在 `.transcription` case 内）：

```swift
                    case .transcription:
                        if let provider = self.impureMakeProvider(polish: true) {
```

位置 2：翻译分支（约在 `.translation` case 内）：

```swift
                    case .translation:
                        if let provider = self.impureMakeProvider(polish: false) {
```

整个文件的这两处仅把 `impureMakePolishingProvider()` → `impureMakeProvider(polish: true)`、`impureMakeTranslationProvider()` → `impureMakeProvider(polish: false)`。

- [ ] **Step 4: 运行全量测试**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

- [ ] **Step 5: Commit**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: add Anthropic provider factory + routing in AppDelegate"
```

---

### Task 7: 最终验证

- [ ] **Step 1: 运行全量测试确保无回归**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

- [ ] **Step 2: 验证 Xcode 项目包含新文件**

在 Xcode 中确认 `AnthropicAIIO.swift`、`AnthropicMessageAdapter.swift`、`KeychainIO.swift` 已添加到 TalkFlow target；测试文件已添加到 TalkFlowTests target。

- [ ] **Step 3: 最终 Commit**

```bash
git add -A
git commit -m "chore: final integration verification for Anthropic provider"
```
