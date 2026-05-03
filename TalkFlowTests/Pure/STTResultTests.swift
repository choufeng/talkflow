// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class STTResultTests: XCTestCase {

    func test_speech_result_equals_sameValues() {
        let a = STTResult.speech(text: "你好", language: "zh")
        let b = STTResult.speech(text: "你好", language: "zh")
        XCTAssertEqual(a, b)
    }

    func test_speech_result_notEquals_differentText() {
        let a = STTResult.speech(text: "你好", language: "zh")
        let b = STTResult.speech(text: "Hello", language: "en")
        XCTAssertNotEqual(a, b)
    }

    func test_silence_equals_silence() {
        XCTAssertEqual(STTResult.silence, STTResult.silence)
    }

    func test_failure_equals_sameError() {
        let a = STTResult.failure(.modelNotReady)
        let b = STTResult.failure(.modelNotReady)
        XCTAssertEqual(a, b)
    }

    func test_different_case_notEqual() {
        XCTAssertNotEqual(STTResult.silence, STTResult.speech(text: "", language: ""))
    }
}
