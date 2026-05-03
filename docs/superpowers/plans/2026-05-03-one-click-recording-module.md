# 一键录音模块 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现独立录音模块 — 全局快捷键 toggle 录音/停止、ESC 取消、500ms 防抖、<1s 丢弃、AAC/m4a 保存至 Application Support 目录。

**Architecture:** 分为 Utils（纯函数数据类型）、IO（副作用协议+实现）、Views（AppKit 状态窗）三层。协调逻辑收敛在 AppDelegate。严格遵循 TDD：先写测试 → 验证失败 → 最小实现 → 验证通过 → 提交。

**Tech Stack:** AppKit、AVFoundation、Carbon Event HotKey

---

### Task 1: RecordingState 纯数据类型与纯函数

**Files:**
- Create: `TalkFlow/Utils/RecordingState.swift`
- Create: `TalkFlowTests/Pure/RecordingStateTests.swift`

- [ ] **Step 1: 写失败测试 — RecordingPhase 枚举与 recordingPhaseFromToggle**

```swift
// TalkFlowTests/Pure/RecordingStateTests.swift
import XCTest
@testable import TalkFlow

final class RecordingStateTests: XCTestCase {

    // MARK: - RecordingPhase

    func test_recordingPhase_idle_isDefault() {
        let phase = RecordingPhase.idle
        XCTAssertEqual(phase, .idle)
    }

    func test_recordingPhase_recording_storesStartDate() {
        let now = Date()
        let phase = RecordingPhase.recording(startedAt: now)
        if case .recording(let startedAt) = phase {
            XCTAssertEqual(startedAt.timeIntervalSinceReferenceDate,
                           now.timeIntervalSinceReferenceDate,
                           accuracy: 0.001)
        } else {
            XCTFail("Expected .recording")
        }
    }

    func test_recordingPhase_equatable() {
        let d = Date()
        XCTAssertEqual(RecordingPhase.idle, RecordingPhase.idle)
        XCTAssertEqual(RecordingPhase.recording(startedAt: d), RecordingPhase.recording(startedAt: d))
        XCTAssertNotEqual(RecordingPhase.idle, RecordingPhase.recording(startedAt: Date()))
    }

    // MARK: - recordingPhaseFromToggle

    func test_recordingPhaseFromToggle_idleToRecording() {
        let now = Date()
        let next = recordingPhaseFromToggle(.idle, now: now)
        XCTAssertEqual(next, .recording(startedAt: now))
    }

    func test_recordingPhaseFromToggle_recordingToIdle() {
        let phase = RecordingPhase.recording(startedAt: Date())
        let next = recordingPhaseFromToggle(phase, now: Date())
        XCTAssertEqual(next, .idle)
    }

    // MARK: - shouldAcceptToggle (防抖)

    func test_shouldAcceptToggle_firstPress_alwaysAccepts() {
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: nil, now: Date(), debounce: 0.5))
    }

    func test_shouldAcceptToggle_withinDebounce_rejects() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.3)
        XCTAssertFalse(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    func test_shouldAcceptToggle_outsideDebounce_accepts() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.6)
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    func test_shouldAcceptToggle_exactlyAtDebounce_accepts() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.5)
        XCTAssertTrue(shouldAcceptToggle(lastToggleTime: t0, now: t1, debounce: 0.5))
    }

    // MARK: - shouldSave

    func test_shouldSave_belowMinDuration_false() {
        XCTAssertFalse(shouldSave(duration: 0.9, minDuration: 1.0))
    }

    func test_shouldSave_exactlyMinDuration_true() {
        XCTAssertTrue(shouldSave(duration: 1.0, minDuration: 1.0))
    }

    func test_shouldSave_aboveMinDuration_true() {
        XCTAssertTrue(shouldSave(duration: 3.5, minDuration: 1.0))
    }

    // MARK: - durationFrom

    func test_durationFrom_computesInterval() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = Date(timeIntervalSinceReferenceDate: 3.5)
        XCTAssertEqual(durationFrom(startDate: start, endDate: end), 3.5, accuracy: 0.001)
    }

    // MARK: - recordingFilename

    func test_recordingFilename_containsTimestampAndIndex() {
        let date = Date(timeIntervalSinceReferenceDate: 733000000) // some fixed date
        let name = recordingFilename(from: date, index: 1)
        XCTAssertTrue(name.hasSuffix("_001.m4a"))
    }

    func test_recordingFilename_indexPadsToThreeDigits() {
        let name = recordingFilename(from: Date(), index: 42)
        XCTAssertTrue(name.contains("_042.m4a"))
    }

    // MARK: - formatDuration

    func test_formatDuration_zero() {
        XCTAssertEqual(formatDuration(0), "00:00")
    }

    func test_formatDuration_exactlyOneSecond() {
        XCTAssertEqual(formatDuration(1.0), "00:01")
    }

    func test_formatDuration_minuteWithSeconds() {
        XCTAssertEqual(formatDuration(125.0), "02:05")
    }

    func test_formatDuration_roundingDown() {
        XCTAssertEqual(formatDuration(5.9), "00:05")
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
make test
```
预期：编译失败 — `RecordingPhase`、`recordingPhaseFromToggle` 等类型/函数未定义。

