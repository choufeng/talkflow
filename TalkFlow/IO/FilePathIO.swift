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
