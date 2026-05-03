import AppKit
import AVFoundation

// MARK: - 协议抽象（便于测试 Mock — rule 17）

protocol PermissionIO {
    /// 权限类型
    var kind: PermissionKind { get }

    /// ⚠️ 非引用透明：读取可变系统状态
    func currentStatus() -> PermissionStatus

    /// ⚠️ 含副作用：弹出系统授权对话框
    func requestAccess() async -> PermissionStatus

    /// ⚠️ 含副作用：打开系统设置面板
    func openSystemSettings()
}

// MARK: - ⚠️ 非纯函数（读系统状态，违反引用透明性 — rule 13）

/// 读取系统麦克风权限状态
fileprivate func micPermissionStatus() -> PermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:       return .authorized
    case .notDetermined:    return .notDetermined
    case .denied, .restricted: return .denied
    @unknown default:       return .notDetermined
    }
}

/// 读取系统辅助功能权限状态
/// 注意：辅助功能无 notDetermined 态，仅 authorized / denied
fileprivate func accessibilityPermissionStatus() -> PermissionStatus {
    AXIsProcessTrusted() ? .authorized : .denied
}

// MARK: - 麦克风权限 IO

struct MicrophonePermissionIO: PermissionIO {
    let kind: PermissionKind = .microphone

    /// ⚠️ 非引用透明
    func currentStatus() -> PermissionStatus {
        micPermissionStatus()
    }

    /// ⚠️ 弹出系统麦克风授权对话框
    func requestAccess() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(returning: micPermissionStatus())
            }
        }
    }

    /// ⚠️ 跳转系统设置 → 隐私 → 麦克风
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 辅助功能权限 IO

struct AccessibilityPermissionIO: PermissionIO {
    let kind: PermissionKind = .accessibility

    /// ⚠️ 非引用透明
    func currentStatus() -> PermissionStatus {
        accessibilityPermissionStatus()
    }

    /// ⚠️ 弹出辅助功能授权提示（仅首次有效，需用户手动在系统设置中开启）
    func requestAccess() async -> PermissionStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // 系统对话框为同步弹出，短暂等待后轮询
        try? await Task.sleep(nanoseconds: 800_000_000)
        return currentStatus()
    }

    /// ⚠️ 跳转系统设置 → 隐私 → 辅助功能
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
