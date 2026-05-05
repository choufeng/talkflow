import XCTest
@testable import TalkFlow

final class LLMEvaluatorIOTests: XCTestCase {

    func test_evaluate_passResponse_returnsPass() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 9, "issues": [], "verdict": "pass"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider)
        let result = try await evaluator.evaluate(input: "测试输入", output: "测试输出", workflow: .transcription)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.score, 9)
    }

    func test_evaluate_failResponse_returnsFail() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 3, "issues": ["信息大幅遗漏", "存在总结"], "verdict": "fail"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider)
        let result = try await evaluator.evaluate(input: "测试输入", output: "测试输出", workflow: .transcription)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.score, 3)
        XCTAssertEqual(result.issues, ["信息大幅遗漏", "存在总结"])
    }

    func test_evaluate_badJSON_throws() async {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "not json at all")

        let evaluator = LLMEvaluatorIO(provider: mockProvider)
        do {
            _ = try await evaluator.evaluate(input: "a", output: "b", workflow: .transcription)
            XCTFail("应抛出 LLMEvalError.parseFailed")
        } catch let error as LLMEvalError {
            XCTAssertEqual(error, .parseFailed("not json at all"))
        } catch {
            XCTFail("非预期的错误")
        }
    }

    func test_evaluate_scoreBelowThreshold_fails() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 5, "issues": ["过分概括"], "verdict": "fail"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider)
        let result = try await evaluator.evaluate(input: "a", output: "b", workflow: .transcription, minScore: 7)

        XCTAssertFalse(result.passed)
    }

    func test_evaluate_promptContainsInputAndOutput() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: """
        {"score": 8, "issues": [], "verdict": "pass"}
        """)

        let evaluator = LLMEvaluatorIO(provider: mockProvider)
        _ = try await evaluator.evaluate(input: "原始文本", output: "润色结果", workflow: .transcription)

        let req = mockProvider.sendLastRequest
        let content = req?.messages.first?.content ?? ""
        XCTAssertTrue(content.contains("原始文本"), "应包含输入文本")
        XCTAssertTrue(content.contains("润色结果"), "应包含输出文本")
    }
}
