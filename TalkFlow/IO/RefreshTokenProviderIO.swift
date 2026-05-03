import Foundation

// MARK: - OAuth2 Refresh Token 令牌提供者

/// 使用 Google OAuth2 refresh_token 获取 access_token
/// 适用于 `gcloud auth application-default login` 产生的 authorized_user 凭据
final class RefreshTokenProviderIO: TokenProviderIO {

    private let clientID: String
    private let clientSecret: String
    private let refreshToken: String
    private let session: URLSession

    init(clientID: String,
         clientSecret: String,
         refreshToken: String,
         session: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
        self.session = session
    }

    func getAccessToken() async throws -> String {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.networkError("Token 请求失败: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("非 HTTP 响应")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.authenticationFailed("Token 交换失败 (HTTP \(httpResponse.statusCode)): \(body.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw ProviderError.authenticationFailed("响应中缺少 access_token")
        }

        return token
    }
}
