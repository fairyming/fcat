import Foundation
import Security

public protocol APIKeyStore {
    func loadAPIKey() -> String
    func saveAPIKey(_ apiKey: String) throws
}

public protocol AISettingsProviding {
    func loadSettings() -> AISettings
}

public final class AISettingsStore: AISettingsProviding {
    private let defaults: UserDefaults
    private let keychain: APIKeyStore
    private let baseURLKey = "FCat.ai.baseURL"
    private let modelKey = "FCat.ai.model"
    private let languageKey = "FCat.ai.defaultLanguage"
    private let timeoutKey = "FCat.ai.timeoutSeconds"

    public init(defaults: UserDefaults = .standard, keychain: APIKeyStore = KeychainAPIKeyStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func loadSettings() -> AISettings {
        AISettings(
            baseURL: defaults.string(forKey: baseURLKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? "",
            defaultLanguage: defaults.string(forKey: languageKey) ?? "中文",
            timeoutSeconds: defaults.object(forKey: timeoutKey) as? TimeInterval ?? 30,
            apiKey: keychain.loadAPIKey()
        )
    }

    public func save(baseURL: String, model: String, defaultLanguage: String, timeoutSeconds: TimeInterval) {
        defaults.set(baseURL, forKey: baseURLKey)
        defaults.set(model, forKey: modelKey)
        defaults.set(defaultLanguage, forKey: languageKey)
        defaults.set(timeoutSeconds, forKey: timeoutKey)
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try keychain.saveAPIKey(apiKey)
    }
}

public final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "FCat"
    private let account = "AI API Key"

    public init() {}

    public func loadAPIKey() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let deleteQuery = baseQuery()
        SecItemDelete(deleteQuery as CFDictionary)

        guard !apiKey.isEmpty else { return }
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = Data(apiKey.utf8)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: "FCat.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to save API key"])
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
