import XCTest
@testable import TalkFlow

final class KeychainIOTests: XCTestCase {
    func test_mock_setThenGet_returnsValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "v")
        let v = try mock.get("k")
        XCTAssertEqual(v, "v")
    }

    func test_mock_getNotFound_throws() {
        let mock = MockKeychainIO()
        XCTAssertThrowsError(try mock.get("nonexistent")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func test_mock_set_overwritesValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "old")
        try mock.set("k", value: "new")
        XCTAssertEqual(try mock.get("k"), "new")
        XCTAssertEqual(mock.setCallCount, 2)
    }

    func test_mock_delete_removesValue() throws {
        let mock = MockKeychainIO()
        try mock.set("k", value: "v")
        try mock.delete("k")
        XCTAssertThrowsError(try mock.get("k"))
    }
}
