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
