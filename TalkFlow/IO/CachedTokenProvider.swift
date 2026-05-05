import Foundation

/// 装饰器：为任意 TokenProviderIO 提供内存级 access_token 缓存
/// 使用 actor 保证线程安全
actor CachedTokenProvider: TokenProviderIO {

    private let inner: any TokenProviderIO
    private var cachedToken: String?
    private var expiresAt: Date = .distantPast
    private let ttl: TimeInterval

    /// - Parameters:
    ///   - inner: 被装饰的实际 token 提供者
    ///   - ttl: 缓存有效期，默认 3300 秒（55 分钟，略小于 token 1h 有效期）
    init(inner: any TokenProviderIO, ttl: TimeInterval = 3300) {
        self.inner = inner
        self.ttl = ttl
    }

    func getAccessToken() async throws -> String {
        if let token = cachedToken, Date() < expiresAt {
            return token
        }

        let token = try await inner.getAccessToken()
        cachedToken = token
        expiresAt = Date().addingTimeInterval(ttl)
        return token
    }
}
