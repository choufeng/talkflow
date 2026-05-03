// TalkFlowTests/Mocks/MockPermissionIO.swift
import Foundation
@testable import TalkFlow

final class MockPermissionIO: PermissionIO {
    let kind: PermissionKind
    var stubbedStatus: PermissionStatus
    var requestAccessCallCount = 0
    var openSystemSettingsCallCount = 0
    var currentStatusCallCount = 0

    init(kind: PermissionKind = .microphone, status: PermissionStatus = .notDetermined) {
        self.kind = kind
        self.stubbedStatus = status
    }

    func currentStatus() -> PermissionStatus {
        currentStatusCallCount += 1
        return stubbedStatus
    }

    func requestAccess() async -> PermissionStatus {
        requestAccessCallCount += 1
        return stubbedStatus
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
