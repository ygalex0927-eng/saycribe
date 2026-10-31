import Foundation
import Security

/// 设备 token 存钥匙串（共享钥匙串组，键盘也能读）。
public final class TokenStore {
    public enum TokenError: Error, Equatable { case invalidFormat, keychain(OSStatus) }

    private let service: String
    private let account = "device-token"
    private let accessGroup: String?

    /// accessGroup 传 nil 时用默认组（单元测试用）。
    public init(service: String = "com.motomotos.saycribe.relay", accessGroup: String? = TokenStore.defaultAccessGroup()) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// 从 Info.plist 的 AppIdentifierPrefix 推导共享组；拿不到返回 nil。
    public static func defaultAccessGroup() -> String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty else { return nil }
        return prefix + SharedConstants.keychainGroupSuffix
    }

    /// 格式：sct_ 加 base64url。只做宽松检查，不打印 token。
    public static func isPlausible(_ token: String) -> Bool {
        guard token.hasPrefix("sct_"), token.count >= 12 else { return false }
        let body = token.dropFirst(4)
        return body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func baseQuery() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func save(_ token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokenStore.isPlausible(token) else { throw TokenError.invalidFormat }
        let data = Data(token.utf8)
        let status = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw TokenError.keychain(s) }
        } else if status != errSecSuccess {
            throw TokenError.keychain(status)
        }
    }

    public func load() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
