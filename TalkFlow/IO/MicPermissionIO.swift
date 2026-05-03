import AppKit
import AVFoundation

// MARK: - 协议抽象（便于测试 Mock）

protocol MicPermissionIO {
    /// 获取当前权限状态
    /// ⚠️ 非引用透明：读取可变系统状态，same call → different result over time
    func currentStatus() -> MicPermissionStatus

    /// 根据状态执行授权操作，返回操作后的状态
    /// ⚠️ 含副作用：弹出系统对话框 或 打开系统设置
    func performAction(for status: MicPermissionStatus) async -> MicPermissionStatus
}

// MARK: - ⚠️ 非纯函数（读系统状态，违反引用透明性）

/// 读取系统麦克风权限状态
/// 此调用读取可变外部状态，非引用透明，仅限 IO 层使用
func micPermissionStatus() -> MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:       return .authorized
    case .notDetermined:    return .notDetermined
    case .denied, .restricted: return .denied
    @unknown default:       return .notDetermined
    }
}

// MARK: - 默认实现

struct DefaultMicPermissionIO: MicPermissionIO {

    /// ⚠️ 非引用透明：每次调用读取可变系统状态
    func currentStatus() -> MicPermissionStatus {
        micPermissionStatus()
    }

    /// ⚠️ 含副作用：根据状态弹出系统对话框或打开系统设置
    func performAction(for status: MicPermissionStatus) async -> MicPermissionStatus {
        switch status {
        case .denied:        return impureOpenSystemPreferences(status)
        case .notDetermined: return await impureRequestAccess()
        case .authorized:    return status
        }
    }

    // MARK: - ⚠️ 副作用（私有）

    private func impureRequestAccess() async -> MicPermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(returning: micPermissionStatus())
            }
        }
    }

    private func impureOpenSystemPreferences(_ status: MicPermissionStatus) -> MicPermissionStatus {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return status }
        NSWorkspace.shared.open(url)
        return status
    }
}
