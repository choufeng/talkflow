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

    // MARK: - 成功响应

    func test_send_returnsChatResponse_whenAPI200() async throws {
        let mockToken = MockTokenProviderIO()
        mockToken.stubbedToken = "test-token"

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.requestHandler = { request in
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

    // MARK: - HTTP 错误

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
        } catch {
            XCTFail("Unexpected error: \(error)")
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
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 解析失败

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
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - 网络错误

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
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
