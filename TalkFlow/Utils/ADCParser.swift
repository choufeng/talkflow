import Foundation

// MARK: - ADC 解析结果

/// Application Default Credentials 解析结果
/// projectID 可选 — ADC 文件不一定包含
struct ADCParsedInfo: Equatable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String
    let projectID: String?
}

// MARK: - 错误

enum ADCParseError: Error, Equatable {
    case invalidJSON
    case missingField(String)
}

// MARK: - 纯函数解析

/// 从 ADC JSON 字典解析 ADCParsedInfo（纯函数，无副作用）
func parseADC(from json: [String: Any]) throws -> ADCParsedInfo {
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

    return ADCParsedInfo(
        clientEmail: clientEmail,
        privateKey: privateKey,
        tokenURI: tokenURI,
        projectID: projectID
    )
}
