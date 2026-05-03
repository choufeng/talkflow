import Foundation

/// 管道阶段 — 驱动浮窗显示状态
enum PipelinePhase {
    case recording
    case transcribing
    case pasteFailed
}
