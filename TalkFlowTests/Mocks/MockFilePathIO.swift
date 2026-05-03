import Foundation
@testable import TalkFlow

final class MockFilePathIO: FilePathIO {

    var stubbedDirectory: URL = URL(fileURLWithPath: "/tmp/TalkFlowTest/Recordings")
    var stubbedNextURL: URL = URL(fileURLWithPath: "/tmp/TalkFlowTest/Recordings/test_001.m4a")
    var nextRecordingURLCallCount = 0

    var recordingsDirectory: URL {
        stubbedDirectory
    }

    func nextRecordingURL() -> URL {
        nextRecordingURLCallCount += 1
        return stubbedNextURL
    }
}
