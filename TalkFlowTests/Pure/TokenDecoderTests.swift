// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class TokenDecoderTests: XCTestCase {

    func test_decode_emptyTokenIds_returnsEmptyString() {
        let tokens: [Int: String] = [1: "你", 2: "好"]
        let result = decodeTokenIds([], tokens: tokens)
        XCTAssertEqual(result, "")
    }

    func test_decode_singleToken_returnsCorrectText() {
        let tokens: [Int: String] = [1: "你", 2: "好"]
        let result = decodeTokenIds([1, 2], tokens: tokens)
        XCTAssertEqual(result, "你好")
    }

    func test_decode_skipsUnknownTokens() {
        let tokens: [Int: String] = [1: "a"]
        let result = decodeTokenIds([1, 99, 1], tokens: tokens)
        XCTAssertEqual(result, "aa")
    }
}
