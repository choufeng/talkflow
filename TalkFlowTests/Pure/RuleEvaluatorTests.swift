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
        let translationConfig = RuleEvalConfig(minCharRatio: 0.2, maxCharRatio: 3.0, minCJKRatio: 0.0)
        let result = evaluateRules(input: input, output: output, config: translationConfig, checkCJK: false)
        XCTAssertTrue(result.passed)
    }
}
