// TalkFlowTests/ViewLogic/PermissionCheckViewTests.swift
import XCTest
import AppKit
@testable import TalkFlow

/// View 逻辑测试：验证数据 → UI 映射，不测 Autolayout/像素
final class PermissionCheckViewTests: XCTestCase {

    // MARK: - authorized 状态

    func test_render_whenAuthorized_shouldShowAuthorizedLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "✅ 麦克风权限：已启用")
    }

    func test_render_whenAuthorized_shouldSetGreenColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .systemGreen)
    }

    func test_render_whenAuthorized_shouldHideButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertTrue(button?.isHidden ?? false)
    }

    // MARK: - notDetermined 状态

    func test_render_whenNotDetermined_shouldShowRequestLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "🎤 需要麦克风权限来录制语音")
    }

    func test_render_whenNotDetermined_shouldShowSecondaryLabelColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .secondaryLabelColor)
    }

    func test_render_whenNotDetermined_shouldShowGrantButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertEqual(button?.title, "授予麦克风权限")
        XCTAssertFalse(button?.isHidden ?? true)
    }

    // MARK: - denied 状态

    func test_render_whenDenied_shouldShowDeniedLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_render_whenDenied_shouldShowSecondaryLabelColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .secondaryLabelColor)
    }

    func test_render_whenDenied_shouldShowOpenSettingsButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertEqual(button?.title, "打开系统设置")
        XCTAssertFalse(button?.isHidden ?? true)
    }

    // MARK: - IO 交互验证

    func test_buttonClick_shouldCallPerformAction() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        button?.performClick(nil)

        let expectation = XCTestExpectation(description: "performAction called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if mock.performActionCallCount > 0 {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    // MARK: - IO 注入验证

    func test_defaultInit_shouldUseDefaultMicPermissionIO() {
        let view = PermissionCheckView(frame: .zero)
        // 默认构造不应崩溃
        XCTAssertNotNil(view)
    }
}
