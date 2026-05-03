import Foundation

// MARK: - ProviderIO 协议

protocol ProviderIO {
    /// 发送对话请求，返回模型输出文本
    /// - Parameter request: 包含了消息列表的请求
    /// - Returns: 模型响应的文本内容
    /// - Throws: ProviderError
    func send(_ request: ChatRequest) async throws -> ChatResponse
}

// MARK: - Provider 错误类型

enum ProviderError: Error, Equatable {
    /// 认证失败（SA 文件不存在 / 格式错误 / 私钥无效 / token 获取失败）
    case authenticationFailed(String)
    /// 网络错误（连接失败 / 超时等）
    case networkError(String)
    /// API 返回错误（含 HTTP 状态码与错误信息）
    case apiError(statusCode: Int, message: String)
    /// 响应解析失败
    case responseParsingFailed(String)
}

// MARK: - ProviderError 显示文本

extension ProviderError {
    /// 面向用户的错误描述
    var displayMessage: String {
        switch self {
        case .authenticationFailed(let msg):
            return "认证失败: \(msg)"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .apiError(let code, let msg):
            return "API 错误 (\(code)): \(msg)"
        case .responseParsingFailed(let msg):
            return "响应解析失败: \(msg)"
        }
    }
}
