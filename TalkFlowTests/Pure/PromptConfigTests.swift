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

    func test_merge_supplementOnlyWhitespace_returnsWithWhitespace() {
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
