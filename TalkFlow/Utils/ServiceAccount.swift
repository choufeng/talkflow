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

/// 从 JSON 字典解析 ServiceAccount（纯函数，无副作用）
func parseServiceAccount(from json: [String: Any]) throws -> ServiceAccount {
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
