import Foundation
import Security
import CryptoKit

/// 基于 Google Service Account 的 JWT + OAuth2 令牌获取器
final class JWTTokenProvider: TokenProviderIO {

    private let sa: ServiceAccount
    private let scope: String
    private let session: URLSession

    init(sa: ServiceAccount,
         scope: String = "https://www.googleapis.com/auth/cloud-platform",
         session: URLSession = .shared) {
        self.sa = sa
        self.scope = scope
        self.session = session
    }

    func getAccessToken() async throws -> String {
        let jwt = try createJWT()
        return try await exchangeJWTForToken(jwt)
    }

    // MARK: - JWT 生成

    private func createJWT(now: Int = Int(Date().timeIntervalSince1970)) throws -> String {
        let header = try base64URLEncode(json: ["alg": "RS256", "typ": "JWT"])

        let claimSet: [String: Any] = [
            "iss": sa.clientEmail,
            "scope": scope,
            "aud": sa.tokenURI,
            "exp": now + 3600,
            "iat": now,
        ]
        let payload = try base64URLEncode(json: claimSet)

        let signingInput = "\(header).\(payload)"
        guard let signature = try signRS256(input: signingInput, privateKeyPEM: sa.privateKey) else {
            throw ProviderError.authenticationFailed("JWT 签名失败")
        }

        return "\(signingInput).\(signature)"
    }

    // MARK: - OAuth2 token 交换

    private func exchangeJWTForToken(_ jwt: String) async throws -> String {
        var request = URLRequest(url: URL(string: sa.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: jwt),
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

    // MARK: - RSA 签名

    private func signRS256(input: String, privateKeyPEM: String) throws -> String? {
        // 去掉 PEM 头尾，提取 Base64 内容
        let lines = privateKeyPEM
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64Key = lines.joined()

        guard let keyData = Data(base64Encoded: base64Key) else {
            throw ProviderError.authenticationFailed("私钥 Base64 解码失败")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) else {
            throw ProviderError.authenticationFailed("SecKey 创建失败")
        }

        let inputData = Data(input.utf8)
        var error: Unmanaged<CFError>?

        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            inputData as CFData,
            &error
        ) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            throw ProviderError.authenticationFailed("RSA 签名失败: \(errMsg)")
        }

        return (signature as Data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Base64URL 编码

    private func base64URLEncode(json dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
