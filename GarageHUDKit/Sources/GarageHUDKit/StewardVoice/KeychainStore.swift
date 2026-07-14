import Foundation
import Security

/// A tiny wrapper over the iOS/macOS Keychain for one secret at a time — used to hold the owner's
/// cloud-TTS API key. The key is never written to UserDefaults, logs, or the JSON garage file; it
/// lives only in the Keychain, which is the correct home for a credential.
public enum KeychainStore {
    /// Store (or overwrite) a string value for a key. Passing nil/empty deletes it.
    @discardableResult
    public static func set(_ value: String?, for account: String, service: String = "com.vanlaw.GarageHUD") -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)   // idempotent overwrite

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public static func get(_ account: String, service: String = "com.vanlaw.GarageHUD") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    public static func has(_ account: String, service: String = "com.vanlaw.GarageHUD") -> Bool {
        get(account, service: service)?.isEmpty == false
    }
}
