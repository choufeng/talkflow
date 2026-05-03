import XCTest
@testable import TalkFlow

final class AudioRecorderIOTests: XCTestCase {

    func test_mockAudioRecorder_startsAndStops() throws {
        let mock = MockAudioRecorderIO()
        let url = URL(fileURLWithPath: "/tmp/test.m4a")

        XCTAssertFalse(mock.isRecording)
        try mock.startRecording(to: url)
        XCTAssertTrue(mock.isRecording)
        XCTAssertEqual(mock.startRecordingCallCount, 1)
        XCTAssertEqual(mock.startRecordingLastURL, url)
        XCTAssertEqual(mock.recordingURL, url)

        let dur = mock.stopRecording()
        XCTAssertFalse(mock.isRecording)
        XCTAssertEqual(mock.stopRecordingCallCount, 1)
        XCTAssertEqual(dur, 3.0)
    }

    func test_mockAudioRecorder_cancel() throws {
        let mock = MockAudioRecorderIO()
        try mock.startRecording(to: URL(fileURLWithPath: "/tmp/test.m4a"))

        mock.cancelRecording()
        XCTAssertFalse(mock.isRecording)
        XCTAssertEqual(mock.cancelRecordingCallCount, 1)
        XCTAssertNil(mock.recordingURL)
    }

    func test_mockAudioRecorder_startError() {
        let mock = MockAudioRecorderIO()
        mock.stubbedStartError = .couldNotStart

        XCTAssertThrowsError(try mock.startRecording(to: URL(fileURLWithPath: "/tmp/test.m4a"))) { error in
            XCTAssertEqual(error as? RecordingError, .couldNotStart)
        }
        XCTAssertFalse(mock.isRecording)
    }
}
