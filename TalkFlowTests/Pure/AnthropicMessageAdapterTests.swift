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
