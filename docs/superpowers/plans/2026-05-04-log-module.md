# 日志模块 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TalkFlow 增加结构化日志写入（JSON Lines + 双文件滚动）、日志查看器 UI、启动时清理 14 天前日志和录音。

**Architecture:** 纯数据模型 LogEntry 在 Utils 层；文件 IO（写入/滚动/清理/读取）在 IO 层，LoggerIO 协议封装日志调用；Views 层新增 LogCardView + LogViewerWindow 含左右分栏查看器；AppDelegate 持有 Logger 并替换 print()，启动时调清理。

**Tech Stack:** Swift, AppKit, Codable (JSONEncoder), FileManager, NSTableView, NSWindow

---

## 文件结构

```
新增:
  TalkFlow/Utils/LogEntry.swift
  TalkFlow/IO/LogFileIO.swift
  TalkFlow/IO/LoggerIO.swift
  TalkFlow/Views/LogCardView.swift
  TalkFlow/Views/LogViewerWindow.swift
  TalkFlow/Views/LogEntryListView.swift
  TalkFlow/Views/LogEntryDetailView.swift
测试:
  TalkFlowTests/Pure/LogEntryTests.swift
  TalkFlowTests/IO/LogFileIOTests.swift
  TalkFlowTests/IO/LoggerIOTests.swift
修改:
  TalkFlow/IO/FilePathIO.swift (新增 cleanOldRecordings 纯函数)
  TalkFlow/AppDelegate.swift (持有 logger, 替换 print(), 清理, LogCardView)
```

---

### Task 1: LogEntry 纯数据模型

**Files:**
- Create: `TalkFlow/Utils/LogEntry.swift`
- Create: `TalkFlowTests/Pure/LogEntryTests.swift`

- [ ] **Step 1: 写 LogEntry**

```swift
// TalkFlow/Utils/LogEntry.swift
import Foundation

enum LogLevel: String, Codable, CaseIterable {
    case debug, info, warning, error
}

struct LogEntry: Codable, Equatable {
    let timestamp: Date
    let level: LogLevel
    let tag: String
    let message: String
}
```

- [ ] **Step 2: 写 LogEntry 测试**

```swift
// TalkFlowTests/Pure/LogEntryTests.swift
import XCTest
@testable import TalkFlow

final class LogEntryTests: XCTestCase {

    func test_logLevel_allCases() {
        XCTAssertEqual(LogLevel.allCases.count, 4)
        XCTAssertTrue(LogLevel.allCases.contains(.debug))
        XCTAssertTrue(LogLevel.allCases.contains(.info))
        XCTAssertTrue(LogLevel.allCases.contains(.warning))
        XCTAssertTrue(LogLevel.allCases.contains(.error))
    }

    func test_logEntry_equatable() {
        let now = Date()
        let a = LogEntry(timestamp: now, level: .info, tag: "Test", message: "hello")
        let b = LogEntry(timestamp: now, level: .info, tag: "Test", message: "hello")
        XCTAssertEqual(a, b)
    }

    func test_logEntry_notEqual_differentMessage() {
        let now = Date()
        let a = LogEntry(timestamp: now, level: .info, tag: "Test", message: "hello")
        let b = LogEntry(timestamp: now, level: .info, tag: "Test", message: "world")
        XCTAssertNotEqual(a, b)
    }

    func test_logEntry_notEqual_differentLevel() {
        let now = Date()
        let a = LogEntry(timestamp: now, level: .info, tag: "Test", message: "hello")
        let b = LogEntry(timestamp: now, level: .error, tag: "Test", message: "hello")
        XCTAssertNotEqual(a, b)
    }

    func test_codable_roundTrip() throws {
        let now = Date()
        let entry = LogEntry(timestamp: now, level: .warning, tag: "Pipeline", message: "润色失败")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)
        XCTAssertEqual(decoded.timestamp.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)
        XCTAssertEqual(decoded.level, .warning)
        XCTAssertEqual(decoded.tag, "Pipeline")
        XCTAssertEqual(decoded.message, "润色失败")
    }

    func test_logLevel_rawValue() {
        XCTAssertEqual(LogLevel.debug.rawValue, "debug")
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warning.rawValue, "warning")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
    }

    func test_logLevel_initFromRawValue() {
        XCTAssertEqual(LogLevel(rawValue: "info"), .info)
        XCTAssertEqual(LogLevel(rawValue: "error"), .error)
        XCTAssertNil(LogLevel(rawValue: "critical"))
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/LogEntryTests 2>&1 | tail -5
```
预期：`** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/Utils/LogEntry.swift TalkFlowTests/Pure/LogEntryTests.swift
git commit -m "feat: add LogEntry data model with tests"
```

---

### Task 2: LogFileIO — 文件 IO 协议与实现

**Files:**
- Create: `TalkFlow/IO/LogFileIO.swift`
- Create: `TalkFlowTests/IO/LogFileIOTests.swift`

- [ ] **Step 1: 写 LogFileIO 协议和实现**

