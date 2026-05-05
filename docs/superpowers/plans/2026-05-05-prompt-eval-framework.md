# 提示词评测框架 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 开发时运行一批测试用例验证提示词效果，规则层（纯函数）+ LLM 评判层（IO）双检。

**Architecture:** 规则层为纯函数（RuleEvalConfig → RuleEvalResult），LLM 评判层复用 ProviderIO 协议。测试用例不设黄金输出，由规则 + LLM 评判替代。测试仅在 `#if DEBUG` 下运行，不跑 CI。

**Tech Stack:** Swift, XCTest, VertexAIIO (复用)

---

### Task 1: RuleEvalConfig 与 RuleEvalResult 纯数据类型

**Files:**
- Create: `TalkFlow/Utils/RuleEvalResult.swift`

- [ ] **Step 1: 创建纯数据类型文件**

```swift
// TalkFlow/Utils/RuleEvalResult.swift
import Foundation

// MARK: - 规则评测配置

struct RuleEvalConfig: Codable, Equatable {
    /// 最低字数比（output.charCount / input.charCount），低于此值视为总结
    var minCharRatio: Double = 0.3
    /// 最高字数比，超过视为异常
    var maxCharRatio: Double = 1.5
    /// 最低 CJK 字符占比（仅润色流程使用）
    var minCJKRatio: Double = 0.5

    static let `default` = RuleEvalConfig()
}

// MARK: - 规则评测结果

struct RuleEvalResult: Equatable {
    let passed: Bool
    let violations: [String]

    static func pass() -> RuleEvalResult {
        RuleEvalResult(passed: true, violations: [])
    }

    static func fail(_ violations: [String]) -> RuleEvalResult {
        RuleEvalResult(passed: false, violations: violations)
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/Utils/RuleEvalResult.swift
git commit -m "feat: 添加 RuleEvalConfig 和 RuleEvalResult 纯数据类型"
```

---

### Task 2: RuleEvaluator 纯函数

**Files:**
- Create: `TalkFlow/Utils/RuleEvaluator.swift`

- [ ] **Step 1: 写失败测试**

```swift
// TalkFlowTests/Pure/RuleEvaluatorTests.swift
import XCTest
@testable import TalkFlow

final class RuleEvaluatorTests: XCTestCase {

    func test_evaluateRules_normalOutput_passes() {
        let input = "嗯我觉得这个方案还行吧"
        let output = "我觉得这个方案还行吧"
        let result = evaluateRules(input: input, output: output, config: .default)
        XCTAssertTrue(result.passed, "正常润色应通过")
        XCTAssertEqual(result.violations, [])
    }

    func test_evaluateRules_emptyOutput_fails() {
        let result = evaluateRules(input: "嗯我觉得这个方案还行吧", output: "", config: .default)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains { $0.contains("空输出") })
    }

    func test_evaluateRules_summarized_fails() {
        let input = "嗯大家好那个我今天想跟各位分享一下关于我们最近在做的一个项目的情况怎么说呢"
        let output = "分享项目情况"  // 大幅压缩
        let result = evaluateRules(input: input, output: output, config: .default)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains { $0.contains("字数比") })
    }

    func test_evaluateRules_outputTooLong_fails() {
        let input = "嗯我觉得这个方案还行吧"
        let output = String(repeating: "我觉得这个方案还行吧我觉得这个方案还行吧", count: 5) // 远超 1.5 倍
        let result = evaluateRules(input: input, output: output, config: .default)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains { $0.contains("字数比") })
    }

    func test_evaluateRules_lowCJKRatioInPolish_fails() {
        let input = "嗯我觉得这个方案还行吧"
        let output = "I think this plan is okay"  // 全英文，中文占比 0
        let result = evaluateRules(input: input, output: output, config: .default, checkCJK: true)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains { $0.contains("中文") })
    }

    func test_evaluateRules_lowCJKRatioInTranslation_passes() {
        let input = "嗯我觉得这个方案还行吧"
        let output = "I think this plan is okay"  // 翻译不检查中文占比
        let result = evaluateRules(input: input, output: output, config: .default, checkCJK: false)
        XCTAssertTrue(result.passed)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/RuleEvaluatorTests 2>&1 | tail -10
```
Expected: FAIL — `evaluateRules` 未定义

- [ ] **Step 3: 实现 evaluateRules**

```swift
// TalkFlow/Utils/RuleEvaluator.swift
import Foundation

// MARK: - 规则评测（纯函数）

/// 对输入/输出文本对做规则层量化检测
/// - Parameters:
///   - input: 原始输入文本
///   - output: 模型输出文本
///   - config: 评测配置
///   - checkCJK: 是否检查中文占比（润色流程 true，翻译流程 false）
/// - Returns: RuleEvalResult
func evaluateRules(input: String, output: String, config: RuleEvalConfig, checkCJK: Bool = true) -> RuleEvalResult {
    var violations: [String] = []

    // 1. 空输出
    if output.isEmpty {
        violations.append("输出为空输出")
        return .fail(violations)
    }

    let inputCount = input.count
    let outputCount = output.count

    // 2. 字数比检查
    guard inputCount > 0 else {
        return .pass() // 无输入则跳过其他规则
    }

    let ratio = Double(outputCount) / Double(inputCount)

    if ratio < config.minCharRatio {
        violations.append("字数比过低: \(String(format: "%.2f", ratio)) < \(config.minCharRatio)（疑似总结）")
    }

    if ratio > config.maxCharRatio {
        violations.append("字数比过高: \(String(format: "%.2f", ratio)) > \(config.maxCharRatio)（疑似异常）")
    }

    // 3. 中文占比（仅润色流程）
    if checkCJK {
        let cjkCount = output.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }.count
        let cjkRatio = outputCount > 0 ? Double(cjkCount) / Double(outputCount) : 0
        if cjkRatio < config.minCJKRatio {
            violations.append("中文占比过低: \(String(format: "%.2f", cjkRatio)) < \(config.minCJKRatio)")
        }
    }

    return violations.isEmpty ? .pass() : .fail(violations)
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/RuleEvaluatorTests 2>&1 | tail -10
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/RuleEvaluator.swift TalkFlowTests/Pure/RuleEvaluatorTests.swift
git commit -m "feat: 添加 RuleEvaluator 纯函数 + 测试"
```

