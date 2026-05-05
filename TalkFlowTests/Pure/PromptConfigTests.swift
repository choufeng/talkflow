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
        XCTAssertTrue(prompt.contains("删除"), "应包含删除语气词规则")
        XCTAssertTrue(prompt.contains("嗯"), "应包含具体示例")
        XCTAssertTrue(prompt.contains("禁止"), "应包含禁止约束")
        XCTAssertTrue(prompt.contains("文本过滤器"), "应定位为过滤器而非编辑器")
        XCTAssertTrue(prompt.contains("还行吧"), "应包含示例")
    }

    func test_makePolishingSystemPrompt_containsTypoRule() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertTrue(prompt.contains("错别字"), "应包含错别字修正规则")
        XCTAssertTrue(prompt.contains("的/地/得"), "应包含同音错误示例")
        XCTAssertTrue(prompt.contains("禁止总结"), "应明确禁止总结")
        XCTAssertTrue(prompt.contains("禁止合并"), "应明确禁止合并句子")
        XCTAssertTrue(prompt.contains("不通顺"), "应允许不通顺原文保留")
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

    // MARK: - makeTranslationSystemPrompt

    func test_makeTranslationSystemPrompt_isNotEmpty() {
        let prompt = makeTranslationSystemPrompt(language: "英文")
        XCTAssertFalse(prompt.isEmpty, "翻译固定提示词不应为空")
    }

    func test_makeTranslationSystemPrompt_containsLanguage() {
        let prompt = makeTranslationSystemPrompt(language: "英文")
        XCTAssertTrue(prompt.contains("英文"), "应包含目标语言")
    }

    func test_makeTranslationSystemPrompt_containsTranslationRule() {
        let prompt = makeTranslationSystemPrompt(language: "日文")
        XCTAssertTrue(prompt.contains("翻译"), "应包含翻译指令")
        XCTAssertTrue(prompt.contains("日文"), "应包含指定的目标语言")
    }

    func test_makeTranslationSystemPrompt_isDeterministic() {
        let a = makeTranslationSystemPrompt(language: "越南语")
        let b = makeTranslationSystemPrompt(language: "越南语")
        XCTAssertEqual(a, b, "纯函数不应有状态依赖")
    }

    // MARK: - mergeTranslationPrompts

    func test_mergeTranslationPrompts_fullMerge() {
        let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "保持口语")
        let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "保持格式")
        let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
        XCTAssertEqual(result, "【润色】\n保持口语\n翻译成英文\n保持格式")
    }

    func test_mergeTranslationPrompts_noSupplement() {
        let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "")
        let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "")
        let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
        XCTAssertEqual(result, "【润色】\n翻译成英文")
    }

    func test_mergeTranslationPrompts_polishOnly() {
        let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "")
        let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "保持格式")
        let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
        XCTAssertEqual(result, "【润色】\n翻译成英文\n保持格式")
    }

    func test_mergeTranslationPrompts_translationOnly() {
        let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "保持口语")
        let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "")
        let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
        XCTAssertEqual(result, "【润色】\n保持口语\n翻译成英文")
    }
}
