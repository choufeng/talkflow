// TalkFlowTests/Mocks/MockClipboardIO.swift
import Foundation
@testable import TalkFlow

final class MockClipboardIO: ClipboardIO {
    var writtenTexts: [String] = []
    var pasteCallCount = 0
    var readCallCount = 0
    var stubbedReadResult: String?

    func write(_ text: String) {
        writtenTexts.append(text)
    }

    func paste() {
        pasteCallCount += 1
    }

    func read() -> String? {
        readCallCount += 1
        return stubbedReadResult
    }
}
