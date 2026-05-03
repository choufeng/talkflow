import Foundation

protocol TokenProviderIO {
    /// 获取访问令牌
    /// - Returns: Bearer token 字符串
    /// - Throws: ProviderError
    func getAccessToken() async throws -> String
}