- [ ] **Step 3: 实现最小代码使测试通过**

```swift
// TalkFlow/Utils/RecordingState.swift

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
    guard let last = lastToggleTime else { return true }
    return now.timeIntervalSince(last) >= debounce
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
```

- [ ] **Step 4: 运行测试验证通过**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/RecordingState.swift TalkFlowTests/Pure/RecordingStateTests.swift
git commit -m "feat: RecordingState 纯数据类型 + 状态机 + 判定函数"
```

---

### Task 2: FilePathIO 协议与实现

**Files:**
- Create: `TalkFlow/IO/FilePathIO.swift`
- Create: `TalkFlowTests/Mocks/MockFilePathIO.swift`

- [ ] **Step 1: 写 Mock + 协议编译验证（无独立单元测试，纯集成用）**

```swift
// TalkFlow/IO/FilePathIO.swift

import Foundation

// MARK: - 协议

protocol FilePathIO {
    /// 录音文件存储目标目录
    var recordingsDirectory: URL { get }
    /// 生成下一个可用的录音文件 URL（自动递增序号防冲突）
    func nextRecordingURL() -> URL
}

// MARK: - 实现

/// 使用 ~/Library/Application Support/TalkFlow/Recordings/
final class AppSupportFilePathIO: FilePathIO {

    private let appName = "TalkFlow"
    private let folderName = "Recordings"

    var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent(appName)
            .appendingPathComponent(folderName)
    }

    func nextRecordingURL() -> URL {
        let dir = recordingsDirectory

        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        // 扫描已有文件，找最大序号
        let existing: [String]
        do {
            existing = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        } catch {
            existing = []
        }

        let pattern = try? NSRegularExpression(pattern: #"_(\d{3})\.m4a$"#)
        let maxIndex = existing.reduce(0) { acc, name in
            guard let regex = pattern,
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name),
                  let idx = Int(name[range])
            else { return acc }
            return max(acc, idx)
        }

        let nextIndex = maxIndex + 1
        let now = Date()
        let filename = recordingFilename(from: now, index: nextIndex)
        return dir.appendingPathComponent(filename)
    }
}
```

```swift
// TalkFlowTests/Mocks/MockFilePathIO.swift

import Foundation
@testable import TalkFlow

final class MockFilePathIO: FilePathIO {

    var stubbedDirectory: URL = URL(fileURLWithPath: "/tmp/TalkFlowTest/Recordings")
    var stubbedNextURL: URL = URL(fileURLWithPath: "/tmp/TalkFlowTest/Recordings/test_001.m4a")
    var nextRecordingURLCallCount = 0

    var recordingsDirectory: URL {
        stubbedDirectory
    }

    func nextRecordingURL() -> URL {
        nextRecordingURLCallCount += 1
        return stubbedNextURL
    }
}
```

- [ ] **Step 2: 运行测试验证编译通过**

```bash
make test
```
预期：全部 PASS（新代码无独立单元测试，但已有测试不退化）。

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/IO/FilePathIO.swift TalkFlowTests/Mocks/MockFilePathIO.swift
git commit -m "feat: FilePathIO 协议 + AppSupport 实现 + Mock"
```

---

### Task 3: AudioRecorderIO 协议与实现

**Files:**
- Create: `TalkFlow/IO/AudioRecorderIO.swift`
- Create: `TalkFlowTests/Mocks/MockAudioRecorderIO.swift`
- Create: `TalkFlowTests/IO/AudioRecorderIOTests.swift`

