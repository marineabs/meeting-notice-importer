import Foundation
import Security

final class APIKeyStore {
    static let shared = APIKeyStore()

    private let service = "com.example.MeetingImporter.credentials"
    private init() {}

    var hasAPIKey: Bool {
        hasAPIKey(for: .zhipu)
    }

    func hasAPIKey(for provider: AIProviderKey) -> Bool {
        !(loadAPIKey(for: provider) ?? "").isEmpty
    }

    func loadAPIKey(for provider: AIProviderKey = .zhipu) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    func saveAPIKey(_ rawValue: String, for provider: AIProviderKey = .zhipu) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            deleteAPIKey(for: provider)
            return
        }

        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }

        guard status == errSecSuccess else { throw APIKeyStoreError.keychain(status) }
    }

    func deleteAPIKey(for provider: AIProviderKey = .zhipu) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIProviderKey {
    case zhipu
    case qwen

    var account: String {
        switch self {
        case .zhipu: "zhipu-api-key"
        case .qwen: "qwen-api-key"
        }
    }
}

enum APIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "无法保存 API Key（钥匙串错误 \(status)）。"
        }
    }
}
