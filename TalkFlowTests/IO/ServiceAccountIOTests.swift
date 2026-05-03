import XCTest
@testable import TalkFlow

final class ServiceAccountIOTests: XCTestCase {

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

    // MARK: - 文件加载

    func test_load_validFile_success() throws {
        let path = writeTempJSON(validSAJSON())
        let sa = try loadServiceAccount(fromPath: path)
        XCTAssertEqual(sa.projectID, "my-project-123")
    }

    func test_load_fileNotFound_throws() {
        XCTAssertThrowsError(try loadServiceAccount(fromPath: "/nonexistent/sa.json")) { error in
            guard case ServiceAccountError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound")
            }
        }
    }

    func test_load_invalidJSON_throws() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try loadServiceAccount(fromPath: path)) { error in
            guard case ServiceAccountError.invalidJSON = error else {
                return XCTFail("Expected invalidJSON")
            }
        }
    }
}
