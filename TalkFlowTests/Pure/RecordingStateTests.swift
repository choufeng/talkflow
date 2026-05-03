import XCTest
@testable import TalkFlow

final class RecordingStateTests: XCTestCase {

    // MARK: - RecordingPhase

    func test_recordingPhase_idle_isDefault() {
        let phase = RecordingPhase.idle
        XCTAssertEqual(phase, .idle)
    }

    func test_recordingPhase_recording_storesStartDate() {
        let now = Date()
        let phase = RecordingPhase.recording(startedAt: now)
        if case .recording(let startedAt) = phase {
            XCTAssertEqual(startedAt.timeIntervalSinceReferenceDate,
                           now.timeIntervalSinceReferenceDate,
                           accuracy: 0.001)
        } else {
            XCTFail("Expected .recording")
        }
    }

    func test_recordingPhase_equatable() {
        let d = Date()
        XCTAssertEqual(RecordingPhase.idle, RecordingPhase.idle)
        XCTAssertEqual(RecordingPhase.recording(startedAt: d), RecordingPhase.recording(startedAt: d))
        XCTAssertNotEqual(RecordingPhase.idle, RecordingPhase.recording(startedAt: Date()))
    }

    // MARK: - recordingPhaseFromToggle

    func test_recordingPhaseFromToggle_idleToRecording() {
        let now = Date()
        let next = recordingPhaseFromToggle(.idle, now: now)
        XCTAssertEqual(next, .recording(startedAt: now))
    }

    func test_recordingPhaseFromToggle_recordingToIdle() {
        let phase = RecordingPhase.recording(startedAt: Date())
        let next = recordingPhaseFromToggle(phase, now: Date())
        XCTAssertEqual(next, .idle)
    }

    // MARK: - shouldAcceptToggle (防抖)

    func test_shouldAcceptToggle_firstPress_alwaysAccepts() {
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: nil, now: Date(), debounce: 0.5))
    }

    func test_shouldAcceptToggle_withinDebounce_rejects() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.3)
        XCTAssertFalse(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    func test_shouldAcceptToggle_outsideDebounce_accepts() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.6)
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    func test_shouldAcceptToggle_exactlyAtDebounce_accepts() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.5)
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    // MARK: - shouldSave

    func test_shouldSave_belowMinDuration_false() {
        XCTAssertFalse(shouldSave(duration: 0.9, minDuration: 1.0))
    }

    func test_shouldSave_exactlyMinDuration_true() {
        XCTAssertTrue(shouldSave(duration: 1.0, minDuration: 1.0))
    }

    func test_shouldSave_aboveMinDuration_true() {
        XCTAssertTrue(shouldSave(duration: 3.5, minDuration: 1.0))
    }

    // MARK: - durationFrom

    func test_durationFrom_computesInterval() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = Date(timeIntervalSinceReferenceDate: 3.5)
        XCTAssertEqual(durationFrom(startDate: start, endDate: end), 3.5, accuracy: 0.001)
    }

    // MARK: - recordingFilename

    func test_recordingFilename_containsTimestampAndIndex() {
        let date = Date(timeIntervalSinceReferenceDate: 733000000)
        let name = recordingFilename(from: date, index: 1)
        XCTAssertTrue(name.hasSuffix("_001.m4a"))
    }

    func test_recordingFilename_indexPadsToThreeDigits() {
        let name = recordingFilename(from: Date(), index: 42)
        XCTAssertTrue(name.contains("_042.m4a"))
    }

    // MARK: - formatDuration

    func test_formatDuration_zero() {
        XCTAssertEqual(formatDuration(0), "00:00")
    }

    func test_formatDuration_exactlyOneSecond() {
        XCTAssertEqual(formatDuration(1.0), "00:01")
    }

    func test_formatDuration_minuteWithSeconds() {
        XCTAssertEqual(formatDuration(125.0), "02:05")
    }

    func test_formatDuration_roundingDown() {
        XCTAssertEqual(formatDuration(5.9), "00:05")
    }
}
