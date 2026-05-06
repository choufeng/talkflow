import XCTest
@testable import TalkFlow

final class AppConfigTests: XCTestCase {

    func test_defaultConfig_useLLM_isTrue() {
        let config = makeDefaultAppConfig()
        XCTAssertTrue(config.transcription.useLLM, "默认应启用 LLM")
    }

    func test_defaultConfig_translationLanguage_isEnglish() {
        let config = makeDefaultAppConfig()
        XCTAssertEqual(config.transcription.translationLanguage, "英文")
    }

    func test_defaultConfig_translationPrompt_isEmpty() {
        let config = makeDefaultAppConfig()
        XCTAssertEqual(config.transcription.translationPrompt, "")
    }

    func test_codableRoundTrip() throws {
        var config = makeDefaultAppConfig()
        config.transcription.translationLanguage = "日文"
        config.transcription.translationPrompt = "保持敬语"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.transcription.translationLanguage, "日文")
        XCTAssertEqual(decoded.transcription.translationPrompt, "保持敬语")
        XCTAssertTrue(decoded.transcription.useLLM)
    }

    func test_codable_oldConfigWithoutTranslationFields_decodesWithDefaults() throws {
        let oldJSON = """
        {"vertexAI":{"modelName":"gemini","projectID":"p","thinkingBudget":0},"transcription":{"useLLM":true,"polishPrompt":"old"}}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.transcription.translationLanguage, "英文", "旧配置应有默认语言")
        XCTAssertEqual(decoded.transcription.translationPrompt, "", "旧配置应有默认提示词")
    }

    // MARK: - AnthropicConfig

    func test_anthropicConfig_defaults() {
        let config = AppConfig.AnthropicConfig()
        XCTAssertEqual(config.baseUrl, "https://api.anthropic.com")
        XCTAssertEqual(config.modelName, "claude-sonnet-4-20250514")
        XCTAssertEqual(config.thinkingBudget, 0)
    }

    func test_codable_oldConfigWithoutAnthropic_decodesWithDefaults() throws {
        let oldJSON = """
        {"vertexAI":{"modelName":"gemini","projectID":"p","thinkingBudget":0},"transcription":{"useLLM":true,"polishPrompt":""}}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.anthropic.baseUrl, "https://api.anthropic.com")
        XCTAssertEqual(decoded.selectedProvider, "vertexAI")
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
}
