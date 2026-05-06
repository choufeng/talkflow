import Foundation

// MARK: - Anthropic Messages API 请求体

struct AnthropicRequestBody: Codable, Equatable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let thinking: AnthropicThinking?
}

struct AnthropicMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct AnthropicThinking: Codable, Equatable {
    let type: String
    let budget_tokens: Int?
}

// MARK: - Anthropic Messages API 响应

struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

struct AnthropicResponseBody: Codable {
    let content: [AnthropicContentBlock]
}

// MARK: - Adapter

enum AnthropicMessageAdapter {
    /// 将 ChatMessage 数组转换为 Anthropic Messages API 请求体
    static func convert(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String,
        thinkingBudget: Int = 0
    ) -> AnthropicRequestBody {
        let anthropicMessages = messages
            .filter { $0.role == .user }
            .map { AnthropicMessage(role: "user", content: $0.content) }

        let system: String? = systemPrompt.isEmpty ? nil : systemPrompt

        let thinking: AnthropicThinking
        if thinkingBudget > 0 {
            thinking = AnthropicThinking(type: "enabled", budget_tokens: thinkingBudget)
        } else {
            thinking = AnthropicThinking(type: "disabled", budget_tokens: nil)
        }

        return AnthropicRequestBody(
            model: model,
            max_tokens: 4096,
            system: system,
            messages: anthropicMessages,
            thinking: thinking
        )
    }

    /// 从 Anthropic Messages API 响应 JSON 解析文本
    static func parseResponse(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response: AnthropicResponseBody
        do {
            response = try decoder.decode(AnthropicResponseBody.self, from: data)
        } catch {
            throw ProviderError.responseParsingFailed("JSON 解析失败: \(error.localizedDescription)")
        }

        guard let firstBlock = response.content.first else {
            throw ProviderError.responseParsingFailed("响应内容为空")
        }

        guard let text = firstBlock.text, !text.isEmpty else {
            throw ProviderError.responseParsingFailed("文本内容为空")
        }

        return text
    }
}