---

### Task 3: LLMEvaluator IO 层

**Files:**
- Create: `TalkFlow/IO/LLMEvaluatorIO.swift`

- [ ] **Step 1: 写 IO 测试（用 MockProviderIO）**

```swift
// TalkFlowTests/IO/LLMEvaluatorIOTests.swift
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
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/LLMEvaluatorIOTests 2>&1 | tail -10
```
Expected: FAIL

- [ ] **Step 3: 实现 LLMEvaluatorIO**

```swift
// TalkFlow/IO/LLMEvaluatorIO.swift
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
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/LLMEvaluatorIOTests 2>&1 | tail -10
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/IO/LLMEvaluatorIO.swift TalkFlowTests/IO/LLMEvaluatorIOTests.swift
git commit -m "feat: 添加 LLMEvaluatorIO 评测层 + 测试"
```

---

### Task 4: PromptTestCases 测试数据集

**Files:**
- Create: `TalkFlowTests/PromptEvaluation/PromptTestCases.swift`

- [ ] **Step 1: 创建测试用例数据**

```swift
// TalkFlowTests/PromptEvaluation/PromptTestCases.swift
import Foundation
@testable import TalkFlow

// MARK: - 测试用例

struct PromptTestCase: Equatable {
    let name: String
    let input: String
    let workflow: Workflow

    init(name: String, input: String, workflow: Workflow) {
        self.name = name
        self.input = input
        self.workflow = workflow
    }
}

// MARK: - 默认测试用例集

let defaultPromptTestCases: [PromptTestCase] = [
    PromptTestCase(
        name: "正常口语",
        input: "嗯我觉得那个这个方案还行吧",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "长段落",
        input: "嗯大家好那个我今天想跟各位分享一下关于我们最近在做的一个项目的情况怎么说呢这个项目其实从去年年底就开始规划了对吧然后经过几个月的时间我们团队一直在努力推进那个目前来看的话进展还算比较顺利就是还有一些细节的地方需要再打磨一下呃总体来说我对此还是比较有信心的",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "大量语气词",
        input: "嗯那个就是呃怎么说呢反正吧我觉得对吧这个东西啊其实对吧就是那么回事对吧你懂我意思吧嗯啊",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "技术术语",
        input: "嗯我们那个在Kubernetes集群里面用了Istio做那个服务网格然后就是那个Sidecar注入之后发现延迟有点高啊大概就是P99延迟从50毫秒涨到了200毫秒",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "翻译用例",
        input: "嗯我觉得这个产品设计思路还是不错的但是那个细节方面可能还需要再打磨一下比如说用户体验这块",
        workflow: .translation
    ),
]
```

- [ ] **Step 2: 提交**

```bash
git add TalkFlowTests/PromptEvaluation/PromptTestCases.swift
git commit -m "feat: 添加 PromptTestCases 测试数据集"
```

---

### Task 5: PromptEvaluationTests XCTest 入口

**Files:**
- Create: `TalkFlowTests/PromptEvaluation/PromptEvaluationTests.swift`

- [ ] **Step 1: 写入口测试（含规则层检测，LLM 部分用 Mock）**

```swift
// TalkFlowTests/PromptEvaluation/PromptEvaluationTests.swift
import XCTest
@testable import TalkFlow

final class PromptEvaluationTests: XCTestCase {

    // MARK: - 规则层（纯函数，始终运行）

    func test_rules_only_allCases_pass() {
        for testCase in defaultPromptTestCases {
            let output = makeMinimalOutput(for: testCase)
            let checkCJK = testCase.workflow == .transcription
            let result = evaluateRules(input: testCase.input, output: output, config: .default, checkCJK: checkCJK)

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

        // 先规则后 LLM
        let checkCJK = testCase.workflow == .transcription
        let ruleResult = evaluateRules(input: testCase.input, output: output, config: .default, checkCJK: checkCJK)
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
        let output = "过度总结的结果" // 故意短输出
        let checkCJK = testCase.workflow == .transcription
        let ruleResult = evaluateRules(input: testCase.input, output: output, config: .default, checkCJK: checkCJK)
        guard ruleResult.passed else { return } // 规则层可能拦截

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
    // 模拟一个合理的最小输出 — 删除部分语气词
    let fillers = ["嗯", "啊", "额", "呃", "那个", "就是", "对吧", "的话", "怎么说呢", "反正", "那种"]
    var result = testCase.input
    for f in fillers {
        result = result.replacingOccurrences(of: f, with: "")
    }
    return result.trimmingCharacters(in: .whitespaces)
}
```

- [ ] **Step 2: 跑测试**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptEvaluationTests 2>&1 | tail -10
```
Expected: PASS

- [ ] **Step 3: 全量测试确认无回归**

```bash
make test
```
Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add TalkFlowTests/PromptEvaluation/PromptEvaluationTests.swift
git commit -m "feat: 添加 PromptEvaluationTests 入口"
```
