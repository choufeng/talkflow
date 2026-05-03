import Foundation

// MARK: - Token 映射表（纯函数）

/// 将 token_id 序列解码为文本（纯函数）
func decodeTokenIds(_ ids: [Int32], tokens: [Int: String]) -> String {
    ids.compactMap { tokens[Int($0)] }.joined()
}
