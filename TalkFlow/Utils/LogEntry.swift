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