```swift
// TalkFlow/IO/LogFileIO.swift
import Foundation

// MARK: - 协议

protocol LogFileIO {
    var logsDirectory: URL { get }
    func append(_ entry: LogEntry)
    func entries(from file: URL) -> [LogEntry]
    func logFiles() -> [URL]
    func rotateIfNeeded()
    func cleanOldLogs(before days: Int)
}

// MARK: - 实现

final class DefaultLogFileIO: LogFileIO {

    private let queue = DispatchQueue(label: "com.talkflow.logfile", qos: .utility)
    private let encoder = JSONEncoder()
    private let fileManager: FileManager
    private let calendar: Calendar
    private var currentDate: String // "yyyy-MM-dd"

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.currentDate = dayString(from: Date(), calendar: calendar)
    }

    var logsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TalkFlow")
            .appendingPathComponent("Logs")
    }

    func append(_ entry: LogEntry) {
        queue.sync {
            rotateIfNeeded()
            ensureDirectoryExists()
            let fileURL = logsDirectory.appendingPathComponent("latest.log")
            guard let data = try? encoder.encode(entry),
                  let handle = try? FileHandle(forWritingTo: fileURL) else {
                // 文件不存在则创建
                let line = (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            handle.seekToEndOfFile()
            var line = data
            line.append(0x0A) // \n
            handle.write(line)
            try? handle.close()
        }
    }

    func rotateIfNeeded() {
        let today = dayString(from: Date(), calendar: calendar)
        guard today != currentDate else { return }

        let latestURL = logsDirectory.appendingPathComponent("latest.log")
        let archiveURL = logsDirectory.appendingPathComponent("\(currentDate).log")

        if fileManager.fileExists(atPath: latestURL.path) {
            try? fileManager.moveItem(at: latestURL, to: archiveURL)
        }

        currentDate = today
    }

    func entries(from file: URL) -> [LogEntry] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: data)
            }
    }

    func logFiles() -> [URL] {
        ensureDirectoryExists()
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let latest = files.filter { $0.lastPathComponent == "latest.log" }
        let archives = files
            .filter { $0.lastPathComponent.hasSuffix(".log") && $0.lastPathComponent != "latest.log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // 日期降序

        return latest + archives
    }

    func cleanOldLogs(before days: Int) {
        ensureDirectoryExists()
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let files = logFiles().filter { $0.lastPathComponent != "latest.log" }

        for file in files {
            guard let date = logDate(from: file.lastPathComponent, calendar: calendar) else { continue }
            if date < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - 私有

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - 纯函数

/// 从日志文件名提取日期（"2026-05-04.log" → Date）
func logDate(from filename: String, calendar: Calendar = .current) -> Date? {
    guard filename.hasSuffix(".log") else { return nil }
    let stem = String(filename.dropLast(4)) // 去掉 ".log"
    let parts = stem.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]) else { return nil }
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    return calendar.date(from: comps)
}

/// 当天日期字符串（"yyyy-MM-dd"）
func dayString(from date: Date, calendar: Calendar = .current) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
}
```

- [ ] **Step 2: 写 LogFileIO 测试**

