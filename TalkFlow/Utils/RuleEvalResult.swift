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