- [ ] **Step 1: 写 Mock + 协议编译**

```swift
// TalkFlow/IO/AudioRecorderIO.swift

import Foundation
import AVFoundation

// MARK: - 协议

protocol AudioRecorderIO {
    /// 是否正在录音
    var isRecording: Bool { get }
    /// 开始录音到目标 URL
    func startRecording(to url: URL) throws
    /// 停止录音 → 返回录音时长（秒）
    func stopRecording() -> TimeInterval
    /// 取消录音（不保存文件）
    func cancelRecording()
}

// MARK: - 实现

final class AVAudioRecorderIO: NSObject, AudioRecorderIO {

    private var recorder: AVAudioRecorder?
    private var recordingStartDate: Date?
    private var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    func startRecording(to url: URL) throws {
        // 先停止任何进行中的录音
        if recorder?.isRecording == true {
            recorder?.stop()
        }

        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.delegate = self
        let started = rec.record()
        guard started else {
            throw RecordingError.couldNotStart
        }
        recorder = rec
        recordingStartDate = Date()
    }

    func stopRecording() -> TimeInterval {
        guard let rec = recorder, let start = recordingStartDate else {
            return 0
        }
        rec.stop()
        recorder = nil
        recordingStartDate = nil
        recordingURL = nil
        return durationFrom(startDate: start, endDate: Date())
    }

    func cancelRecording() {
        guard let rec = recorder else { return }
        rec.stop()

        // 删除已写入的临时文件
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recorder = nil
        recordingStartDate = nil
        recordingURL = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension AVAudioRecorderIO: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            recordingStartDate = nil
            self.recorder = nil
        }
    }
}

// MARK: - 错误类型

enum RecordingError: Error, Equatable {
    case couldNotStart
}
```

```swift
// TalkFlowTests/Mocks/MockAudioRecorderIO.swift

import Foundation
@testable import TalkFlow

final class MockAudioRecorderIO: AudioRecorderIO {

    var isRecording: Bool = false

    var startRecordingCallCount = 0
    var startRecordingLastURL: URL?
    var stubbedStartError: RecordingError?

    var stopRecordingCallCount = 0
    var stubbedDuration: TimeInterval = 3.0

    var cancelRecordingCallCount = 0

    func startRecording(to url: URL) throws {
        startRecordingCallCount += 1
        startRecordingLastURL = url
        if let error = stubbedStartError {
            throw error
        }
        isRecording = true
    }

    func stopRecording() -> TimeInterval {
        stopRecordingCallCount += 1
        isRecording = false
        return stubbedDuration
    }

    func cancelRecording() {
        cancelRecordingCallCount += 1
        isRecording = false
    }
}
```

```swift
// TalkFlowTests/IO/AudioRecorderIOTests.swift

import XCTest
@testable import TalkFlow

final class AudioRecorderIOTests: XCTestCase {

    func test_mockAudioRecorder_startsAndStops() throws {
        let mock = MockAudioRecorderIO()
        let url = URL(fileURLWithPath: "/tmp/test.m4a")

        XCTAssertFalse(mock.isRecording)
        try mock.startRecording(to: url)
        XCTAssertTrue(mock.isRecording)
        XCTAssertEqual(mock.startRecordingCallCount, 1)
        XCTAssertEqual(mock.startRecordingLastURL, url)

        let dur = mock.stopRecording()
        XCTAssertFalse(mock.isRecording)
        XCTAssertEqual(mock.stopRecordingCallCount, 1)
        XCTAssertEqual(dur, 3.0)
    }

    func test_mockAudioRecorder_cancel() throws {
        let mock = MockAudioRecorderIO()
        try mock.startRecording(to: URL(fileURLWithPath: "/tmp/test.m4a"))

        mock.cancelRecording()
        XCTAssertFalse(mock.isRecording)
        XCTAssertEqual(mock.cancelRecordingCallCount, 1)
    }

    func test_mockAudioRecorder_startError() {
        let mock = MockAudioRecorderIO()
        mock.stubbedStartError = .couldNotStart

        XCTAssertThrowsError(try mock.startRecording(to: URL(fileURLWithPath: "/tmp/test.m4a"))) { error in
            XCTAssertEqual(error as? RecordingError, .couldNotStart)
        }
        XCTAssertFalse(mock.isRecording)
    }
}
```

