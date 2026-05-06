import Foundation
@testable import TalkFlow

final class MockKeychainIO: KeychainIO {
    private var storage: [String: String] = [:]

    var getCallCount = 0
    var setCallCount = 0

    func get(_ key: String) throws -> String {
        getCallCount += 1
        guard let value = storage[key] else {
            throw KeychainError.itemNotFound
        }
        return value
    }

    func set(_ key: String, value: String) throws {
        setCallCount += 1
        storage[key] = value
    }

    func delete(_ key: String) throws {
        storage.removeValue(forKey: key)
    }
}
