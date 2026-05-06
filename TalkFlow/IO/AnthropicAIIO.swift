import Foundation

final class AnthropicAIIO: ProviderIO {
    private let baseUrl: String
    private let model: String
    private let promptConfig: PromptConfig
    private let thinkingBudget: Int
    private let keychainIO: KeychainIO
    private let session: URLSession

    init(
        baseUrl: String,
        model: String,
        promptConfig: PromptConfig,
        thinkingBudget: Int = 0,
        keychainIO: KeychainIO,
        session: URLSession = .shared
    ) {
        self.baseUrl = baseUrl
        self.model = model
        self.promptConfig = promptConfig
        self.thinkingBudget = thinkingBudget
        self.keychainIO = keychainIO
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey: String
        do {
            apiKey = try keychainIO.get("api-key")
        } catch {
            throw ProviderError.authenticationFailed("未找到 API Key: \(error.localizedDescription)")
        }

        let systemPrompt = mergePrompts(promptConfig)
        let body = AnthropicMessageAdapter.convert(
            messages: request.messages,
            model: model,
            systemPrompt: systemPrompt,
            thinkingBudget: thinkingBudget
        )

        let urlString = buildURL()
        guard let url = URL(string: urlString) else {
            throw ProviderError.networkError("无效 URL: \(urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ProviderError.networkError("请求失败: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("非 HTTP 响应")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let text = try AnthropicMessageAdapter.parseResponse(data)
                return ChatResponse(content: text)
            } catch let error as ProviderError {
                throw error
            } catch {
                throw ProviderError.responseParsingFailed("解析失败: \(error.localizedDescription)")
            }
        case 401, 403:
            throw ProviderError.authenticationFailed("API Key 无效或被拒 (\(httpResponse.statusCode))")
        default:
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.apiError(
                statusCode: httpResponse.statusCode,
                message: String(bodyText.prefix(500))
            )
        }
    }

    private func buildURL() -> String {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return "\(trimmed)/v1/messages"
    }

    /// 构建 URLRequest 供测试使用
    func buildRequest(for chatRequest: ChatRequest) throws -> URLRequest {
        let apiKey = try keychainIO.get("api-key")
        let systemPrompt = mergePrompts(promptConfig)
        let body = AnthropicMessageAdapter.convert(
            messages: chatRequest.messages,
            model: model,
            systemPrompt: systemPrompt,
            thinkingBudget: thinkingBudget
        )

        let urlString = buildURL()
        guard let url = URL(string: urlString) else {
            throw ProviderError.networkError("无效 URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}