- [ ] **Step 2: 运行测试验证通过**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/IO/AudioRecorderIO.swift TalkFlowTests/Mocks/MockAudioRecorderIO.swift TalkFlowTests/IO/AudioRecorderIOTests.swift
git commit -m "feat: AudioRecorderIO 协议 + AVAudioRecorder 实现 + Mock"
```

---

### Task 4: HotkeyIO 扩展 — ESC 临时热键

**Files:**
- Modify: `TalkFlow/IO/HotkeyIO.swift`

- [ ] **Step 1: 理解现有实现**

已有 `CarbonHotkeyIO` 使用 `hotkeyID.id = 1` 注册主热键。ESC 键码 = `0x35`，修饰键为空。需要新增 `hotkeyID.id = 2` 用于 ESC。

- [ ] **Step 2: 修改协议与实现**

在 `HotkeyIO` 协议末尾（`stopRecording()` 之后）增加两个方法：

```swift
// TalkFlow/IO/HotkeyIO.swift — 在协议定义末尾 // MARK: - 录制 之后增加

    // MARK: - 临时热键（ESC 取消录音等场景）

    /// ⚠️ 注册临时 ESC 热键
    func registerEscHotkey(onTrigger: @escaping () -> Void)

    /// ⚠️ 注销 ESC 热键
    func unregisterEscHotkey()
```

在 `CarbonHotkeyIO` 实现中增加：

```swift
// 在类成员变量区域（hotkeyID 下方）增加

    // ESC 临时热键
    private var escHotkeyRef: EventHotKeyRef?
    private var escOnTrigger: (() -> Void)?
    private let escHotkeyID = EventHotKeyID(signature: 0x54464C4F, id: 2) // "TFLO"

// 在 // MARK: - 录制 之后增加

    // MARK: - 临时热键（ESC）

    func registerEscHotkey(onTrigger: @escaping () -> Void) {
        unregisterEscHotkey()
        escOnTrigger = onTrigger

        // ESC 键码 0x35，无修饰键
        let modifiers: UInt32 = 0
        let keyCode: UInt32 = 0x35

        hotkeyLog("注册临时 ESC 热键...")

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            escHotkeyID,
            GetEventMonitorTarget(),
            0,
            &ref
        )
        if status != noErr {
            hotkeyLog("❌ 注册 ESC 热键失败 (OSStatus: \(status))")
            return
        }
        escHotkeyRef = ref
        hotkeyLog("✅ ESC 热键注册成功")
    }

    func unregisterEscHotkey() {
        if let ref = escHotkeyRef {
            UnregisterEventHotKey(ref)
            escHotkeyRef = nil
            hotkeyLog("注销 ESC 热键")
        }
        escOnTrigger = nil
    }
```

现有 Carbon 回调 `eventHandlerCallback` 需要同时处理 ESC 热键。修改该回调逻辑：

```swift
// 替换 private static let eventHandlerCallback 为：

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let userData = userData else { return noErr }

        // 从事件中提取热键 ID
        var hotkeyID = EventHotKeyID(signature: 0, id: 0)
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard err == noErr else { return noErr }

        let io = Unmanaged<CarbonHotkeyIO>.fromOpaque(userData).takeUnretainedValue()

        if hotkeyID.id == 1 {
            hotkeyLog("🔥 全局快捷键触发！")
            NotificationCenter.default.post(name: .talkFlowHotkeyTriggered, object: nil)
        } else if hotkeyID.id == 2 {
            hotkeyLog("🔥 ESC 热键触发！")
            io.escOnTrigger?()
        }

        return noErr
    }
```

- [ ] **Step 3: 运行测试确保已有测试不退化**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/IO/HotkeyIO.swift
git commit -m "feat: HotkeyIO 增加 ESC 临时热键注册/注销"
```

---

### Task 5: RecordingStatusView 浮动状态窗

**Files:**
- Create: `TalkFlow/Views/RecordingStatusView.swift`

- [ ] **Step 1: 实现视图（纯 UI，无独立单元测试）**

