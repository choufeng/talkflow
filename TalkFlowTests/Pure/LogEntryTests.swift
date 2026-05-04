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