```swift
// TalkFlowTests/IO/LogFileIOTests.swift
import XCTest
@testable import TalkFlow

final class LogFileIOTests: XCTestCase {

    // MARK: - 纯函数

    func test_logDate_validFilename() {
        let date = logDate(from: "2026-05-04.log")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 4)
    }

    func test_logDate_invalidFilename_returnsNil() {
        XCTAssertNil(logDate(from: "latest.log"))
        XCTAssertNil(logDate(from: "not-a-date.log"))
        XCTAssertNil(logDate(from: "abc.txt"))
    }

    func test_dayString_format() {
        let comps = DateComponents(year: 2026, month: 5, day: 4)
        let date = Calendar.current.date(from: comps)!
        XCTAssertEqual(dayString(from: date), "2026-05-04")
    }

    // MARK: - LogFileIO 集成测试（用临时目录）

    func test_append_and_entries_roundTrip() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 注入自定义目录的实现
        let io = TestLogFileIO(directory: tmpDir)
        let entry = LogEntry(timestamp: Date(), level: .info, tag: "Test", message: "hello")

        io.append(entry)
        let files = io.logFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].lastPathComponent, "latest.log")

        let entries = io.entries(from: files[0])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].tag, "Test")
        XCTAssertEqual(entries[0].message, "hello")
        XCTAssertEqual(entries[0].level, .info)
    }

    func test_append_multipleEntries() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let io = TestLogFileIO(directory: tmpDir)
        io.append(LogEntry(timestamp: Date(), level: .debug, tag: "A", message: "m1"))
        io.append(LogEntry(timestamp: Date(), level: .info, tag: "B", message: "m2"))
        io.append(LogEntry(timestamp: Date(), level: .error, tag: "C", message: "m3"))

        let entries = io.entries(from: io.logFiles()[0])
        XCTAssertEqual(entries.count, 3)
    }

    func test_rotate_renamesLatestToDateFile() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 用昨天的日期构造 io，使其 rotate 到"昨天"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStr = dayString(from: yesterday)

        let io = TestLogFileIO(directory: tmpDir, initialDate: yesterdayStr)
        io.append(LogEntry(timestamp: yesterday, level: .info, tag: "T", message: "old"))

        // 强制 rotate（模拟跨天）
        io.forceRotate(to: dayString(from: Date()))

        let files = io.logFiles()
        // 应该有 latest.log（空）和 yesterdayStr.log
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "\(yesterdayStr).log" })
        XCTAssertTrue(files.contains { $0.lastPathComponent == "latest.log" })

        // 归档文件包含旧条目
        let archive = files.first { $0.lastPathComponent != "latest.log" }!
        let archivedEntries = io.entries(from: archive)
        XCTAssertEqual(archivedEntries.count, 1)
        XCTAssertEqual(archivedEntries[0].message, "old")
    }

    func test_cleanOldLogs_removesOldFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 创建 15 天前的日志文件
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let oldFile = tmpDir.appendingPathComponent("\(dayString(from: oldDate)).log")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try? "test".write(to: oldFile, atomically: true, encoding: .utf8)

        // 创建今天的 latest.log
        let latestFile = tmpDir.appendingPathComponent("latest.log")
        try? "latest".write(to: latestFile, atomically: true, encoding: .utf8)

        let io = TestLogFileIO(directory: tmpDir)
        io.cleanOldLogs(before: 14)

        let remaining = io.logFiles()
        // latest.log 保留，旧文件删除
        XCTAssertFalse(remaining.contains { $0.lastPathComponent == oldFile.lastPathComponent })
        XCTAssertTrue(remaining.contains { $0.lastPathComponent == "latest.log" })
    }

    func test_logFiles_sortedDescending() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try? "".write(to: tmpDir.appendingPathComponent("latest.log"), atomically: true, encoding: .utf8)
        try? "".write(to: tmpDir.appendingPathComponent("2026-05-03.log"), atomically: true, encoding: .utf8)
        try? "".write(to: tmpDir.appendingPathComponent("2026-05-04.log"), atomically: true, encoding: .utf8)

        let io = TestLogFileIO(directory: tmpDir)
        let files = io.logFiles()

        // latest.log 在最前
        XCTAssertEqual(files[0].lastPathComponent, "latest.log")
        // 之后按日期降序：05-04 在 05-03 之前
        XCTAssertEqual(files[1].lastPathComponent, "2026-05-04.log")
        XCTAssertEqual(files[2].lastPathComponent, "2026-05-03.log")
    }
}

// MARK: - 测试专用实现（注入目录以绕过真实 AppSupport）

final class TestLogFileIO: LogFileIO {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.talkflow.test.logfile")
    private let encoder = JSONEncoder()
    private let calendar: Calendar
    private var currentDate: String
    private let fileManager: FileManager

    init(directory: URL, initialDate: String? = nil, calendar: Calendar = .current, fileManager: FileManager = .default) {
        self.directory = directory
        self.calendar = calendar
        self.fileManager = fileManager
        self.currentDate = initialDate ?? dayString(from: Date(), calendar: calendar)
    }

    var logsDirectory: URL { directory }

    func append(_ entry: LogEntry) {
        queue.sync {
            ensureDirectoryExists()
            let url = directory.appendingPathComponent("latest.log")
            guard let data = try? encoder.encode(entry) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                var line = data
                line.append(0x0A)
                handle.write(line)
                try? handle.close()
            } else {
                let line = (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func entries(from file: URL) -> [LogEntry] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: data)
            }
    }

    func logFiles() -> [URL] {
        ensureDirectoryExists()
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let latest = files.filter { $0.lastPathComponent == "latest.log" }
        let archives = files
            .filter { $0.lastPathComponent.hasSuffix(".log") && $0.lastPathComponent != "latest.log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        return latest + archives
    }

    func rotateIfNeeded() {
        // no-op for test — 由 forceRotate 替代
    }

    func forceRotate(to newDate: String) {
        let latestURL = directory.appendingPathComponent("latest.log")
        let archiveURL = directory.appendingPathComponent("\(currentDate).log")
        if fileManager.fileExists(atPath: latestURL.path) {
            try? fileManager.moveItem(at: latestURL, to: archiveURL)
        }
        currentDate = newDate
    }

    func cleanOldLogs(before days: Int) {
        ensureDirectoryExists()
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let files = logFiles().filter { $0.lastPathComponent != "latest.log" }
        for file in files {
            guard let date = logDate(from: file.lastPathComponent, calendar: calendar) else { continue }
            if date < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/LogFileIOTests 2>&1 | tail -5
```
预期：`** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/IO/LogFileIO.swift TalkFlowTests/IO/LogFileIOTests.swift
git commit -m "feat: add LogFileIO with dual-file rolling and cleanup"
```

---

### Task 3: LoggerIO — 日志写入协议

**Files:**
- Create: `TalkFlow/IO/LoggerIO.swift`
- Create: `TalkFlowTests/IO/LoggerIOTests.swift`

- [ ] **Step 1: 写 LoggerIO 协议和实现**

```swift
// TalkFlow/IO/LoggerIO.swift
import Foundation

// MARK: - 协议

protocol LoggerIO {
    func log(_ level: LogLevel, tag: String, _ message: String)
}

extension LoggerIO {
    func debug(tag: String, _ message: String) { log(.debug, tag: tag, message) }
    func info(tag: String, _ message: String)  { log(.info, tag: tag, message) }
    func warning(tag: String, _ message: String) { log(.warning, tag: tag, message) }
    func error(tag: String, _ message: String)  { log(.error, tag: tag, message) }
}

// MARK: - 实现

final class FileLoggerIO: LoggerIO {
    private let fileIO: LogFileIO

    init(fileIO: LogFileIO) {
        self.fileIO = fileIO
    }

    func log(_ level: LogLevel, tag: String, _ message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            tag: tag,
            message: message
        )
        fileIO.append(entry)
    }
}

// MARK: - 工厂函数

func impureMakeLogger() -> LoggerIO {
    FileLoggerIO(fileIO: DefaultLogFileIO())
}
```

- [ ] **Step 2: 写 LoggerIO 测试**

