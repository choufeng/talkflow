// TalkFlowTests/Mocks/MockMicPermissionIO.swift
import Foundation
@testable import TalkFlow

/// Mock 实现 MicPermissionIO 协议，用于单元测试
/// 无任何真实副作用，通过 stubbed 值控制行为
final class MockMicPermissionIO: MicPermissionIO {
    var stubbedStatus: MicPermissionStatus = .notDetermined
    var performActionCallCount = 0
    var performActionReceivedStatuses: [MicPermissionStatus] = []

    func currentStatus() -> MicPermissionStatus {
        stubbedStatus
    }

    func performAction(for status: MicPermissionStatus) async -> MicPermissionStatus {
        performActionCallCount += 1
        performActionReceivedStatuses.append(status)
        return stubbedStatus
    }
}
