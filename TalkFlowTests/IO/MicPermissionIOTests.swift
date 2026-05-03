// TalkFlowTests/IO/MicPermissionIOTests.swift
import XCTest
@testable import TalkFlow

/// 通过 MockMicPermissionIO 验证 IO 协议行为
final class MicPermissionIOTests: XCTestCase {

    // MARK: - currentStatus()

    func test_currentStatus_shouldReturnStubbedValue() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        XCTAssertEqual(mock.currentStatus(), .authorized)
    }

    func test_currentStatus_whenNotDetermined_shouldReturnNotDetermined() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        XCTAssertEqual(mock.currentStatus(), .notDetermined)
    }

    func test_currentStatus_whenDenied_shouldReturnDenied() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        XCTAssertEqual(mock.currentStatus(), .denied)
    }

    // MARK: - performAction(for:) 调用计数与参数记录

    func test_performAction_shouldIncrementCallCount() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionCallCount, 1)
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionCallCount, 2)
    }

    func test_performAction_shouldRecordReceivedStatus() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        _ = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(mock.performActionReceivedStatuses, [.notDetermined])
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionReceivedStatuses, [.notDetermined, .denied])
    }

    func test_performAction_shouldReturnStubbedStatus() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let result = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(result, .authorized)
    }

    // MARK: - performAction(for:) 各分支路径验证

    func test_performAction_whenAuthorized_shouldNotChangeState() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let result = await mock.performAction(for: .authorized)
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    func test_performAction_whenNotDetermined_shouldSimulateRequestAccess() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let result = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(result, .notDetermined)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    func test_performAction_whenDenied_shouldSimulateOpenPreferences() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let result = await mock.performAction(for: .denied)
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }
}
