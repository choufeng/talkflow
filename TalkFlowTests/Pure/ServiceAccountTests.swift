import XCTest
@testable import TalkFlow

final class ServiceAccountTests: XCTestCase {

    // 合法 SA JSON 示例
    private func validSAJSON() -> [String: Any] {
        return [
            "type": "service_account",
            "project_id": "my-project-123",
            "private_key_id": "abc123",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADAN...\n-----END PRIVATE KEY-----\n",
            "client_email": "test@my-project-123.iam.gserviceaccount.com",
            "client_id": "12345",
            "token_uri": "https://oauth2.googleapis.com/token",
        ]
    }

    private func writeTempJSON(_ dict: [String: Any]) -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".json"
        let data = try! JSONSerialization.data(withJSONObject: dict)
        try! data.write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - 合法解析

    func test_parse_validSA_success() throws {
        let path = writeTempJSON(validSAJSON())
        let sa = try parseServiceAccount(fromPath: path)
        XCTAssertEqual(sa.projectID, "my-project-123")
        XCTAssertTrue(sa.privateKey.contains("BEGIN PRIVATE KEY"))
        XCTAssertEqual(sa.clientEmail, "test@my-project-123.iam.gserviceaccount.com")
        XCTAssertEqual(sa.tokenURI, "https://oauth2.googleapis.com/token")
    }

    // MARK: - 文件不存在

    func test_parse_fileNotFound_throws() {
        XCTAssertThrowsError(try parseServiceAccount(fromPath: "/nonexistent/sa.json")) { error in
            guard case ServiceAccountError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound")
            }
        }
    }

    // MARK: - 缺失字段

    func test_parse_missingProjectID_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "project_id")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("project_id") = error else {
                return XCTFail("Expected missingField project_id")
            }
        }
    }

    func test_parse_missingPrivateKey_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "private_key")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("private_key") = error else {
                return XCTFail("Expected missingField private_key")
            }
        }
    }

    func test_parse_missingClientEmail_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "client_email")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("client_email") = error else {
                return XCTFail("Expected missingField client_email")
            }
        }
    }

    func test_parse_missingTokenURI_throws() {
        var dict = validSAJSON()
        dict.removeValue(forKey: "token_uri")
        let path = writeTempJSON(dict)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.missingField("token_uri") = error else {
                return XCTFail("Expected missingField token_uri")
            }
        }
    }

    // MARK: - 格式错误

    func test_parse_invalidJSON_throws() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try parseServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON")
            }
        }
    }
}
