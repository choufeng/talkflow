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
