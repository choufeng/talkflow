// 纯数据类型 — 零副作用，零外部依赖

// MARK: - 代数数据类型（ADT）

/// 麦克风权限状态（sum type）
enum MicPermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
}

/// 麦克风权限的 UI 展示状态（product type）
struct MicPermissionUIState {
    let label: String
    let buttonTitle: String
    let buttonVisible: Bool
    let needsSystemSettings: Bool
}

// MARK: - 预置 UI 状态值

extension MicPermissionUIState {
    static let authorized = MicPermissionUIState(
        label: "✅ 麦克风权限：已启用",
        buttonTitle: "",
        buttonVisible: false,
        needsSystemSettings: false
    )
    static let notDetermined = MicPermissionUIState(
        label: "🎤 需要麦克风权限来录制语音",
        buttonTitle: "授予麦克风权限",
        buttonVisible: true,
        needsSystemSettings: false
    )
    static let denied = MicPermissionUIState(
        label: "⚠️ 麦克风权限已被拒绝，请在系统设置中开启",
        buttonTitle: "打开系统设置",
        buttonVisible: true,
        needsSystemSettings: true
    )
}

// MARK: - 纯函数（引用透明）

/// 权限状态 → UI 状态映射
/// 纯函数：给定相同输入必返回相同输出，无外部依赖
func produceUIState(from status: MicPermissionStatus) -> MicPermissionUIState {
    switch status {
    case .authorized:    return .authorized
    case .notDetermined: return .notDetermined
    case .denied:        return .denied
    }
}
