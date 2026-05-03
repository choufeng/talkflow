import Foundation
@testable import TalkFlow

final class MockAudioRecorderIO: AudioRecorderIO {

    var isRecording: Bool = false
    var recordingURL: URL?

    var startRecordingCallCount = 0
    var startRecordingLastURL: URL?
    var stubbedStartError: RecordingError?

    var stopRecordingCallCount = 0
    var stubbedDuration: TimeInterval = 3.0

    var cancelRecordingCallCount = 0

    func startRecording(to url: URL) throws {
        startRecordingCallCount += 1
        startRecordingLastURL = url
        if let error = stubbedStartError {
            throw error
        }
        isRecording = true
        recordingURL = url
    }

    func stopRecording() -> TimeInterval {
        stopRecordingCallCount += 1
        isRecording = false
        return stubbedDuration
    }

    func cancelRecording() {
        cancelRecordingCallCount += 1
        isRecording = false
        recordingURL = nil
    }
}