```swift
// TalkFlowTests/IO/LoggerIOTests.swift
import XCTest
@testable import TalkFlow

final class LoggerIOTests: XCTestCase {

    func test_fileLogger_info_createsCorrectEntry() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileIO = TestLogFileIO(directory: tmpDir)
        let logger = FileLoggerIO(fileIO: fileIO)

        logger.info(tag: "Test", "hello world")

        let entries = fileIO.entries(from: fileIO.logFiles()[0])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].level, .info)
        XCTAssertEqual(entries[0].tag, "Test")
        XCTAssertEqual(entries[0].message, "hello world")
    }

    func test_convenienceMethods() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileIO = TestLogFileIO(directory: tmpDir)
        let logger = FileLoggerIO(fileIO: fileIO)

        logger.debug(tag: "A", "d")
        logger.info(tag: "B", "i")
        logger.warning(tag: "C", "w")
        logger.error(tag: "D", "e")

        let entries = fileIO.entries(from: fileIO.logFiles()[0])
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].level, .debug)
        XCTAssertEqual(entries[1].level, .info)
        XCTAssertEqual(entries[2].level, .warning)
        XCTAssertEqual(entries[3].level, .error)
    }

    func test_log_directMethod() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileIO = TestLogFileIO(directory: tmpDir)
        let logger = FileLoggerIO(fileIO: fileIO)

        logger.log(.error, tag: "Custom", "direct call")

        let entries = fileIO.entries(from: fileIO.logFiles()[0])
        XCTAssertEqual(entries[0].level, .error)
        XCTAssertEqual(entries[0].tag, "Custom")
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/LoggerIOTests 2>&1 | tail -5
```
预期：`** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/IO/LoggerIO.swift TalkFlowTests/IO/LoggerIOTests.swift
git commit -m "feat: add LoggerIO protocol and FileLoggerIO implementation"
```

---

### Task 4: 清理录音文件 + 日期提取纯函数

**Files:**
- Modify: `TalkFlow/IO/FilePathIO.swift`
- Modify: `TalkFlow/Utils/RecordingState.swift`（或直接在 FilePathIO 中加纯函数）
- Create: `TalkFlowTests/Pure/RecordingCleanupTests.swift`

- [ ] **Step 1: 在 FilePathIO.swift 末尾追加清理函数**

```swift
// 追加到 TalkFlow/IO/FilePathIO.swift 末尾

// MARK: - 清理纯函数

/// 从录音文件名提取日期（"yyyy-MM-dd'T'HH-mm-ss_xxx.m4a" → Date）
func recordingDate(from filename: String) -> Date? {
    // 文件名格式: "2026-05-04T16-32-01_001.m4a"
    guard let tIndex = filename.firstIndex(of: "T") else { return nil }
    let datePart = String(filename[..<tIndex]) // "2026-05-04"
    let parts = datePart.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]) else { return nil }
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    return Calendar.current.date(from: comps)
}

/// 清理 N 天前的录音文件
func cleanOldRecordings(fileIO: FilePathIO, before days: Int) {
    guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
    let dir = fileIO.recordingsDirectory
    guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }

    for filename in filenames where filename.hasSuffix(".m4a") {
        guard let date = recordingDate(from: filename), date < cutoff else { continue }
        let fileURL = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 2: 写清理测试**

```swift
// TalkFlowTests/Pure/RecordingCleanupTests.swift
import XCTest
@testable import TalkFlow

final class RecordingCleanupTests: XCTestCase {

    // MARK: - recordingDate 纯函数

    func test_recordingDate_validFilename() {
        let date = recordingDate(from: "2026-05-04T16-32-01_001.m4a")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 4)
    }

    func test_recordingDate_invalidFilename_returnsNil() {
        XCTAssertNil(recordingDate(from: "not-a-file.txt"))
        XCTAssertNil(recordingDate(from: "2026-05-04.log"))
    }

    // MARK: - cleanOldRecordings 集成测试

    func test_cleanOldRecordings_removesOldFiles_onlyM4A() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        let recordingsDir = tmpDir.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 创建 15 天前的录音文件
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let oldFilename = recordingFilenameForTest(from: oldDate, index: 1)
        let oldFile = recordingsDir.appendingPathComponent(oldFilename)
        try? "old".write(to: oldFile, atomically: true, encoding: .utf8)

        // 创建 3 天前的录音文件
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let recentFilename = recordingFilenameForTest(from: recentDate, index: 2)
        let recentFile = recordingsDir.appendingPathComponent(recentFilename)
        try? "recent".write(to: recentFile, atomically: true, encoding: .utf8)

        // 创建一个非 .m4a 文件（不应被删除）
        let otherFile = recordingsDir.appendingPathComponent("readme.txt")
        try? "keep".write(to: otherFile, atomically: true, encoding: .utf8)

        let mockFileIO = MockFilePathIOForCleanup(directory: recordingsDir)
        cleanOldRecordings(fileIO: mockFileIO, before: 14)

        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: recordingsDir.path)) ?? []
        // 旧 m4a 被删
        XCTAssertFalse(remaining.contains(oldFilename))
        // 新 m4a 保留
        XCTAssertTrue(remaining.contains(recentFilename))
        // 非 m4a 保留
        XCTAssertTrue(remaining.contains("readme.txt"))
    }
}

// 测试辅助：生成可预测的录音文件名
func recordingFilenameForTest(from date: Date, index: Int) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    fmt.timeZone = TimeZone.current
    let ts = fmt.string(from: date)
    return "\(ts)_\(String(format: "%03d", index)).m4a"
}

// 测试用 MockFilePathIO
final class MockFilePathIOForCleanup: FilePathIO {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    var recordingsDirectory: URL { directory }
    func nextRecordingURL() -> URL { directory.appendingPathComponent("mock.m4a") }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/RecordingCleanupTests 2>&1 | tail -5
```
预期：`** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add TalkFlow/IO/FilePathIO.swift TalkFlowTests/Pure/RecordingCleanupTests.swift
git commit -m "feat: add cleanup for old recordings by filename date"
```

---

### Task 5: LogCardView — 主窗体底部日志卡片

**Files:**
- Create: `TalkFlow/Views/LogCardView.swift`

- [ ] **Step 1: 写 LogCardView**

```swift
// TalkFlow/Views/LogCardView.swift
import AppKit

/// 主窗体底部日志卡片 — 复用 CardView，显示错误/警告计数 + 打开按钮
final class LogCardView: NSView {

