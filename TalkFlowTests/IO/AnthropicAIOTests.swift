import XCTest
@testable import TalkFlow

final class AnthropicAIOTests: XCTestCase {

    private func makeAnthropicAIIO(
        mockKeychain: MockKeychainIO,
        baseUrl: String = "https://api.anthropic.com",
        model: String = "claude-sonnet-4",
        thinkingBudget: Int = 0
    ) -> AnthropicAIIO {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return AnthropicAIIO(
            baseUrl: baseUrl,
            model: model,
            promptConfig: PromptConfig(defaultPrompt: "你是助手", userSupplement: ""),
            thinkingBudget: thinkingBudget,
            keychainIO: mockKeychain,
            session: URLSession(configuration: config)
        )
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

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "你好")])
        let response = try await anthropic.send(request)

        XCTAssertEqual(response.content, "你好！有什么可以帮你的？")
        XCTAssertEqual(mockKeychain.getCallCount, 1)
    }

    // MARK: - HTTP 错误

    func test_send_throwsAuthenticationFailed_when401() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "bad-key")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
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

    func test_send_throwsApiError_when500() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
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

    func test_send_throwsResponseParsingFailed_whenMalformedJSON() async throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
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

    func test_send_throwsNetworkError_whenConnectionFails() async throws {
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

    func test_send_usesThinkingDisabled_whenBudgetZero() throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain, thinkingBudget: 0)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        let urlRequest = try anthropic.buildRequest(for: request)

        guard let bodyData = urlRequest.httpBody else {
            return XCTFail("httpBody is nil")
        }
        let body = try JSONDecoder().decode(AnthropicRequestBody.self, from: bodyData)
        XCTAssertEqual(body.thinking?.type, "disabled")
    }

    func test_send_usesThinkingEnabled_whenBudgetPositive() throws {
        let mockKeychain = MockKeychainIO()
        try mockKeychain.set("api-key", value: "k")

        let anthropic = makeAnthropicAIIO(mockKeychain: mockKeychain, thinkingBudget: 4000)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
        let urlRequest = try anthropic.buildRequest(for: request)

        guard let bodyData = urlRequest.httpBody else {
            return XCTFail("httpBody is nil")
        }
        let body = try JSONDecoder().decode(AnthropicRequestBody.self, from: bodyData)
        XCTAssertEqual(body.thinking?.type, "enabled")
        XCTAssertEqual(body.thinking?.budget_tokens, 4000)
    }
}
