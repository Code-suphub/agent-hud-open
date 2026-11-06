import Foundation
import Security

/// Never include request credentials in UserDefaults, report snapshots, logs or the usage ledger.
public enum BalanceRequestVault {
    private static let service = "app.agenthud.custom-balance-request"
    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }

    public static func save(_ request: BalanceRequest, id: String) throws {
        try request.validate()
        let data = try JSONEncoder().encode(request)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess { throw failure() }
    }

    public static func load(id: String) throws -> BalanceRequest {
        var item = query(id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { throw failure() }
        do { return try JSONDecoder().decode(BalanceRequest.self, from: data) } catch { throw failure() }
    }

    public static func remove(id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
    }

    private static func failure() -> UsageProviderError {
        UsageProviderError(L10n.text("无法读写钥匙串中的余额请求，请重新导入", "Cannot access the saved balance request in Keychain; import it again"))
    }
}