    private let logFileIO: LogFileIO
    private var onOpen: (() -> Void)?
    private var summaryLabel: NSTextField?

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        impureSetupUI()
        refreshCounts()
    }

    // MARK: - 公开方法

    func refreshCounts() {
        let latestURL = logFileIO.logsDirectory.appendingPathComponent("latest.log")
        let entries = logFileIO.entries(from: latestURL)
        let errors = entries.filter { $0.level == .error }.count
        let warnings = entries.filter { $0.level == .warning }.count

        if errors == 0 && warnings == 0 {
            summaryLabel?.stringValue = "暂无错误"
        } else {
            var parts: [String] = []
            if errors > 0 { parts.append("\(errors) error") }
            if warnings > 0 { parts.append("\(warnings) warning") }
            summaryLabel?.stringValue = parts.joined(separator: " · ")
        }
    }

    // MARK: - ⚠️ UI

    private func impureSetupUI() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "暂无错误")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        self.summaryLabel = label

        let openButton = NSButton(title: "打开", target: self, action: #selector(impureOpenTapped))
        openButton.bezelStyle = .rounded
        openButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(openButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            openButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            openButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(equalToConstant: 28),
        ])

        let card = CardView(title: "日志", contentView: contentView)
        card.setUp()
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func impureOpenTapped() {
        onOpen?()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add TalkFlow/Views/LogCardView.swift
git commit -m "feat: add LogCardView for main window bottom card"
```

---

### Task 6: LogEntryDetailView — 右侧详情面板

**Files:**
- Create: `TalkFlow/Views/LogEntryDetailView.swift`

- [ ] **Step 1: 写 LogEntryDetailView**

```swift
// TalkFlow/Views/LogEntryDetailView.swift
import AppKit

/// 日志详情 — 显示选中条目的完整信息
final class LogEntryDetailView: NSView {

    private let levelBadge = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let messageTextView = NSTextView()
    private var placeholderLabel: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        impureSetupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 公开方法

    func show(entry: LogEntry?, sourceFile: String = "") {
        subviews.forEach { $0.isHidden = entry == nil }
        placeholderLabel?.isHidden = entry != nil

        guard let entry else { return }

        // 级别 badge
        levelBadge.stringValue = entry.level.rawValue.uppercased()
        levelBadge.textColor = colorForLevel(entry.level)
        levelBadge.font = NSFont.boldSystemFont(ofSize: 11)

        // 时间戳
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        timestampLabel.stringValue = fmt.string(from: entry.timestamp)
        timestampLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor

        // 元信息
        metaLabel.stringValue = "标签: [\(entry.tag)]  |  来源: \(sourceFile)"
        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = .tertiaryLabelColor

        // 消息体
        messageTextView.string = entry.message
    }

    // MARK: - ⚠️ UI

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // 占位文字
        let placeholder = NSTextField(labelWithString: "选择一条日志查看详情")
        placeholder.font = NSFont.systemFont(ofSize: 14)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        self.placeholderLabel = placeholder

        // 级别
        levelBadge.translatesAutoresizingMaskIntoConstraints = false
        levelBadge.isHidden = true
        addSubview(levelBadge)

        // 时间
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.isHidden = true
        addSubview(timestampLabel)

        // 元信息
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.isHidden = true
        addSubview(metaLabel)

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = true
        addSubview(separator)

        // 消息体（可滚动、可选择）
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true

        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        messageTextView.textColor = .labelColor
        messageTextView.backgroundColor = .controlBackgroundColor
        messageTextView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = messageTextView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),

            levelBadge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            levelBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            timestampLabel.topAnchor.constraint(equalTo: levelBadge.bottomAnchor, constant: 8),
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            metaLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            separator.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    private func colorForLevel(_ level: LogLevel) -> NSColor {
        switch level {
        case .debug:   return .tertiaryLabelColor
        case .info:    return .systemBlue
        case .warning: return .systemOrange
        case .error:   return .systemRed
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add TalkFlow/Views/LogEntryDetailView.swift
git commit -m "feat: add LogEntryDetailView for right-side detail panel"
```

---

### Task 7: LogEntryListView — 左侧日志列表

**Files:**
- Create: `TalkFlow/Views/LogEntryListView.swift`

- [ ] **Step 1: 写 LogEntryListView**

```swift
// TalkFlow/Views/LogEntryListView.swift
import AppKit

/// 日志列表 — 左侧：文件切换 + 级别筛选 + NSTableView + checkbox + 复制
final class LogEntryListView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    // 数据
    private var entries: [LogEntry] = []
    private var filteredEntries: [LogEntry] = []
    private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    private var checkedIndices: Set<Int> = []
    private var onSelectionChanged: ((LogEntry, String) -> Void)?
    private var logFileIO: LogFileIO
    private var currentFileName: String = "latest.log"

    // UI
    private let filePopup = NSPopUpButton()
    private let tableView = NSTableView()
    private let copyButton = NSButton()
    private let selectAllButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "共 0 条")

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
        super.init(frame: .zero)
        impureSetupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp(onSelectionChanged: @escaping (LogEntry, String) -> Void) {
        self.onSelectionChanged = onSelectionChanged
        impureRefreshFileList()
        impureLoadCurrentFile()
    }

    // MARK: - 公开

    func refresh() {
        impureLoadCurrentFile()
    }

    // MARK: - ⚠️ 数据加载

    private func impureLoadCurrentFile() {
        let url = logFileIO.logsDirectory.appendingPathComponent(currentFileName)
        entries = logFileIO.entries(from: url)
        checkedIndices = []
        impureApplyFilter()
    }

    private func impureApplyFilter() {
        filteredEntries = entries.filter { selectedLevels.contains($0.level) }
        countLabel.stringValue = "共 \(filteredEntries.count) 条"
        tableView.reloadData()
        impureUpdateCopyButton()
    }

    // MARK: - ⚠️ UI

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // 顶部工具栏
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        filePopup.target = self
        filePopup.action = #selector(impureFileChanged)
        filePopup.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(filePopup)

        // 级别筛选按钮
        let levelStack = NSStackView()
        levelStack.orientation = .horizontal
        levelStack.spacing = 4
        levelStack.translatesAutoresizingMaskIntoConstraints = false

        for level in LogLevel.allCases {
            let btn = NSButton()
            btn.title = level.rawValue.capitalized
            btn.bezelStyle = .inline
            btn.setButtonType(.toggle)
            btn.state = .on
            btn.tag = level.hashValue
            btn.target = self
            btn.action = #selector(impureLevelToggled(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false

            // 存储 level 引用
            objc_setAssociatedObject(btn, "logLevel", level, .OBJC_ASSOCIATION_RETAIN)
            levelStack.addArrangedSubview(btn)
        }
        toolbar.addSubview(levelStack)

        NSLayoutConstraint.activate([
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            filePopup.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            filePopup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            levelStack.leadingAnchor.constraint(equalTo: filePopup.trailingAnchor, constant: 12),
            levelStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])

        // TableView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        col1.title = ""
        col1.width = 24
        tableView.addTableColumn(col1)

        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("level"))
        col2.title = ""
        col2.width = 24
        tableView.addTableColumn(col2)

        let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        col3.title = "时间"
        col3.width = 65
        tableView.addTableColumn(col3)

        let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tag"))
        col4.title = "标签"
        col4.width = 80
        tableView.addTableColumn(col4)

        let col5 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        col5.title = "消息"
        col5.width = 200
        tableView.addTableColumn(col5)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = nil
        tableView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = tableView

        // 底部工具栏
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        copyButton.title = "📋 复制勾选"
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false
        copyButton.target = self
        copyButton.action = #selector(impureCopySelected)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(copyButton)

        selectAllButton.title = "☐ 全选"
        selectAllButton.bezelStyle = .inline
        selectAllButton.target = self
        selectAllButton.action = #selector(impureToggleSelectAll)
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(selectAllButton)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(countLabel)

        NSLayoutConstraint.activate([
            bottomBar.heightAnchor.constraint(equalToConstant: 32),

            copyButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 4),
            copyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            selectAllButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            selectAllButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            countLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])

        // 整体布局
        addSubview(toolbar)
        addSubview(scrollView)
        addSubview(bottomBar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bottomBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - ⚠️ Actions

    @objc private func impureFileChanged() {
        currentFileName = filePopup.titleOfSelectedItem ?? "latest.log"
        impureLoadCurrentFile()
    }

    @objc private func impureLevelToggled(_ sender: NSButton) {
        guard let level = objc_getAssociatedObject(sender, "logLevel") as? LogLevel else { return }
        if sender.state == .on {
            selectedLevels.insert(level)
        } else {
            selectedLevels.remove(level)
        }
        impureApplyFilter()
    }

    @objc private func impureCopySelected() {
        let selected = checkedIndices.sorted().compactMap { i -> LogEntry? in
            guard i < filteredEntries.count else { return nil }
            return filteredEntries[i]
        }

        let text = selected.map { entry in
            let ts = timeFormatter.string(from: entry.timestamp)
            return "[\(ts)] [\(entry.level.rawValue.uppercased())] [\(entry.tag)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func impureToggleSelectAll() {
        if checkedIndices.count == filteredEntries.count {
            checkedIndices = []
            selectAllButton.title = "☐ 全选"
        } else {
            checkedIndices = Set(0..<filteredEntries.count)
            selectAllButton.title = "☑ 取消全选"
        }
        impureUpdateCopyButton()
        tableView.reloadData()
    }

    private func impureRefreshFileList() {
        filePopup.removeAllItems()
        for file in logFileIO.logFiles() {
            filePopup.addItem(withTitle: file.lastPathComponent)
        }
        filePopup.selectItem(withTitle: "latest.log")
    }

    private func impureUpdateCopyButton() {
        let count = checkedIndices.count
        copyButton.title = count > 0 ? "📋 复制 (\(count))" : "📋 复制勾选"
        copyButton.isEnabled = count > 0
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        nil // 使用 view-based
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredEntries.count else { return nil }
        let entry = filteredEntries[row]

        switch tableColumn?.identifier.rawValue {
        case "check":
            let btn = NSButton()
            btn.setButtonType(.switch)
            btn.state = checkedIndices.contains(row) ? .on : .off
            btn.target = self
            btn.action = #selector(impureCheckToggled(_:))
            btn.tag = row
            return btn

        case "level":
            let tf = NSTextField(labelWithString: levelEmoji(entry.level))
            tf.font = NSFont.systemFont(ofSize: 11)
            return tf

        case "time":
            let tf = NSTextField(labelWithString: timeFormatter.string(from: entry.timestamp))
            tf.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            tf.textColor = .secondaryLabelColor
            return tf

        case "tag":
            let tf = NSTextField(labelWithString: "[\(entry.tag)]")
            tf.font = NSFont.systemFont(ofSize: 11)
            tf.textColor = .secondaryLabelColor
            tf.lineBreakMode = .byTruncatingTail
            return tf

        case "message":
            let tf = NSTextField(labelWithString: entry.message)
            tf.font = NSFont.systemFont(ofSize: 11)
            tf.lineBreakMode = .byTruncatingTail
            return tf

        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredEntries.count else { return }
        let entry = filteredEntries[row]
        onSelectionChanged?(entry, currentFileName)
    }

    @objc private func impureCheckToggled(_ sender: NSButton) {
        let row = sender.tag
        if sender.state == .on {
            checkedIndices.insert(row)
        } else {
            checkedIndices.remove(row)
        }
        impureUpdateCopyButton()
    }

    private func levelEmoji(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "⚪"
        case .info: return "🔵"
        case .warning: return "🟠"
        case .error: return "🔴"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add TalkFlow/Views/LogEntryListView.swift
git commit -m "feat: add LogEntryListView with checkbox selection and copy"
```

---

### Task 8: LogViewerWindow — 日志查看器窗口

**Files:**
- Create: `TalkFlow/Views/LogViewerWindow.swift`

- [ ] **Step 1: 写 LogViewerWindow**

```swift
// TalkFlow/Views/LogViewerWindow.swift
import AppKit

/// 日志查看器窗口 — 左右分栏
final class LogViewerWindow {

    private var window: NSWindow?
    private let logFileIO: LogFileIO

    init(logFileIO: LogFileIO = DefaultLogFileIO()) {
        self.logFileIO = logFileIO
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let listView = LogEntryListView(logFileIO: logFileIO)
        let detailView = LogEntryDetailView()

        listView.setUp { [weak detailView] entry, fileName in
            detailView?.show(entry: entry, sourceFile: fileName)
        }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(listView)
        splitView.addArrangedSubview(detailView)
        splitView.setPosition(400, ofDividerAt: 0)

        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 600)
        let win = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "日志查看器"
        win.contentView = splitView
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = WindowDelegate { [weak self] in
            self?.window = nil
        }

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 窗口关闭委托

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
```

- [ ] **Step 2: Commit**

```bash
git add TalkFlow/Views/LogViewerWindow.swift
git commit -m "feat: add LogViewerWindow with left-right split layout"
```

---

### Task 9: AppDelegate 集成 — 替换 print、清理、LogCardView

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 在 AppDelegate 中做以下修改**

修改点：

**a) 添加属性：**
```swift
// 在 "private var window: NSWindow?" 下方添加
private let logger: LoggerIO = impureMakeLogger()
private let logFileIO: LogFileIO = DefaultLogFileIO()
```

**b) 在 `applicationDidFinishLaunching` 末尾添加清理和日志卡片：**
```swift
// 在 "impureSetupSTT()" 后、方法结束前添加

// 清理两周前的日志和录音
logFileIO.cleanOldLogs(before: 14)
let filePathIO = AppSupportFilePathIO()
cleanOldRecordings(fileIO: filePathIO, before: 14)
```

**c) 在 `impureShowMainWindow()` 中，mc.bottomAnchor 约束前添加日志卡片：**
```swift
// 在 "mc.isHidden = false" 之后，NSLayoutConstraint.activate 之前添加

// 日志卡片
let logCardView = LogCardView(logFileIO: logFileIO)
let logViewerWindow = LogViewerWindow(logFileIO: logFileIO)
logCardView.setUp {
    logViewerWindow.show()
}
let logCard = CardView(title: "日志", contentView: logCardView)
logCard.setUp()
rootView.addSubview(logCard)

// 然后修改 mc.bottomAnchor 约束，改为：
// 原来: mc.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
// 改为: logCard.topAnchor.constraint(equalTo: mc.bottomAnchor, constant: 16),
// 新增:
// logCard.leadingAnchor 和 trailingAnchor 同其他卡片
// logCard.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
```

**d) 替换所有 `print("[Tag] ...")` 为 logger 调用：**

按照以下映射：

| 级别 | 调用模式 |
|------|---------|
| `info` | 正常流程：`logger.info(tag: "Pipeline", "开始 STT 转写...")` |
| `debug` | 调试细节：`logger.debug(tag: "STT", "推理: \(tokenIds.count) token IDs")` |
| `warning` | 降级/溶断：`logger.warning(tag: "Pipeline", "润色失败，降级使用原文: \(error)")` |
| `error` | 异常失败：`logger.error(tag: "Pipeline", "STT 失败: \(error)")` |

具体替换列表：

```
[Pipeline] 录音文件: url.path          → logger.info(tag: "Pipeline", "录音文件: \(url.path)")
[Pipeline] 开始 STT 转写...            → logger.info(tag: "Pipeline", "开始 STT 转写...")
[Pipeline] 开始 LLM 润色...            → logger.info(tag: "Pipeline", "开始 LLM 润色...")
[Pipeline] 润色完成: ...               → logger.info(tag: "Pipeline", "润色完成: \(response.content.prefix(60))...")
[Pipeline] 润色失败，降级使用原文: error → logger.warning(tag: "Pipeline", "润色失败，降级使用原文: \(error)")
[Pipeline] 开始 LLM 润色+翻译...        → logger.info(tag: "Pipeline", "开始 LLM 润色+翻译...")
[Pipeline] 润色+翻译完成: ...            → logger.info(tag: "Pipeline", "润色+翻译完成: \(response.content.prefix(60))...")
[Pipeline] 翻译失败，降级使用原文: error → logger.warning(tag: "Pipeline", "翻译失败，降级使用原文: \(error)")
[Pipeline] 管线完成: ...               → logger.info(tag: "Pipeline", "管线完成: \(finalResult)")
[Pipeline] 识别文本 (language): text    → logger.info(tag: "Pipeline", "识别文本 (\(language)): \(text)")
[Pipeline] 已写入剪贴板                 → logger.info(tag: "Pipeline", "已写入剪贴板")
[Pipeline] Cmd+V 粘贴✅ 成功            → logger.info(tag: "Pipeline", "Cmd+V 粘贴成功")
[Pipeline] Cmd+V 粘贴❌ 失败            → logger.error(tag: "Pipeline", "Cmd+V 粘贴失败")
[Pipeline] 静音 — 跳过粘贴              → logger.info(tag: "Pipeline", "静音 — 跳过粘贴")
[Pipeline] STT 失败: error              → logger.error(tag: "Pipeline", "STT 失败: \(error)")
[Pipeline] STT 异常: error              → logger.error(tag: "Pipeline", "STT 异常: \(error)")
[Pipeline] 快捷键触发 → 切换到 phase     → logger.debug(tag: "Pipeline", "快捷键触发 → 切换到 \(nextPhase)")
[Pipeline] 录音太短 — 丢弃              → logger.info(tag: "Pipeline", "录音太短(< \(minRecordingDuration)s) — 丢弃")
[Pipeline] 防抖忽略                     → logger.debug(tag: "Pipeline", "防抖忽略（间隔 < \(debounceInterval)s）")
[Pipeline] 🎤 开始录音 → ...            → logger.info(tag: "Pipeline", "🎤 开始录音 → \(url.lastPathComponent)")
[Pipeline] ❌ 录音启动失败: error        → logger.error(tag: "Pipeline", "录音启动失败: \(error)")
[Pipeline] ⏹ 停止录音 时长=...s         → logger.info(tag: "Pipeline", "⏹ 停止录音 时长=\(String(format: "%.1f", duration))s")
[Pipeline] 润色 — ADC 未检测到          → logger.info(tag: "Pipeline", "润色 — ADC 未检测到，跳过")
[Pipeline] 润色 — ProjectID 或 modelName 为空 → logger.info(tag: "Pipeline", "润色 — ProjectID 或 modelName 为空，跳过")
[Pipeline] 翻译 — ADC 未检测到          → logger.info(tag: "Pipeline", "翻译 — ADC 未检测到，跳过")
[Pipeline] 翻译 — ProjectID 或 modelName 为空 → logger.info(tag: "Pipeline", "翻译 — ProjectID 或 modelName 为空，跳过")
[STT] 解码: samples.count samples       → logger.debug(tag: "STT", "解码: \(samples.count) samples @ \(sampleRate)Hz")
[STT] 重采样: resampled.count samples   → logger.debug(tag: "STT", "重采样: \(resampled.count) samples @ 16000Hz")
[STT] 静音判定: ...                     → logger.info(tag: "STT", "静音判定: 采样数 < 4800")
[STT] Fbank: ...                        → logger.debug(tag: "STT", "Fbank: \(fbank.count) frames x \(fbank.first?.count ?? 0) dims")
[STT] Fbank isEmpty                     → logger.debug(tag: "STT", "Fbank isEmpty")
[STT] LFR: ...                          → logger.debug(tag: "STT", "LFR: \(lfr.count) frames x \(lfr.first?.count ?? 0) dims")
[STT] LFR isEmpty                       → logger.debug(tag: "STT", "LFR isEmpty")
[STT] CMVN done, starting inference...  → logger.debug(tag: "STT", "CMVN done, starting inference...")
[STT] 推理: tokenIds.count token IDs    → logger.debug(tag: "STT", "推理: \(tokenIds.count) token IDs")
[STT] 解码: "text"                      → logger.info(tag: "STT", "解码: \"\(text)\"")
[STT] 后处理: "cleaned"                 → logger.debug(tag: "STT", "后处理: \"\(cleaned)\"")
[ADC] ADC 文件不存在: path              → logger.info(tag: "ADC", "ADC 文件不存在: \(adcPath.path)")
[ADC] 读取 ADC 文件失败: error          → logger.error(tag: "ADC", "读取 ADC 文件失败: \(error.localizedDescription)")
[ADC] ADC JSON 格式错误                 → logger.error(tag: "ADC", "ADC JSON 格式错误")
[ADC] ADC JSON 解析失败: error          → logger.error(tag: "ADC", "ADC JSON 解析失败: \(error.localizedDescription)")
[ADC] ADC 解析失败: error               → logger.error(tag: "ADC", "ADC 解析失败: \(error)")
[AppConfig] 已保存: url.path            → logger.debug(tag: "AppConfig", "已保存: \(url.path)")
[AppConfig] 保存失败: error             → logger.error(tag: "AppConfig", "保存失败: \(error.localizedDescription)")
[AppConfig] 配置文件不存在，使用默认     → logger.info(tag: "AppConfig", "配置文件不存在，使用默认")
[AppConfig] 已加载: url.path            → logger.debug(tag: "AppConfig", "已加载: \(url.path)")
[AppConfig] 加载失败: error             → logger.warning(tag: "AppConfig", "加载失败: \(error.localizedDescription)，使用默认")
[TalkFlow.Hotkey] msg                   → logger.debug(tag: "Hotkey", "\(msg)")
```

- [ ] **Step 2: 运行全部测试确认没有破坏现有功能**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```
预期：`** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: integrate LoggerIO, cleanup, and LogCardView into AppDelegate"
```

---

### Task 10: 验证与清理

- [ ] **Step 1: 运行全量测试**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|executed"
```
预期：全部通过，无失败。

- [ ] **Step 2: 功能性检查清单**

- [ ] `latest.log` 文件在 `~/Library/Application Support/TalkFlow/Logs/` 下生成
- [ ] 日志格式为 JSON Lines
- [ ] 主窗口底部出现"日志"卡片
- [ ] 点击"打开"弹出日志查看器窗口
- [ ] 左侧显示日志列表，支持文件切换、级别筛选
- [ ] 点击条目右侧显示详情
- [ ] checkbox 勾选后可复制到剪贴板
- [ ] 启动时自动清理 14 天前日志和录音

- [ ] **Step 3: 最终 commit（如有遗漏）**
