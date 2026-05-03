// TalkFlowTests/IO/MicPermissionIOTests.swift
import XCTest
@testable import TalkFlow

final class PermissionIOTests: XCTestCase {

    // MARK: - currentStatus()

    func test_currentStatus_shouldReturnStubbedValue() {
        let mock = MockPermissionIO(status: .authorized)
        XCTAssertEqual(mock.currentStatus(), .authorized)
        XCTAssertEqual(mock.currentStatusCallCount, 1)
    }

    func test_currentStatus_whenDenied_shouldReturnDenied() {
        let mock = MockPermissionIO(status: .denied)
        XCTAssertEqual(mock.currentStatus(), .denied)
    }

    func test_currentStatus_whenNotDetermined_shouldReturnNotDetermined() {
        let mock = MockPermissionIO(status: .notDetermined)
        XCTAssertEqual(mock.currentStatus(), .notDetermined)
    }

    // MARK: - kind

    func test_kind_microphone() {
        let mock = MockPermissionIO(kind: .microphone)
        XCTAssertEqual(mock.kind, .microphone)
    }

    func test_kind_accessibility() {
        let mock = MockPermissionIO(kind: .accessibility)
        XCTAssertEqual(mock.kind, .accessibility)
    }

    // MARK: - requestAccess()

    func test_requestAccess_shouldReturnStubbedStatus() async {
        let mock = MockPermissionIO(status: .authorized)
        let result = await mock.requestAccess()
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(mock.requestAccessCallCount, 1)
    }

    func test_requestAccess_shouldIncrementCallCount() async {
        let mock = MockPermissionIO(status: .denied)
        _ = await mock.requestAccess()
        _ = await mock.requestAccess()
        XCTAssertEqual(mock.requestAccessCallCount, 2)
    }

    // MARK: - openSystemSettings()

    func test_openSystemSettings_shouldIncrementCallCount() {
        let mock = MockPermissionIO()
        mock.openSystemSettings()
        XCTAssertEqual(mock.openSystemSettingsCallCount, 1)
        mock.openSystemSettings()
        XCTAssertEqual(mock.openSystemSettingsCallCount, 2)
    }
}
