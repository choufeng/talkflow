import Foundation

/// Google Cloud Service Account 信息（从 JSON 密钥文件解析）
struct ServiceAccount: Equatable {
    let projectID: String
    let privateKey: String       // PEM 格式，含 -----BEGIN/END PRIVATE KEY-----
    let clientEmail: String
    let tokenURI: String
}

// MARK: - 错误

enum ServiceAccountError: Error, Equatable {
    case fileNotFound(path: String)
    case invalidJSON
    case missingField(String)
}

// MARK: - 纯函数解析

/// 从 Service Account JSON 文件路径解析
func parseServiceAccount(fromPath path: String) throws -> ServiceAccount {
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

    guard let projectID = json["project_id"] as? String else {
        throw ServiceAccountError.missingField("project_id")
    }
    guard let privateKey = json["private_key"] as? String else {
        throw ServiceAccountError.missingField("private_key")
    }
    guard let clientEmail = json["client_email"] as? String else {
        throw ServiceAccountError.missingField("client_email")
    }
    guard let tokenURI = json["token_uri"] as? String else {
        throw ServiceAccountError.missingField("token_uri")
    }

    return ServiceAccount(
        projectID: projectID,
        privateKey: privateKey,
        clientEmail: clientEmail,
        tokenURI: tokenURI
    )
}
