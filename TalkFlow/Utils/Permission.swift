// 纯数据类型 — 零副作用，零外部依赖

// MARK: - 代数数据类型（ADT）

/// 权限类型（sum type — rule 11）
enum PermissionKind: Equatable {
    case microphone
    case accessibility
}

/// 权限状态（sum type — rule 11）
enum PermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
}

/// 单个权限的完整状态（product type — rule 11）
struct PermissionState: Equatable {
    let kind: PermissionKind
    let status: PermissionStatus
}

/// 权限的 UI 展示状态（product type — rule 11）
struct PermissionUIState {
    let displayName: String
    let label: String
    let buttonTitle: String
    let buttonVisible: Bool
}

// MARK: - 纯函数（引用透明，无副作用）

/// 权限类型 → 显示名称
func produceDisplayName(for kind: PermissionKind) -> String {
    switch kind {
    case .microphone:    return "麦克风"
    case .accessibility: return "辅助功能"
    }
}

/// 权限类型 + 授权态 → 授权文案
func produceGrantLabel(for kind: PermissionKind) -> String {
    switch kind {
    case .microphone:    return "🎤"
    case .accessibility: return "⌨️"
    }
}

/// 权限状态 → UI 状态（核心纯函数）
func produceUIState(from state: PermissionState) -> PermissionUIState {
    let name = produceDisplayName(for: state.kind)
    let icon = produceGrantLabel(for: state.kind)
    switch state.status {
    case .authorized:
        return PermissionUIState(
            displayName: name,
            label: "✅ \(name)权限：已启用",
            buttonTitle: "",
            buttonVisible: false
        )
    case .notDetermined:
        return PermissionUIState(
            displayName: name,
            label: "\(icon) 需要\(name)权限",
            buttonTitle: "授予\(name)权限",
            buttonVisible: true
        )
    case .denied:
        return PermissionUIState(
            displayName: name,
            label: "⚠️ \(name)权限已被拒绝，请在系统设置中开启",
            buttonTitle: "打开系统设置",
            buttonVisible: true
        )
    }
}
