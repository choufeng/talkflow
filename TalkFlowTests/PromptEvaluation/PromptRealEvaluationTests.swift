import XCTest
@testable import TalkFlow

/// 真实 Vertex AI 评测 — 仅在 DEBUG 下手动运行
/// 运行: xcodebuild test -scheme TalkFlow -destination 'platform=macOS' \
///   -only-testing:TalkFlowTests/PromptRealEvaluationTests
final class PromptRealEvaluationTests: XCTestCase {

    func test_transcription_all_cases_with_real_llm() async throws {
        guard ProcessInfo.processInfo.environment["TALKFLOW_REAL_EVAL"] == "1" else {
            throw XCTSkip("设置 TALKFLOW_REAL_EVAL=1 以运行真实 API 评测")
        }
        guard let adc = impureLoadADCFromDefaultPath() else {
            throw XCTSkip("ADC 未检测到")
        }
        let appConfig = impureLoadAppConfig()
        let projectID = appConfig.vertexAI.projectID
        let modelName = appConfig.vertexAI.modelName
        guard !projectID.isEmpty, !modelName.isEmpty else {
            throw XCTSkip("ProjectID/ModelName 未配置")
        }

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(projectID: projectID, privateKey: privateKey, clientEmail: clientEmail, tokenURI: tokenURI)
            tokenProvider = JWTTokenProvider(sa: sa)
        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
        }

        let polishPrompt = makePolishingSystemPrompt()
        let userSupplement = appConfig.transcription.polishPrompt
        let fullPrompt = PromptConfig(defaultPrompt: polishPrompt, userSupplement: userSupplement)

        let provider = VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: fullPrompt,
            thinkingBudget: appConfig.vertexAI.thinkingBudget
        )

        var results: [(name: String, passed: Bool, violations: [String], score: Int?)] = []

        for testCase in defaultPromptTestCases where testCase.workflow == .transcription {
            print("\n📝 [\(testCase.name)] 输入: \(testCase.input.prefix(40))...")

            // 1. 调用真实 LLM
            let request = ChatRequest(messages: [ChatMessage(role: .user, content: testCase.input)])
            let response: ChatResponse
            do {
                response = try await provider.send(request)
            } catch {
                print("   ❌ LLM 调用失败: \(error)")
                results.append((testCase.name, false, ["LLM 调用失败: \(error.localizedDescription)"], nil))
                continue
            }
            let output = response.content
            print("   输出: \(output.prefix(60))...")

            // 2. 规则层
            let ruleResult = evaluateRules(input: testCase.input, output: output, config: .default, checkCJK: true)
            if !ruleResult.passed {
                print("   ⚠️ 规则层 FAIL: \(ruleResult.violations.joined(separator: ", "))")
                results.append((testCase.name, false, ruleResult.violations, nil))
                continue
            }
            print("   ✅ 规则层 PASS")

            // 3. LLM 评判层（真实）
            let llmConfig = PromptConfig(defaultPrompt: makePolishingSystemPrompt(), userSupplement: "")
            let evalProvider = VertexAIIO(
                tokenProvider: tokenProvider,
                projectID: projectID,
                location: "us-central1",
                model: modelName,
                promptConfig: llmConfig,
                thinkingBudget: 0
            )
            let evaluator = LLMEvaluatorIO(provider: evalProvider, minScore: 7)
            do {
                let llmResult = try await evaluator.evaluate(
                    input: testCase.input,
                    output: output,
                    workflow: .transcription
                )
                print("   LLM 评判: score=\(llmResult.score), passed=\(llmResult.passed)")
                if !llmResult.issues.isEmpty {
                    print("   问题: \(llmResult.issues.joined(separator: ", "))")
                }
                results.append((testCase.name, llmResult.passed, llmResult.issues, llmResult.score))
            } catch {
                print("   ⚠️ LLM 评判失败: \(error)")
                results.append((testCase.name, false, ["LLM 评判失败: \(error.localizedDescription)"], nil))
            }
        }

        // 汇总
        print("\n" + String(repeating: "=", count: 60))
        print("评测汇总")
        print(String(repeating: "=", count: 60))
        let passed = results.filter(\.passed).count
        let failed = results.filter { !$0.passed }.count
        for r in results {
            let icon = r.passed ? "✅" : "❌"
            let scoreStr = r.score.map { " (\($0)分)" } ?? ""
            print("\(icon) \(r.name)\(scoreStr)")
            if !r.violations.isEmpty {
                for v in r.violations {
                    print("   → \(v)")
                }
            }
        }
        print("\n通过: \(passed)/\(results.count), 失败: \(failed)/\(results.count)")

        // 断言全部通过（如有失败会在这里报）
        if failed > 0 {
            XCTFail("\(failed) 个用例未通过评测")
        }
    }
}
