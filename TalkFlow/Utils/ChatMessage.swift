import Foundation

// MARK: - 消息角色

enum MessageRole: String, Codable, Equatable {
    case system
    case user
}

// MARK: - 聊天消息

struct ChatMessage: Codable, Equatable {
    let role: MessageRole
    let content: String
}

// MARK: - 聊天请求

struct ChatRequest: Codable, Equatable {
    let messages: [ChatMessage]
}

// MARK: - 聊天响应

struct ChatResponse: Equatable {
    let content: String
}
