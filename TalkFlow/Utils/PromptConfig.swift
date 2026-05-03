import Foundation

/// 提示词配置：默认系统提示词 + 用户补充内容
struct PromptConfig: Codable, Equatable {
    let defaultPrompt: String
    var userSupplement: String
}

// MARK: - 纯函数

/// 合并默认提示词与用户补充
/// - 无补充时仅返回默认提示词
/// - 有补充时以换行拼接
func mergePrompts(_ config: PromptConfig) -> String {
    if config.userSupplement.isEmpty {
        return config.defaultPrompt
    }
    return "\(config.defaultPrompt)\n\(config.userSupplement)"
}
