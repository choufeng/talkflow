import Foundation

// MARK: - ADC 凭据类型

/// Application Default Credentials — 支持 service_account 与 authorized_user 两种类型
enum ADCCredential: Equatable {
    /// Service Account（JWT 认证）
    case serviceAccount(
        clientEmail: String,
        privateKey: String,
        tokenURI: String,
        projectID: String?
    )
    /// Authorized User（OAuth2 refresh_token 认证）
    case authorizedUser(
        clientID: String,
        clientSecret: String,
        refreshToken: String,
        projectID: String?
    )
}

// MARK: - 错误

enum ADCParseError: Error, Equatable {
    case invalidJSON
    case missingField(String)
    case unsupportedType(String)
}

// MARK: - 纯函数解析

/// 从 ADC JSON 字典解析 ADCCredential（纯函数，无副作用）
func parseADC(from json: [String: Any]) throws -> ADCCredential {
    guard let type = json["type"] as? String else {
        throw ADCParseError.missingField("type")
    }

    switch type {
    case "service_account":
        return try parseServiceAccountADC(from: json)
    case "authorized_user":
        return try parseAuthorizedUserADC(from: json)
    default:
        throw ADCParseError.unsupportedType(type)
    }
}

// MARK: - 子类型解析

private func parseServiceAccountADC(from json: [String: Any]) throws -> ADCCredential {
    guard let clientEmail = json["client_email"] as? String else {
        throw ADCParseError.missingField("client_email")
    }
    guard let privateKey = json["private_key"] as? String else {
        throw ADCParseError.missingField("private_key")
    }
    guard let tokenURI = json["token_uri"] as? String else {
        throw ADCParseError.missingField("token_uri")
    }
    let projectID = json["project_id"] as? String

    return .serviceAccount(
        clientEmail: clientEmail,
        privateKey: privateKey,
        tokenURI: tokenURI,
        projectID: projectID
    )
}

private func parseAuthorizedUserADC(from json: [String: Any]) throws -> ADCCredential {
    guard let clientID = json["client_id"] as? String else {
        throw ADCParseError.missingField("client_id")
    }
    guard let clientSecret = json["client_secret"] as? String else {
        throw ADCParseError.missingField("client_secret")
    }
    guard let refreshToken = json["refresh_token"] as? String else {
        throw ADCParseError.missingField("refresh_token")
    }
    let projectID = json["quota_project_id"] as? String

    return .authorizedUser(
        clientID: clientID,
        clientSecret: clientSecret,
        refreshToken: refreshToken,
        projectID: projectID
    )
}
