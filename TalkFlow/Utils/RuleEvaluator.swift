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
