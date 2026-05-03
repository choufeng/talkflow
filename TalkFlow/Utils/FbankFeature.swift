import Foundation

// MARK: - 低帧率拼接（LFR）

/// LFR: 将 10ms 步进的 fbank 特征拼接为 60ms 步进
/// 参数: m=7（拼接宽度）, n=6（步进步长）
/// 输入: [N 帧 × 80 维]
/// 输出: [T_LFR 帧 × 560 维]
func applyLFR(_ feats: [[Float]]) -> [[Float]] {
    let lfrM = 7
    let lfrN = 6
    let leftPad = (lfrM - 1) / 2

    guard let first = feats.first, !first.isEmpty else { return [] }

    let dim = first.count
    // 左填充：复制首帧 leftPad 次
    let padding = Array(repeating: first, count: leftPad)
    let padded = padding + feats

    guard padded.count >= lfrM else { return [] }

    let tLFR = (padded.count - lfrM) / lfrN + 1
    let lfrDim = dim * lfrM

    return (0..<tLFR).map { i -> [Float] in
        let start = i * lfrN
        return (0..<lfrM).flatMap { j in
            padded[start + j]
        }
    }
}

// MARK: - CMVN 归一化

/// CMVN: (feat + mean) * var
func applyCMVN(_ feats: [[Float]], means: [Double], vars: [Double]) -> [[Float]] {
    let n = min(means.count, vars.count)
    return feats.map { frame in
        frame.enumerated().map { i, v in
            guard i < n else { return v }
            return Float((Double(v) + means[i]) * vars[i])
        }
    }
}

// MARK: - Token 解码

/// argmax: 从 ONNX 输出 logits 取每帧最大 token_id
/// - 跳过 token_id == 0（blank）
/// - 去重（连续相同 token 只保留一个）
func argmaxTokens(logits: [Float], frames: Int, vocabSize: Int) -> [Int32] {
    (0..<frames).reduce(into: [Int32]()) { result, t in
        let start = t * vocabSize
        let row = Array(logits[start..<start + vocabSize])
        guard let maxIdx = row.indices.max(by: { row[$0] < row[$1] }),
              maxIdx != 0,
              result.last != Int32(maxIdx)
        else { return }
        result.append(Int32(maxIdx))
    }
}

// MARK: - 后处理

/// 去除 <|tag|> 特殊标记，trim 空白
func postprocess(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let range = NSRange(text.startIndex..., in: text)
    let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}
