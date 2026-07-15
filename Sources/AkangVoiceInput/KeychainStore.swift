import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "密钥内容无效。"
        case .unexpectedStatus(let status):
            if status == errSecAuthFailed {
                "无法读取旧版保存的凭证。请重新设置 API Key 和 Workspace ID。"
            } else {
                "Keychain 操作失败（状态码：\(status)）。"
            }
        }
    }
}

struct KeychainStore {
    // v3 starts with the app's stable designated requirement. Older local
    // development items may carry ACLs tied to obsolete ad-hoc signatures.
    private static let service = "com.akang.ai-voice-input.credentials.v3"
    private static let apiKeyAccount = "bailian-api-key"
    private static let workspaceIDDefaultsKey = "bailianWorkspaceID"
    private static let valueCache = KeychainValueCache()

    static func saveAPIKey(_ value: String) throws {
        try save(value, account: apiKeyAccount)
    }

    static func saveWorkspaceID(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainStoreError.invalidData }
        UserDefaults.standard.set(trimmed, forKey: workspaceIDDefaultsKey)
    }

    static func saveCredentials(apiKey: String, workspaceID: String) throws {
        try saveAPIKey(apiKey)
        do {
            try saveWorkspaceID(workspaceID)
            guard try readAPIKey() == apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                  try readWorkspaceID() == workspaceID.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw KeychainStoreError.invalidData
            }
        } catch {
            try? remove(account: apiKeyAccount)
            throw error
        }
    }

    private static func save(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !data.isEmpty else {
            throw KeychainStoreError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            valueCache.set(trimmed, for: account)
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var insertQuery = query
        attributes.forEach { insertQuery[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(insertStatus)
        }
        valueCache.set(trimmed, for: account)
    }

    static func readAPIKey() throws -> String? {
        try read(account: apiKeyAccount)
    }

    static func readWorkspaceID() throws -> String? {
        UserDefaults.standard.string(forKey: workspaceIDDefaultsKey)
    }

    private static func read(account: String) throws -> String? {
        if let cached = valueCache.value(for: account) {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        valueCache.set(value, for: account)
        return value
    }

    static func hasAPIKey() -> Bool {
        (try? readAPIKey()) != nil
    }

    static func hasWorkspaceID() -> Bool {
        guard let value = try? readWorkspaceID() else { return false }
        return !value.isEmpty
    }

    static func removeCredentials() throws {
        try remove(account: apiKeyAccount)
        UserDefaults.standard.removeObject(forKey: workspaceIDDefaultsKey)
    }

    private static func remove(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        valueCache.removeValue(for: account)
    }
}

private final class KeychainValueCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func set(_ value: String, for account: String) {
        lock.lock()
        values[account] = value
        lock.unlock()
    }

    func removeValue(for account: String) {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}
