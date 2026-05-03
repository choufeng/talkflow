import Foundation

// MARK: - ADT（代数数据类型）

/// 录音阶段状态
enum RecordingPhase: Equatable {
    case idle
    case recording(startedAt: Date)
}

/// 录音完成结果
struct RecordingResult: Equatable {
    let url: URL
    let duration: TimeInterval
}

// MARK: - 纯函数

/// 状态机转换：toggle 触发
func recordingPhaseFromToggle(_ current: RecordingPhase, now: Date) -> RecordingPhase {
    switch current {
    case .idle:
        return .recording(startedAt: now)
    case .recording:
        return .idle
    }
}

/// 防抖判定：自上次 toggle 是否已过 debounce 秒
func shouldAcceptToggle(lastToggleTime: Date?, now: Date, debounce: TimeInterval) -> Bool {
    lastToggleTime.map { now.timeIntervalSince($0) >= debounce } ?? true
}

/// 是否满足最短录音时长
func shouldSave(duration: TimeInterval, minDuration: TimeInterval) -> Bool {
    duration >= minDuration
}

/// 计算录音时长
func durationFrom(startDate: Date, endDate: Date) -> TimeInterval {
    endDate.timeIntervalSince(startDate)
}

/// 生成录音文件名
func recordingFilename(from date: Date, index: Int) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    fmt.timeZone = TimeZone.current
    let ts = fmt.string(from: date)
    return "\(ts)_\(String(format: "%03d", index)).m4a"
}

/// 格式化时长为 MM:SS
func formatDuration(_ duration: TimeInterval) -> String {
    let total = Int(duration)
    let mins = total / 60
    let secs = total % 60
    return String(format: "%02d:%02d", mins, secs)
}