```swift
// TalkFlow/Views/RecordingStatusView.swift

import AppKit

/// 录音中浮动状态窗 — 显示录制时长
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class RecordingStatusView: NSView {

    // MARK: - Subviews

    private let indicatorLabel = NSTextField(labelWithString: "🔴")
    private let timeLabel = NSTextField(labelWithString: "00:00")

    // MARK: - 构造

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp() {
        impureSetupUI()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        indicatorLabel.font = NSFont.systemFont(ofSize: 14)
        indicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicatorLabel)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        let hintLabel = NSTextField(labelWithString: "ESC 取消")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            indicatorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            indicatorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.leadingAnchor.constraint(equalTo: indicatorLabel.trailingAnchor, constant: 6),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: - 公开更新方法

    /// 更新显示的录音时长
    func updateDuration(_ duration: TimeInterval) {
        timeLabel.stringValue = formatDuration(duration)
    }
}

// MARK: - 浮动窗口

/// 管理录音状态浮动窗口的生命周期
final class RecordingStatusWindow {

    private var window: NSWindow?
    private var statusView: RecordingStatusView?
    private var timer: Timer?

    // MARK: - ⚠️ 显示

    func show() {
        dismiss()

        let view = RecordingStatusView()
        view.setUp()
        statusView = view

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = view
        panel.center()

        window = panel
        panel.orderFront(nil)

        // 定时更新时长
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak view] _ in
            let elapsed = Date().timeIntervalSince(startTime)
            view?.updateDuration(elapsed)
        }
    }

    // MARK: - ⚠️ 消失

    func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
        statusView = nil
    }
}
```

- [ ] **Step 2: 运行测试确保编译通过**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/Views/RecordingStatusView.swift
git commit -m "feat: RecordingStatusView 浮动状态窗"
```

---

### Task 6: AppDelegate 协调集成

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 在 AppDelegate 中集成录音协调逻辑**

在现有 `AppDelegate` 中增加录音模块的依赖和协调逻辑。修改点：

```swift
// AppDelegate 增加成员变量
    // 录音模块
    private let audioRecorder: AudioRecorderIO = AVAudioRecorderIO()
    private let filePathIO: FilePathIO = AppSupportFilePathIO()
    private let statusWindow = RecordingStatusWindow()
    private var recordingPhase: RecordingPhase = .idle
    private var lastToggleTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private let minRecordingDuration: TimeInterval = 1.0
```

在 `applicationDidFinishLaunching` 末尾增加热键触发监听：

```swift
// 监听主快捷键触发
NotificationCenter.default.addObserver(
    self,
    selector: #selector(impureHandleHotkeyTrigger),
    name: .talkFlowHotkeyTriggered,
    object: nil
)
```

新增方法：

```swift
// MARK: - ⚠️ 录音协调

    @objc private func impureHandleHotkeyTrigger() {
        let now = Date()

        // 防抖检查
        guard shouldAcceptToggle(lastToggleTime: lastToggleTime, now: now, debounce: debounceInterval) else {
            return
        }
        lastToggleTime = now

        // 状态转换
        let nextPhase = recordingPhaseFromToggle(recordingPhase, now: now)
        recordingPhase = nextPhase

        switch nextPhase {
        case .idle:
            impureStopRecording()
        case .recording:
            impureStartRecording()
        }
    }

    private func impureStartRecording() {
        let url = filePathIO.nextRecordingURL()
        do {
            try audioRecorder.startRecording(to: url)
            statusWindow.show()
            // 注册 ESC 取消
            if let hotkeyIO = self.hotkeyIO {
                hotkeyIO.registerEscHotkey { [weak self] in
                    self?.impureCancelRecording()
                }
            }
        } catch {
            recordingPhase = .idle
        }
    }

    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        statusWindow.dismiss()

        // 注销 ESC
        hotkeyIO?.unregisterEscHotkey()

        if shouldSave(duration: duration, minDuration: minRecordingDuration) {
            let url = filePathIO.nextRecordingURL() // 已经在 start 时用过了，实际应拿回 start 时的 url

            // 注意：stopRecording 返回时长但丢失了 URL。
            // 需要在 AudioRecorderIO 协议中增加 currentURL 属性或修改返回值
        }
    }

    private func impureCancelRecording() {
        audioRecorder.cancelRecording()
        statusWindow.dismiss()
        hotkeyIO?.unregisterEscHotkey()
        recordingPhase = .idle
    }
