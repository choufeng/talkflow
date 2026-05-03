// TalkFlowTests/Pure/MicPermissionUIStateTests.swift
import XCTest
@testable import TalkFlow

final class PermissionKindTests: XCTestCase {

    func test_permissionKind_microphone_exists() {
        let kind: PermissionKind = .microphone
        XCTAssertEqual(kind, .microphone)
    }

    func test_permissionKind_accessibility_exists() {
        let kind: PermissionKind = .accessibility
        XCTAssertEqual(kind, .accessibility)
    }

    // MARK: - PermissionState

    func test_permissionState_authorizedMicrophone() {
        let s = PermissionState(kind: .microphone, status: .authorized)
        XCTAssertEqual(s.kind, .microphone)
        XCTAssertEqual(s.status, .authorized)
    }

    func test_permissionState_deniedAccessibility() {
        let s = PermissionState(kind: .accessibility, status: .denied)
        XCTAssertEqual(s.kind, .accessibility)
        XCTAssertEqual(s.status, .denied)
    }

    // MARK: - PermissionStatus enum cases

    func test_permissionStatus_hasThreeCases() {
        let cases: [PermissionStatus] = [.authorized, .notDetermined, .denied]
        XCTAssertEqual(cases.count, 3)
    }

    func test_permissionStatus_equatable() {
        XCTAssertEqual(PermissionStatus.authorized, PermissionStatus.authorized)
        XCTAssertNotEqual(PermissionStatus.authorized, PermissionStatus.denied)
    }
}
