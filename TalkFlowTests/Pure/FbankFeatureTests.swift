// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class FbankFeatureTests: XCTestCase {

    // MARK: - applyLFR

    func test_applyLFR_emptyInput_returnsEmpty() {
        let feats: [[Float]] = []
        let result = applyLFR(feats)
        XCTAssertTrue(result.isEmpty)
    }

    func test_applyLFR_singleFrame_returnsEmpty() {
        let feats = [Array(repeating: 1.0 as Float, count: 80)]
        let result = applyLFR(feats)
        // 单帧被左填充 3 次 → padded 有 4 帧 < 7 → 0 输出
        XCTAssertTrue(result.isEmpty)
    }

    func test_applyLFR_minimalFrames_producesOutput() {
        let feats = Array(repeating: Array(repeating: 1.0 as Float, count: 80), count: 4)
        let result = applyLFR(feats)
        XCTAssertEqual(result.count, 1)
    }

    func test_applyLFR_outputDimension_is80x7() {
        let feats = Array(repeating: Array(repeating: Float(0), count: 80), count: 10)
        let result = applyLFR(feats)
        if let first = result.first {
            XCTAssertEqual(first.count, 560) // 80 * 7
        }
    }

    func test_applyLFR_leftPaddingUsesFirstFrame() {
        let feats = Array(repeating: Array(repeating: 1.0 as Float, count: 80), count: 7)
        let result = applyLFR(feats)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], Array(repeating: 1.0 as Float, count: 560))
    }

    // MARK: - applyCMVN

    func test_applyCMVN_preservesDimensions() {
        let feats: [[Float]] = [[1.0, 2.0], [3.0, 4.0]]
        let means: [Double] = [0.0, 0.0]
        let vars: [Double] = [1.0, 1.0]
        let result = applyCMVN(feats, means: means, vars: vars)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 2)
    }

    func test_applyCMVN_appliesFormula() {
        let feats: [[Float]] = [[2.0, 3.0]]
        let means: [Double] = [1.0, 2.0]
        let vars: [Double] = [4.0, 5.0]
        let result = applyCMVN(feats, means: means, vars: vars)
        XCTAssertEqual(result[0][0], (2.0 + 1.0) * 4.0)
        XCTAssertEqual(result[0][1], (3.0 + 2.0) * 5.0)
    }

    // MARK: - argmaxTokens

    func test_argmax_picksMaxIndex_perFrame() {
        // 帧0: [0.1, 0.2, 0.9, 0.3] → max=2; 帧1: [0.8, 0.1, 0.1, 0.4] → max=0(skip)
        let logits: [Float] = [0.1, 0.2, 0.9, 0.3, 0.8, 0.1, 0.1, 0.4]
        let tokens = argmaxTokens(logits: logits, frames: 2, vocabSize: 4)
        XCTAssertEqual(tokens, [2]) // idx 0 skipped
    }

    func test_argmax_skipsIndexZero() {
        let logits: [Float] = [1.0, 0.1, 0.1, 1.0, 0.1, 0.1]
        let tokens = argmaxTokens(logits: logits, frames: 2, vocabSize: 3)
        XCTAssertEqual(tokens, [])
    }

    func test_argmax_deduplicatesConsecutive() {
        let logits: [Float] = [0.1, 0.9, 0.1, 0.1, 0.9, 0.1, 0.9, 0.1, 0.1]
        let tokens = argmaxTokens(logits: logits, frames: 3, vocabSize: 3)
        XCTAssertEqual(tokens, [1])
    }

    // MARK: - postprocess

    func test_postprocess_removesTags() {
        XCTAssertEqual(postprocess("<|zh|>你好<|en|>"), "你好")
    }

    func test_postprocess_trimsWhitespace() {
        XCTAssertEqual(postprocess("  hello  "), "hello")
    }

    func test_postprocess_emptyString_returnsEmpty() {
        XCTAssertEqual(postprocess(""), "")
    }

    func test_postprocess_onlyTags_returnsEmpty() {
        XCTAssertEqual(postprocess("<|nospeech|>"), "")
    }
}
