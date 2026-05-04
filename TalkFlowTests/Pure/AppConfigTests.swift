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
}
