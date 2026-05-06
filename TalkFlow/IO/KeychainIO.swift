import Foundation

// MARK: - KeychainIO 协议

protocol KeychainIO {
    func get(_ key: String) throws -> String
    func set(_ key: String, value: String) throws
    func delete(_ key: String) throws
}

// MARK: - SecItem 实现

final class SecItemKeychainIO: KeychainIO {
    private let service: String

    init(service: String = "com.talkflow.anthropic") {
        self.service = service
    }

    func get(_ key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return value
    }

    func set(_ key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // 先尝试删除旧值
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }
}

// MARK: - Keychain 错误

enum KeychainError: Error, Equatable {
    case itemNotFound
    case invalidData
    case saveFailed
    case deleteFailed
}
