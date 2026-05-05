import Foundation

// MARK: - 提示词优化 IO

final class PromptOptimizerIO {
    private let provider: ProviderIO

    init(provider: ProviderIO) {
        self.provider = provider
    }

    /// 优化用户补充提示词
    /// - Parameter rawPrompt: 用户在输入框中的原始文本
    /// - Returns: 优化后的提示词
    func optimize(_ rawPrompt: String) async throws -> String {
        let prompt = makeOptimizePrompt(rawPrompt: rawPrompt)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: prompt)])
        let response = try await provider.send(request)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 优化 Prompt

private func makeOptimizePrompt(rawPrompt: String) -> String {
    """
    优化以下用户自定义提示词，使其更清晰、无歧义、不矛盾：

    原则：
    - 结构化：如有多个要求，用编号或分段
    - 删除与"去语气词、修错别字、去口吃重复"矛盾的内容
    - 删除暗示总结、改写、概括的任何表述
    - 如果输入为空或仅有空白，返回空字符串
    - 仅输出优化后的提示词文本，不输出解释或任何其他内容

    用户原始提示词：
    \(rawPrompt)
    """
}