```

**问题发现：** `stopRecording()` 返回时长但不返回 URL。需要调整 `AudioRecorderIO` 协议。

- [ ] **Step 2: 调整 AudioRecorderIO 协议增加 recordingURL 属性**

修改 `TalkFlow/IO/AudioRecorderIO.swift`：

```swift
// 在 AudioRecorderIO 协议中增加：
    /// 当前录音目标 URL（停止后可获取保存位置）
    var recordingURL: URL? { get }
```

在 `AVAudioRecorderIO` 实现中，去掉 `private` 修饰 `var recordingURL: URL?`，改为计算属性：

```swift
    var recordingURL: URL? {
        _recordingURL
    }
    private var _recordingURL: URL?
```

在 `startRecording` 中赋值 `_recordingURL = url`，在 `cancelRecording` 中清空 `_recordingURL = nil`。

在 `MockAudioRecorderIO` 中增加：

```swift
    var recordingURL: URL?
```

- [ ] **Step 3: 完成 AppDelegate 协调逻辑**

现在 `impureStopRecording` 完整实现：

```swift
    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        let savedURL = audioRecorder.recordingURL
        statusWindow.dismiss()
        hotkeyIO?.unregisterEscHotkey()

        if shouldSave(duration: duration, minDuration: minRecordingDuration),
           let url = savedURL {
            onRecordingComplete?(url)
        } else {
            // 删除过短录音或无效录音的文件
            if let url = savedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
```

AppDelegate 增加回调属性：

```swift
    /// 录音完成回调 — 供后续工作流（语音转写）接入
    var onRecordingComplete: ((URL) -> Void)?
```

- [ ] **Step 4: 处理成员变量访问 — hotkeyIO 引用**

AppDelegate 当前在 `impureShowMainWindow` 中创建局部 `let hotkeyIO = CarbonHotkeyIO()`，无法在其他方法中引用。需要改为成员变量：

```swift
    private var hotkeyIO: HotkeyIO?
```

在 `impureShowMainWindow` 中赋值：

```swift
    let hotkeyIO = CarbonHotkeyIO()
    self.hotkeyIO = hotkeyIO
```

- [ ] **Step 5: 运行测试验证编译和已有测试不退化**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add TalkFlow/AppDelegate.swift TalkFlow/IO/AudioRecorderIO.swift TalkFlowTests/Mocks/MockAudioRecorderIO.swift
git commit -m "feat: AppDelegate 集成录音协调逻辑 + AudioRecorderIO 增加 recordingURL"
```

---

### Task 7: 菜单栏图标录制状态联动

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 增加图标状态切换方法**

```swift
// 在 AppDelegate 中增加

    private func impureUpdateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = isRecording ? "mic.circle.fill" : "mic.fill"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRecording ? "TalkFlow (录制中)" : "TalkFlow"
        )
        button.image?.size = NSSize(width: 18, height: 18)
    }
```

在 `impureStartRecording` 中调用 `impureUpdateMenuBarIcon(isRecording: true)`，
在 `impureStopRecording` 和 `impureCancelRecording` 中调用 `impureUpdateMenuBarIcon(isRecording: false)`。

- [ ] **Step 2: 运行测试**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: 菜单栏图标录制状态联动"
```

---

### Task 8: 最终验证与清理

- [ ] **Step 1: 运行全量测试**

```bash
make test
```
预期：全部 PASS。

- [ ] **Step 2: 确认 Xcode 项目文件包含所有新文件**

检查 `TalkFlow.xcodeproj/project.pbxproj` 是否需要在 Xcode 中手动添加新文件到 target。

需要添加到 **TalkFlow** target：
- `Utils/RecordingState.swift`
- `IO/AudioRecorderIO.swift`
- `IO/FilePathIO.swift`
- `Views/RecordingStatusView.swift`

需要添加到 **TalkFlowTests** target：
- `Pure/RecordingStateTests.swift`
- `Mocks/MockAudioRecorderIO.swift`
- `Mocks/MockFilePathIO.swift`
- `IO/AudioRecorderIOTests.swift`

若需手动添加，在 Xcode 中操作后提交。

- [ ] **Step 3: 提交**

```bash
git add TalkFlow.xcodeproj/project.pbxproj  # 如已修改
git commit -m "chore: 将录音模块新文件加入 Xcode target"
```
