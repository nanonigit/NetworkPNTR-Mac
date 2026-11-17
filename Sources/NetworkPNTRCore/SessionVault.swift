import Foundation
import Security

@MainActor public protocol SessionVault {
    func load() throws -> String?
    func save(_ token: String) throws
    func remove() throws
}

@MainActor public final class KeychainSessionVault: SessionVault {
    private let service: String
    private let account: String
    public init(service: String = "com.nanonigit.artex-mac", account: String = "dedicated-guest-session") { self.service = service; self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    public func load() throws -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BackendAPIError.secureStorage(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else { throw BackendAPIError.invalidResponse }
        return value
    }
    public func save(_ token: String) throws {
        let value = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw BackendAPIError.secureStorage(status) }
        var addition = query
        addition[kSecValueData as String] = value
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(addition as CFDictionary, nil)
        guard added == errSecSuccess else { throw BackendAPIError.secureStorage(added) }
    }
    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BackendAPIError.secureStorage(status) }
    }
}
