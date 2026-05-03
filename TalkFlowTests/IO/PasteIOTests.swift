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
}
