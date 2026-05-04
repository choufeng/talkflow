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
