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
