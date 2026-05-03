import Foundation
@testable import TalkFlow

// MARK: - MockPasteIO

final class MockPasteIO: PasteIO {
    var shouldSucceed = true
    var pasteCallCount = 0

    func paste() -> Bool {
        pasteCallCount += 1
        return shouldSucceed
    }
}
