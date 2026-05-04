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

        // 15 天前的录音文件
        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let oldFilename = recordingFilenameForTest(from: oldDate, index: 1)
        let oldFile = recordingsDir.appendingPathComponent(oldFilename)
        try? "old".write(to: oldFile, atomically: true, encoding: .utf8)

        // 3 天前的录音文件
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let recentFilename = recordingFilenameForTest(from: recentDate, index: 2)
        let recentFile = recordingsDir.appendingPathComponent(recentFilename)
        try? "recent".write(to: recentFile, atomically: true, encoding: .utf8)

        // 非 .m4a 文件
        let otherFile = recordingsDir.appendingPathComponent("readme.txt")
        try? "keep".write(to: otherFile, atomically: true, encoding: .utf8)

        let mockFileIO = MockFilePathIOForCleanup(directory: recordingsDir)
        cleanOldRecordings(fileIO: mockFileIO, before: 14)

        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: recordingsDir.path)) ?? []
        XCTAssertFalse(remaining.contains(oldFilename))
        XCTAssertTrue(remaining.contains(recentFilename))
        XCTAssertTrue(remaining.contains("readme.txt"))
    }
}

// MARK: - 测试辅助

func recordingFilenameForTest(from date: Date, index: Int) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    fmt.timeZone = TimeZone.current
    let ts = fmt.string(from: date)
    return "\(ts)_\(String(format: "%03d", index)).m4a"
}

final class MockFilePathIOForCleanup: FilePathIO {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    var recordingsDirectory: URL { directory }
    func nextRecordingURL() -> URL { directory.appendingPathComponent("mock.m4a") }
}
