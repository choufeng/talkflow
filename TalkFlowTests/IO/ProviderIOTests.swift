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
