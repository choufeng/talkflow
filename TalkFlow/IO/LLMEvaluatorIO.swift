import Foundation

// MARK: - LLM 评测结果

struct LLMEvalResult: Equatable {
    let passed: Bool
    let score: Int
    let issues: [String]
}

// MARK: - LLM 评测错误

enum LLMEvalError: Error, Equatable {
    case parseFailed(String)
    case unexpectedVerdict(String)
}

// MARK: - LLM 评测 IO

final class LLMEvaluatorIO {
    private let provider: ProviderIO
    private let minScore: Int

    init(provider: ProviderIO, minScore: Int = 7) {
        self.provider = provider
        self.minScore = minScore
    }

    /// 用 LLM 评判输出质量
    /// - Parameters:
    ///   - input: 原始输入文本
    ///   - output: 模型输出文本
    ///   - workflow: 工作流类型
    func evaluate(input: String, output: String, workflow: Workflow, minScore: Int? = nil) async throws -> LLMEvalResult {
        let prompt = makeEvalPrompt(input: input, output: output, workflow: workflow)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: prompt)])
        let response = try await provider.send(request)
        var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 提取 JSON（可能包裹在 markdown 代码块中）
        if content.hasPrefix("```") {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            content = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = json["score"] as? Int,
              let verdict = json["verdict"] as? String else {
            throw LLMEvalError.parseFailed(content)
        }

        let issues = json["issues"] as? [String] ?? []
        let threshold = minScore ?? self.minScore
        let passed = verdict == "pass" && score >= threshold

        return LLMEvalResult(passed: passed, score: score, issues: issues)
    }
}

// MARK: - 评测 Prompt

private func makeEvalPrompt(input: String, output: String, workflow: Workflow) -> String {
    let taskDesc: String
    switch workflow {
    case .transcription:
        taskDesc = "STT 润色结果"
    case .translation:
        taskDesc = "STT 翻译结果"
    }

    return """
    对以下 \(taskDesc) 打分（0-10），评判标准：

    1. 信息保真度：输出是否保留了输入的全部信息？有无遗漏？
    2. 无过度总结：输出是否为逐句对应？有无大幅压缩或概括？
    3. 仅执行允许的操作：是否只做了去语气词、修错别字、去口吃？

    输入: \(input)
    输出: \(output)

    返回严格 JSON（不要用 markdown 包裹）:
    {"score": <0-10 整数>, "issues": ["问题1", ...], "verdict": "pass"|"fail"}
    """
}
