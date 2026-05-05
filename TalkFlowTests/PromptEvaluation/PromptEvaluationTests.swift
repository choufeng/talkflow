import XCTest
@testable import TalkFlow

final class PromptEvaluationTests: XCTestCase {

    // MARK: - 规则层（纯函数，始终运行）

    func test_rules_only_allCases_pass() {
        for testCase in defaultPromptTestCases {
            let output = makeMinimalOutput(for: testCase)
            let checkCJK = testCase.workflow == .transcription
            let config: RuleEvalConfig
            switch testCase.workflow {
            case .transcription:
                config = .default
            case .translation:
                config = RuleEvalConfig(minCharRatio: 0.2, maxCharRatio: 3.0, minCJKRatio: 0.0)
            }
            let result = evaluateRules(input: testCase.input, output: output, config: config, checkCJK: checkCJK)

            XCTAssertTrue(
                result.passed,
                "[\(testCase.name)] 规则层失败: \(result.violations.joined(separator: ", "))"
            )
        }
    }

    // MARK: - LLM 评判层（用 Mock，仅验证流程）

    func test_evaluation_integration_mockPass() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 9, "issues": [], "verdict": "pass"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider, minScore: 7)
        let testCase = defaultPromptTestCases[0]
        let output = makeMinimalOutput(for: testCase)

        let checkCJK = testCase.workflow == .transcription
        let config: RuleEvalConfig = testCase.workflow == .transcription ? .default :
            RuleEvalConfig(minCharRatio: 0.2, maxCharRatio: 3.0, minCJKRatio: 0.0)
        let ruleResult = evaluateRules(input: testCase.input, output: output, config: config, checkCJK: checkCJK)
        guard ruleResult.passed else {
            XCTFail("[\(testCase.name)] 规则层未通过不应进入 LLM 评判")
            return
        }

        let llmResult = try await evaluator.evaluate(
            input: testCase.input,
            output: output,
            workflow: testCase.workflow
        )

        XCTAssertTrue(llmResult.passed, "[\(testCase.name)] LLM 评判未通过: \(llmResult.issues)")
    }

    func test_evaluation_integration_mockFail() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 3, "issues": ["严重总结"], "verdict": "fail"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider, minScore: 7)
        let testCase = defaultPromptTestCases[0]
        let output = "过度总结的结果"
        let checkCJK = testCase.workflow == .transcription
        let config: RuleEvalConfig = testCase.workflow == .transcription ? .default :
            RuleEvalConfig(minCharRatio: 0.2, maxCharRatio: 3.0, minCJKRatio: 0.0)
        let ruleResult = evaluateRules(input: testCase.input, output: output, config: config, checkCJK: checkCJK)
        guard ruleResult.passed else { return }

        let llmResult = try await evaluator.evaluate(
            input: testCase.input,
            output: output,
            workflow: testCase.workflow
        )

        XCTAssertFalse(llmResult.passed, "总结应被 LLM 评判为 fail")
    }
}

// MARK: - 辅助

private func makeMinimalOutput(for testCase: PromptTestCase) -> String {
    let fillers = ["嗯", "啊", "额", "呃", "那个", "就是", "对吧", "的话", "怎么说呢", "反正", "那种"]
    var result = testCase.input
    for f in fillers {
        result = result.replacingOccurrences(of: f, with: "")
    }
    return result.trimmingCharacters(in: .whitespaces)
}
