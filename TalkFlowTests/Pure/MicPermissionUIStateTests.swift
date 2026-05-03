// TalkFlowTests/Pure/MicPermissionUIStateTests.swift
import XCTest
@testable import TalkFlow

/// 验证 MicPermissionUIState 静态预置值的完整性
final class MicPermissionUIStateTests: XCTestCase {

    // MARK: - .authorized 预置值

    func test_authorizedPreset_label_shouldBeAuthorized() {
        XCTAssertEqual(MicPermissionUIState.authorized.label, "✅ 麦克风权限：已启用")
    }

    func test_authorizedPreset_buttonVisible_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.authorized.buttonVisible)
    }

    func test_authorizedPreset_buttonTitle_shouldBeEmpty() {
        XCTAssertEqual(MicPermissionUIState.authorized.buttonTitle, "")
    }

    func test_authorizedPreset_needsSystemSettings_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.authorized.needsSystemSettings)
    }

    // MARK: - .notDetermined 预置值

    func test_notDeterminedPreset_label_shouldBeRequest() {
        XCTAssertEqual(MicPermissionUIState.notDetermined.label, "🎤 需要麦克风权限来录制语音")
    }

    func test_notDeterminedPreset_buttonVisible_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.notDetermined.buttonVisible)
    }

    func test_notDeterminedPreset_buttonTitle_shouldBeGrant() {
        XCTAssertEqual(MicPermissionUIState.notDetermined.buttonTitle, "授予麦克风权限")
    }

    func test_notDeterminedPreset_needsSystemSettings_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.notDetermined.needsSystemSettings)
    }

    // MARK: - .denied 预置值

    func test_deniedPreset_label_shouldBeDenied() {
        XCTAssertEqual(MicPermissionUIState.denied.label, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_deniedPreset_buttonVisible_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.denied.buttonVisible)
    }

    func test_deniedPreset_buttonTitle_shouldBeOpenSettings() {
        XCTAssertEqual(MicPermissionUIState.denied.buttonTitle, "打开系统设置")
    }

    func test_deniedPreset_needsSystemSettings_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.denied.needsSystemSettings)
    }
}
