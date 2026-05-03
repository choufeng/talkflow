// TalkFlowTests/Pure/MicPermissionStatusTests.swift
import XCTest
@testable import TalkFlow

/// 穷尽测试 MicPermissionStatus 枚举的 produceUIState 映射
final class MicPermissionStatusTests: XCTestCase {

    // MARK: - authorized

    func test_authorized_shouldProduceAuthorizedLabel() {
        let state = produceUIState(from: .authorized)
        XCTAssertEqual(state.label, "✅ 麦克风权限：已启用")
    }

    func test_authorized_shouldHideButton() {
        let state = produceUIState(from: .authorized)
        XCTAssertFalse(state.buttonVisible)
    }

    func test_authorized_shouldNotNeedSystemSettings() {
        let state = produceUIState(from: .authorized)
        XCTAssertFalse(state.needsSystemSettings)
    }

    // MARK: - notDetermined

    func test_notDetermined_shouldProduceRequestLabel() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertEqual(state.label, "🎤 需要麦克风权限来录制语音")
    }

    func test_notDetermined_shouldShowButton() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertTrue(state.buttonVisible)
    }

    func test_notDetermined_shouldNotNeedSystemSettings() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertFalse(state.needsSystemSettings)
    }

    // MARK: - denied

    func test_denied_shouldProduceDeniedLabel() {
        let state = produceUIState(from: .denied)
        XCTAssertEqual(state.label, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_denied_shouldShowButton() {
        let state = produceUIState(from: .denied)
        XCTAssertTrue(state.buttonVisible)
    }

    func test_denied_shouldNeedSystemSettings() {
        let state = produceUIState(from: .denied)
        XCTAssertTrue(state.needsSystemSettings)
    }
}
