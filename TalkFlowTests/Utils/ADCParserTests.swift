import XCTest
@testable import TalkFlow

final class ADCParserTests: XCTestCase {

    // MARK: - Service Account

    func testParseADC_serviceAccountFullJSON() throws {
        let json: [String: Any] = [
            "type": "service_account",
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
            "project_id": "my-project",
        ]
        let result = try parseADC(from: json)
        guard case .serviceAccount(let email, let key, let uri, let pid) = result else {
            return XCTFail("Expected serviceAccount")
        }
        XCTAssertEqual(email, "test@developer.gserviceaccount.com")
        XCTAssertEqual(key, "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(uri, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(pid, "my-project")
    }

    func testParseADC_serviceAccountWithoutProjectID() throws {
        let json: [String: Any] = [
            "type": "service_account",
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
        ]
        let result = try parseADC(from: json)
        guard case .serviceAccount(_, _, _, let pid) = result else {
            return XCTFail("Expected serviceAccount")
        }
        XCTAssertNil(pid)
    }

    func testParseADC_serviceAccountMissingClientEmail_throws() {
        let json: [String: Any] = [
            "type": "service_account",
            "private_key": "k",
            "token_uri": "https://example.com",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "client_email")
        }
    }

    // MARK: - Authorized User

    func testParseADC_authorizedUserFullJSON() throws {
        let json: [String: Any] = [
            "type": "authorized_user",
            "client_id": "123.apps.googleusercontent.com",
            "client_secret": "secret123",
            "refresh_token": "1//refreshtoken",
            "quota_project_id": "my-quota-project",
        ]
        let result = try parseADC(from: json)
        guard case .authorizedUser(let cid, let cs, let rt, let pid) = result else {
            return XCTFail("Expected authorizedUser")
        }
        XCTAssertEqual(cid, "123.apps.googleusercontent.com")
        XCTAssertEqual(cs, "secret123")
        XCTAssertEqual(rt, "1//refreshtoken")
        XCTAssertEqual(pid, "my-quota-project")
    }

    func testParseADC_authorizedUserWithoutProjectID() throws {
        let json: [String: Any] = [
            "type": "authorized_user",
            "client_id": "123.apps.googleusercontent.com",
            "client_secret": "secret123",
            "refresh_token": "1//refreshtoken",
        ]
        let result = try parseADC(from: json)
        guard case .authorizedUser(_, _, _, let pid) = result else {
            return XCTFail("Expected authorizedUser")
        }
        XCTAssertNil(pid)
    }

    func testParseADC_authorizedUserMissingClientID_throws() {
        let json: [String: Any] = [
            "type": "authorized_user",
            "client_secret": "secret123",
            "refresh_token": "1//refreshtoken",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "client_id")
        }
    }

    // MARK: - Unsupported/Invalid

    func testParseADC_unsupportedType_throws() {
        let json: [String: Any] = ["type": "external_account"]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.unsupportedType(let type) = error else {
                return XCTFail("Expected unsupportedType error")
            }
            XCTAssertEqual(type, "external_account")
        }
    }

    func testParseADC_missingType_throws() {
        let json: [String: Any] = ["client_email": "x@x.com"]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "type")
        }
    }
}
