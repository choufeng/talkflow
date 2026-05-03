import Foundation

// MARK: - ServiceAccount 文件加载（副作用）

/// 从 Service Account JSON 文件路径加载（含文件 I/O 副作用）
func loadServiceAccount(fromPath path: String) throws -> ServiceAccount {
    guard FileManager.default.fileExists(atPath: path) else {
        throw ServiceAccountError.fileNotFound(path: path)
    }

    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw ServiceAccountError.fileNotFound(path: path)
    }

    let json: [String: Any]
    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceAccountError.invalidJSON
        }
        json = dict
    } catch {
        throw ServiceAccountError.invalidJSON
    }

    return try parseServiceAccount(from: json)
}
