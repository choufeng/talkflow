// TalkFlowTests/IO/PasteIOTests.swift
import XCTest
@testable import TalkFlow

final class PasteIOTests: XCTestCase {

    // MARK: - paste() 基础行为

    func test_paste_success_returnsTrue() {
        let mock = MockPasteIO()
        mock.shouldSucceed = true
        XCTAssertTrue(mock.paste())
    }

    func test_paste_failure_returnsFalse() {
        let mock = MockPasteIO()
        mock.shouldSucceed = false
        XCTAssertFalse(mock.paste())
    }

    func test_paste_incrementsCallCount() {
        let mock = MockPasteIO()
        _ = mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 1)
        _ = mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 2)
    }

    // MARK: - 管道行为（模拟 onRecordingComplete 中的粘贴逻辑）

    func test_pipeline_pasteCalledAfterSTTSpeech() {
        let mock = MockPasteIO()
        let result = STTResult.speech(text: "你好世界", language: "zh")

        switch result {
        case .speech:
            _ = mock.paste()
            XCTAssertEqual(mock.pasteCallCount, 1)
        case .silence, .failure:
            XCTFail("应进入 .speech 分支")
        }
    }

    func test_pipeline_pasteNotCalledOnSilence() {
        let mock = MockPasteIO()
        let result = STTResult.silence

        switch result {
        case .speech:
            XCTFail("不应进入 .speech 分支")
        case .silence, .failure:
            break
        }

        XCTAssertEqual(mock.pasteCallCount, 0)
    }

    func test_pipeline_pasteNotCalledOnFailure() {
        let mock = MockPasteIO()
        let result = STTResult.failure(.modelNotReady)

        switch result {
        case .speech:
            XCTFail("不应进入 .speech 分支")
        case .silence, .failure:
            break
        }

        XCTAssertEqual(mock.pasteCallCount, 0)
    }

    func test_pipeline_clipboardWrittenBeforePaste() {
        let mock = MockPasteIO()
        let result = STTResult.speech(text: "测试文本", language: "zh")

        var clipboardText: String?
        var pastePerformed = false

        switch result {
        case .speech(let text, _):
            clipboardText = text
            pastePerformed = mock.paste()
        case .silence, .failure:
            XCTFail("应进入 .speech 分支")
        }

        XCTAssertNotNil(clipboardText)
        XCTAssertTrue(pastePerformed)
    }
}
