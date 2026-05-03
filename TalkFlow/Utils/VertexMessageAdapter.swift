import Foundation

/// Vertex AI 消息格式适配器
/// 将 ChatMessage 数组转换为 Vertex AI generateContent 请求格式
enum VertexMessageAdapter {

    /// 单条消息内容部分
    struct ContentPart: Codable, Equatable {
        let text: String
    }

    /// 单条消息
    struct Content: Codable, Equatable {
        let role: String
        let parts: [ContentPart]
    }

    /// 系统指令
    struct SystemInstruction: Codable, Equatable {
        let parts: [ContentPart]
    }

    /// Vertex AI 请求体
    struct RequestBody: Codable, Equatable {
        let contents: [Content]
        let systemInstruction: SystemInstruction?
        let generationConfig: GenerationConfig?
    }

    struct GenerationConfig: Codable, Equatable {
        let thinkingConfig: ThinkingConfig?
    }

    struct ThinkingConfig: Codable, Equatable {
        let thinkingBudget: Int
    }

    // MARK: - 纯函数转换

    /// 将 ChatMessage 数组转换为 Vertex RequestBody
    /// thinkingBudget: 0 = 关闭思维链，-1 = 由模型决定
    static func convert(messages: [ChatMessage], systemPrompt: String, thinkingBudget: Int = 0) -> RequestBody {
        let contents = messages
            .filter { $0.role == .user }
            .map { msg in
                Content(role: "user", parts: [ContentPart(text: msg.content)])
            }

        let sysInstruction: SystemInstruction?
        if !systemPrompt.isEmpty {
            sysInstruction = SystemInstruction(parts: [ContentPart(text: systemPrompt)])
        } else {
            sysInstruction = nil
        }

        return RequestBody(
            contents: contents,
            systemInstruction: sysInstruction,
            generationConfig: GenerationConfig(
                thinkingConfig: ThinkingConfig(thinkingBudget: thinkingBudget)
            )
        )
    }
}

// MARK: - 响应解析

/// Vertex AI generateContent 响应的 candidates 部分
struct VertexCandidate: Codable {
    struct ResponseContent: Codable {
        struct Part: Codable {
            let text: String
        }
        let role: String
        let parts: [Part]
    }
    let content: ResponseContent
}

struct VertexGenerateContentResponse: Codable {
    let candidates: [VertexCandidate]
}

/// 从 Vertex AI JSON 响应解析 ChatResponse
func parseVertexResponse(data: Data) throws -> ChatResponse {
    let decoder = JSONDecoder()

    let response: VertexGenerateContentResponse
    do {
        response = try decoder.decode(VertexGenerateContentResponse.self, from: data)
    } catch {
        throw ProviderError.responseParsingFailed("JSON 解析失败: \(error.localizedDescription)")
    }

    guard let firstCandidate = response.candidates.first else {
        throw ProviderError.responseParsingFailed("响应中无候选内容")
    }

    let text = firstCandidate.content.parts.map(\.text).joined(separator: "\n")
    guard !text.isEmpty else {
        throw ProviderError.responseParsingFailed("候选内容为空")
    }

    return ChatResponse(content: text)
}
