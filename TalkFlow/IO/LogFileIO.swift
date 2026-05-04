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
    private var currentDate: String

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
                let line = (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            handle.seekToEndOfFile()
            var line = data
            line.append(0x0A)
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
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

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

    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - 纯函数

func logDate(from filename: String, calendar: Calendar = .current) -> Date? {
    guard filename.hasSuffix(".log") else { return nil }
    let stem = String(filename.dropLast(4))
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

func dayString(from date: Date, calendar: Calendar = .current) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
}
