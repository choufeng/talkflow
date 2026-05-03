// TalkFlowTests/Pure/MicPermissionStatusTests.swift
import XCTest
@testable import TalkFlow

final class PermissionStatusTests: XCTestCase {

    // MARK: - produceDisplayName

    func test_displayName_microphone_shouldReturnChinese() {
        XCTAssertEqual(produceDisplayName(for: .microphone), "麦克风")
    }

    func test_displayName_accessibility_shouldReturnChinese() {
        XCTAssertEqual(produceDisplayName(for: .accessibility), "辅助功能")
    }

    // MARK: - produceGrantLabel

    func test_grantLabel_microphone_shouldReturnMicEmoji() {
        XCTAssertEqual(produceGrantLabel(for: .microphone), "🎤")
    }

    func test_grantLabel_accessibility_shouldReturnKeyboardEmoji() {
        XCTAssertEqual(produceGrantLabel(for: .accessibility), "⌨️")
    }

    // MARK: - produceUIState → authorized

    func test_authorized_microphone_shouldShowAuthorizedLabel() {
        let state = PermissionState(kind: .microphone, status: .authorized)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "✅ 麦克风权限：已启用")
        XCTAssertFalse(ui.buttonVisible)
        XCTAssertEqual(ui.buttonTitle, "")
    }

    func test_authorized_accessibility_shouldShowAuthorizedLabel() {
        let state = PermissionState(kind: .accessibility, status: .authorized)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "✅ 辅助功能权限：已启用")
        XCTAssertFalse(ui.buttonVisible)
    }

    // MARK: - produceUIState → notDetermined

    func test_notDetermined_microphone_shouldShowGrantLabel() {
        let state = PermissionState(kind: .microphone, status: .notDetermined)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "🎤 需要麦克风权限")
        XCTAssertTrue(ui.buttonVisible)
        XCTAssertEqual(ui.buttonTitle, "授予麦克风权限")
    }

    func test_notDetermined_accessibility_shouldShowGrantLabel() {
        let state = PermissionState(kind: .accessibility, status: .notDetermined)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "⌨️ 需要辅助功能权限")
        XCTAssertTrue(ui.buttonVisible)
        XCTAssertEqual(ui.buttonTitle, "授予辅助功能权限")
    }

    // MARK: - produceUIState → denied

    func test_denied_microphone_shouldShowDeniedLabel() {
        let state = PermissionState(kind: .microphone, status: .denied)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
        XCTAssertTrue(ui.buttonVisible)
        XCTAssertEqual(ui.buttonTitle, "打开系统设置")
    }

    func test_denied_accessibility_shouldShowDeniedLabel() {
        let state = PermissionState(kind: .accessibility, status: .denied)
        let ui = produceUIState(from: state)
        XCTAssertEqual(ui.label, "⚠️ 辅助功能权限已被拒绝，请在系统设置中开启")
        XCTAssertTrue(ui.buttonVisible)
    }
}
