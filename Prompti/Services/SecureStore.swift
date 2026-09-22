import Foundation
import Security
import CryptoKit

struct SecureStore: Sendable {
    private let service: String
    init(service: String = "com.prompti.app.byok") { self.service = service }

    private static let reviewScope = "systemone|https://api.typesafe.ai/v1/systemone"
    private func account(scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func account(for configuration: ProviderConfiguration) -> String {
        account(scope: configuration.credentialScope)
    }

    func saveAPIKey(_ value: String, for configuration: ProviderConfiguration) throws {
        try save(value, account: account(for: configuration))
    }

    func saveReviewKey(_ value: String) throws { try save(value, account: account(scope: Self.reviewScope)) }
    func readReviewKey() -> String? { read(account: account(scope: Self.reviewScope)) }
    func deleteReviewKey() { delete(account: account(scope: Self.reviewScope)) }

    private func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecureStoreError.unhandled(updateStatus) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureStoreError.unhandled(status) }
    }

    func readAPIKey(for configuration: ProviderConfiguration) -> String? {
        read(account: account(for: configuration))
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey(for configuration: ProviderConfiguration) {
        delete(account: account(for: configuration))
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Assign the old single key only to the user's previously saved provider.
    func migrateLegacyKey(for configuration: ProviderConfiguration) {
        guard configuration.kind != .apple, let legacy = read(account: "primary-api-key") else { return }
        do {
            if readAPIKey(for: configuration) == nil { try saveAPIKey(legacy, for: configuration) }
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "primary-api-key"
            ] as CFDictionary)
        } catch { /* Keep the old key if migration cannot finish. */ }
    }
}

enum SecureStoreError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled: String(localized: "Unable to access the device Keychain. Please try again.")
        }
    }
}
