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

    // MARK: - LogFileIO 集成测试

    func test_append_and_entries_roundTrip() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

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

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStr = dayString(from: yesterday)

        let io = TestLogFileIO(directory: tmpDir, initialDate: yesterdayStr)
        io.append(LogEntry(timestamp: yesterday, level: .info, tag: "T", message: "old"))

        io.forceRotate(to: dayString(from: Date()))

        let files = io.logFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "\(yesterdayStr).log" })
        XCTAssertTrue(files.contains { $0.lastPathComponent == "latest.log" })

        let archive = files.first { $0.lastPathComponent != "latest.log" }!
        let archivedEntries = io.entries(from: archive)
        XCTAssertEqual(archivedEntries.count, 1)
        XCTAssertEqual(archivedEntries[0].message, "old")
    }

    func test_cleanOldLogs_removesOldFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkFlowTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let oldFile = tmpDir.appendingPathComponent("\(dayString(from: oldDate)).log")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try? "test".write(to: oldFile, atomically: true, encoding: .utf8)

        let latestFile = tmpDir.appendingPathComponent("latest.log")
        try? "latest".write(to: latestFile, atomically: true, encoding: .utf8)

        let io = TestLogFileIO(directory: tmpDir)
        io.cleanOldLogs(before: 14)

        let remaining = io.logFiles()
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

        XCTAssertEqual(files[0].lastPathComponent, "latest.log")
        XCTAssertEqual(files[1].lastPathComponent, "2026-05-04.log")
        XCTAssertEqual(files[2].lastPathComponent, "2026-05-03.log")
    }
}

// MARK: - 测试专用实现

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

    func rotateIfNeeded() {}

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
