import Foundation
import Security

/// Account-scoped provider secret storage. Items opt into iCloud Keychain so a
/// paired service can survive reinstall/device replacement when the user enables
/// Keychain sync. Heartable's account UUID remains part of every key, preventing
/// another Heartable account on the device from adopting the credential.
enum Keychain {
    static func set(_ value: String?, for key: String) {
        guard let value, let data = value.data(using: .utf8) else {
            delete(key); return
        }
        write(data, for: key)
    }

    static func get(_ key: String) -> String? {
        var query = matchingQuery(key)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

        // Existing releases wrote device-local items. Reading one upgrades it in
        // place to synchronizable storage without changing its account-scoped key.
        if (item[kSecAttrSynchronizable as String] as? Bool) != true {
            write(data, for: key)
        }
        return value
    }

    static func delete(_ key: String) {
        SecItemDelete(matchingQuery(key) as CFDictionary)
    }

    private static func write(_ data: Data, for key: String) {
        SecItemDelete(matchingQuery(key) as CFDictionary)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrSynchronizable as String] = true
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            // Managed devices may disable iCloud Keychain. Preserve the local
            // credential rather than turning that policy into a disconnect.
            add.removeValue(forKey: kSecAttrSynchronizable as String)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func matchingQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
