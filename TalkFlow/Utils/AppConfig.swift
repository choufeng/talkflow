import Foundation

// MARK: - 应用配置（Codable，纯数据）

/// TalkFlow 全局配置 — 序列化为 JSON 存储在 App Support 目录
struct AppConfig: Codable, Equatable {

    /// Vertex AI 配置
    struct VertexAIConfig: Codable, Equatable {
        var modelName: String = "gemini-2.5-flash"
        var projectID: String = ""
        var thinkingBudget: Int = 0
    }

    /// 转写配置
    struct TranscriptionConfig: Codable, Equatable {
        var useLLM: Bool
        /// 用户自定义润色要求，与固定提示词拼接后作为 LLM system prompt
        var polishPrompt: String
        /// 翻译目标语言，默认英文
        var translationLanguage: String
        /// 用户自定义翻译补充要求
        var translationPrompt: String

        init(useLLM: Bool = true,
             polishPrompt: String = "",
             translationLanguage: String = "英文",
             translationPrompt: String = "") {
            self.useLLM = useLLM
            self.polishPrompt = polishPrompt
            self.translationLanguage = translationLanguage
            self.translationPrompt = translationPrompt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            useLLM = try container.decodeIfPresent(Bool.self, forKey: .useLLM) ?? true
            polishPrompt = try container.decodeIfPresent(String.self, forKey: .polishPrompt) ?? ""
            translationLanguage = try container.decodeIfPresent(String.self, forKey: .translationLanguage) ?? "英文"
            translationPrompt = try container.decodeIfPresent(String.self, forKey: .translationPrompt) ?? ""
        }
    }

    /// Anthropic Messages API 配置
    struct AnthropicConfig: Codable, Equatable {
        var baseUrl: String = "https://api.anthropic.com"
        var modelName: String = "claude-sonnet-4-20250514"
        var thinkingBudget: Int = 0
    }

    var vertexAI: VertexAIConfig = VertexAIConfig()
    var anthropic: AnthropicConfig = AnthropicConfig()
    var selectedProvider: String = "vertexAI"
    var transcription: TranscriptionConfig = TranscriptionConfig()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vertexAI = try container.decodeIfPresent(VertexAIConfig.self, forKey: .vertexAI) ?? VertexAIConfig()
        anthropic = try container.decodeIfPresent(AnthropicConfig.self, forKey: .anthropic) ?? AnthropicConfig()
        selectedProvider = try container.decodeIfPresent(String.self, forKey: .selectedProvider) ?? "vertexAI"
        transcription = try container.decodeIfPresent(TranscriptionConfig.self, forKey: .transcription) ?? TranscriptionConfig()
    }

    init() {
        vertexAI = VertexAIConfig()
        anthropic = AnthropicConfig()
        selectedProvider = "vertexAI"
        transcription = TranscriptionConfig()
    }
}

// MARK: - 纯函数

/// 默认配置
func makeDefaultAppConfig() -> AppConfig {
    AppConfig()
}
