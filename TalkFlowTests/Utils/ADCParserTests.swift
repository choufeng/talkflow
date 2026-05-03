import XCTest
@testable import TalkFlow

final class ADCParserTests: XCTestCase {

    // MARK: - 有效 ADC JSON（含 project_id）

    func testParseADC_validFullJSON_returnsParsedInfo() throws {
        let json: [String: Any] = [
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
            "project_id": "my-project",
        ]
        let result = try parseADC(from: json)
        XCTAssertEqual(result.clientEmail, "test@developer.gserviceaccount.com")
        XCTAssertEqual(result.privateKey, "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(result.tokenURI, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(result.projectID, "my-project")
    }

    // MARK: - 有效 ADC JSON（不含 project_id）

    func testParseADC_validJSONWithoutProjectID_returnsParsedInfoWithNilProjectID() throws {
        let json: [String: Any] = [
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
        ]
        let result = try parseADC(from: json)
        XCTAssertEqual(result.clientEmail, "test@developer.gserviceaccount.com")
        XCTAssertEqual(result.privateKey, "-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(result.tokenURI, "https://oauth2.googleapis.com/token")
        XCTAssertNil(result.projectID)
    }

    // MARK: - 缺失必填字段

    func testParseADC_missingClientEmail_throws() {
        let json: [String: Any] = [
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

    func testParseADC_missingPrivateKey_throws() {
        let json: [String: Any] = [
            "client_email": "x@x.com",
            "token_uri": "https://example.com",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "private_key")
        }
    }

    func testParseADC_missingTokenURI_throws() {
        let json: [String: Any] = [
            "client_email": "x@x.com",
            "private_key": "k",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "token_uri")
        }
    }
}
