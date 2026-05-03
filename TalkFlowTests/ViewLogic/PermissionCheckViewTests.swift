// TalkFlowTests/ViewLogic/PermissionCheckViewTests.swift
import XCTest
import AppKit
@testable import TalkFlow

final class PermissionRowViewTests: XCTestCase {

    // MARK: - authorized 麦克风

    func test_render_authorizedMicrophone_shouldShowGreenLabel() {
        let mock = MockPermissionIO(kind: .microphone, status: .authorized)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .systemGreen)
    }

    func test_render_authorizedMicrophone_shouldHideButton() {
        let mock = MockPermissionIO(kind: .microphone, status: .authorized)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let button = row.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertTrue(button?.isHidden ?? false)
    }

    func test_render_authorizedMicrophone_shouldShowAuthorizedLabel() {
        let mock = MockPermissionIO(kind: .microphone, status: .authorized)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "✅ 麦克风权限：已启用")
    }

    // MARK: - authorized 辅助功能

    func test_render_authorizedAccessibility_shouldShowGreenLabel() {
        let mock = MockPermissionIO(kind: .accessibility, status: .authorized)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .systemGreen)
    }

    // MARK: - notDetermined

    func test_render_notDeterminedMicrophone_shouldShowRequestLabel() {
        let mock = MockPermissionIO(kind: .microphone, status: .notDetermined)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "🎤 需要麦克风权限")
    }

    func test_render_notDetermined_shouldShowButton() {
        let mock = MockPermissionIO(kind: .microphone, status: .notDetermined)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let button = row.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertFalse(button?.isHidden ?? true)
        XCTAssertEqual(button?.title, "授予麦克风权限")
    }

    func test_render_notDetermined_shouldNotBeGreen() {
        let mock = MockPermissionIO(kind: .microphone, status: .notDetermined)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .secondaryLabelColor)
    }

    // MARK: - denied

    func test_render_denied_shouldShowDeniedLabel() {
        let mock = MockPermissionIO(kind: .microphone, status: .denied)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_render_denied_shouldShowSettingsButton() {
        let mock = MockPermissionIO(kind: .microphone, status: .denied)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let button = row.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertEqual(button?.title, "打开系统设置")
        XCTAssertFalse(button?.isHidden ?? true)
    }

    // MARK: - button click → IO 交互

    func test_buttonClick_whenNotDetermined_shouldCallRequestAccess() {
        let mock = MockPermissionIO(kind: .microphone, status: .notDetermined)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let button = row.subviews.compactMap { $0 as? NSButton }.first
        button?.performClick(nil)

        let exp = XCTestExpectation(description: "requestAccess called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if mock.requestAccessCallCount > 0 { exp.fulfill() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertGreaterThan(mock.requestAccessCallCount, 0)
    }

    func test_buttonClick_whenDenied_shouldCallOpenSystemSettings() {
        let mock = MockPermissionIO(kind: .microphone, status: .denied)
        let row = PermissionRowView(io: mock)
        row.setUp()

        let button = row.subviews.compactMap { $0 as? NSButton }.first
        button?.performClick(nil)

        let exp = XCTestExpectation(description: "openSystemSettings called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if mock.openSystemSettingsCallCount > 0 { exp.fulfill() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertGreaterThan(mock.openSystemSettingsCallCount, 0)
    }
}
