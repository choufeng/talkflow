// TalkFlowTests/IO/ClipboardIOTests.swift
import XCTest
@testable import TalkFlow

final class ClipboardIOTests: XCTestCase {

    // MARK: - write()

    func test_write_shouldAppendTextToWrittenTexts() {
        let mock = MockClipboardIO()
        mock.write("hello")
        XCTAssertEqual(mock.writtenTexts, ["hello"])
    }

    func test_writeMultipleTimes_shouldAccumulateInOrder() {
        let mock = MockClipboardIO()
        mock.write("first")
        mock.write("second")
        mock.write("third")
        XCTAssertEqual(mock.writtenTexts, ["first", "second", "third"])
    }

    // MARK: - paste()

    func test_paste_shouldIncrementCallCount() {
        let mock = MockClipboardIO()
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 1)
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 2)
    }

    // MARK: - read()

    func test_read_shouldReturnStubbedValue() {
        let mock = MockClipboardIO()
        mock.stubbedReadResult = "copied text"
        XCTAssertEqual(mock.read(), "copied text")
    }

    func test_read_shouldIncrementCallCount() {
        let mock = MockClipboardIO()
        _ = mock.read()
        _ = mock.read()
        XCTAssertEqual(mock.readCallCount, 2)
    }

    func test_read_whenNoStub_shouldReturnNil() {
        let mock = MockClipboardIO()
        XCTAssertNil(mock.read())
    }
}
