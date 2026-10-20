import Foundation
import OpenGrindKit
import Security

/// Keeps the account credentials and the device identity in the Keychain,
/// readable only on this device after it has been unlocked once.
final class KeychainStore: CredentialStore {
    private let service = "org.opengrind.ios"

    func loadCredentials() -> String? { read("credentials") }

    func saveCredentials(_ credentials: String?) { write(credentials, to: "credentials") }

    /// The persisted device identity. A stable device is less likely to trip
    /// Grindr's bot protection than a new one on every launch.
    var device: String? {
        get { read("device") }
        set { write(newValue, to: "device") }
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String?, to account: String) {
        let query = query(account)
        guard let value else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }
}
