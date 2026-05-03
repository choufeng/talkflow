import Foundation

/// Vertex AI Gemini 对话补全实现
final class VertexAIIO: ProviderIO {

    private let tokenProvider: TokenProviderIO
    private let projectID: String
    private let location: String
    private let model: String
    private let promptConfig: PromptConfig
    private let thinkingBudget: Int
    private let session: URLSession

    init(tokenProvider: TokenProviderIO,
         projectID: String,
         location: String = "us-central1",
         model: String = "gemini-2.5-flash",
         promptConfig: PromptConfig,
         thinkingBudget: Int = 0,
         session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.projectID = projectID
        self.location = location
        self.model = model
        self.promptConfig = promptConfig
        self.thinkingBudget = thinkingBudget
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        let token: String
        do {
            token = try await tokenProvider.getAccessToken()
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.authenticationFailed("Token 获取失败: \(error.localizedDescription)")
        }

        let systemPrompt = mergePrompts(promptConfig)
        let body = VertexMessageAdapter.convert(messages: request.messages, systemPrompt: systemPrompt, thinkingBudget: thinkingBudget)

        let urlString = "https://\(location)-aiplatform.googleapis.com/v1/projects/\(projectID)/locations/\(location)/publishers/google/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw ProviderError.networkError("无效 URL: \(urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.apiError(statusCode: httpResponse.statusCode, message: String(bodyText.prefix(500)))
        }

        do {
            return try parseVertexResponse(data: data)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.responseParsingFailed("解析失败: \(error.localizedDescription)")
        }
    }
}
