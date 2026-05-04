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

    // MARK: - makePolishingSystemPrompt

    func test_makePolishingSystemPrompt_isNotEmpty() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertFalse(prompt.isEmpty, "固定提示词不应为空")
    }

    func test_makePolishingSystemPrompt_containsRemovalRule() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertTrue(prompt.contains("去除"), "应包含去除语气词规则")
        XCTAssertTrue(prompt.contains("\"嗯\""), "应包含具体示例")
    }

    func test_makePolishingSystemPrompt_containsTypoRule() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertTrue(prompt.contains("错别字"), "应包含错别字修正规则")
        XCTAssertTrue(prompt.contains("\"的/地/得\""), "应包含同音错误示例")
    }

    func test_makePolishingSystemPrompt_isDeterministic() {
        let a = makePolishingSystemPrompt()
        let b = makePolishingSystemPrompt()
        XCTAssertEqual(a, b, "纯函数不应有状态依赖")
    }

    func test_mergePrompts_withFixedPromptAndUserSupplement() {
        let result = mergePrompts(PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: "保持口语化风格"
        ))
        XCTAssertTrue(result.contains("去除"), "应含固定提示词")
        XCTAssertTrue(result.contains("保持口语化风格"), "应含用户补充")
        XCTAssertTrue(result.contains("\n"), "应以换行拼接")
    }

    func test_mergePrompts_withFixedPromptOnly_emptySupplement() {
        let result = mergePrompts(PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: ""
        ))
        XCTAssertEqual(result, makePolishingSystemPrompt())
    }
}
