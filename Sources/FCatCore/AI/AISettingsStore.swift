import Foundation

public protocol AISettingsProviding {
    func loadSettings() -> AISettings
}

public final class AISettingsStore: AISettingsProviding {
    private let defaults: UserDefaults
    private let providerKey = "FCat.ai.provider"
    private let baseURLKey = "FCat.ai.baseURL"
    private let modelKey = "FCat.ai.model"
    private let languageKey = "FCat.ai.defaultLanguage"
    private let timeoutKey = "FCat.ai.timeoutSeconds"
    private let maxTokensKey = "FCat.ai.maxTokens"
    private let apiKeyKey = "FCat.ai.apiKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> AISettings {
        let providerRawValue = defaults.string(forKey: providerKey) ?? AIProvider.openAICompatible.rawValue
        let provider = AIProvider(rawValue: providerRawValue) ?? .openAICompatible

        return AISettings(
            provider: provider,
            baseURL: defaults.string(forKey: baseURLKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? "",
            defaultLanguage: defaults.string(forKey: languageKey) ?? "中文",
            timeoutSeconds: defaults.object(forKey: timeoutKey) as? TimeInterval ?? 30,
            maxTokens: defaults.object(forKey: maxTokensKey) as? Int ?? 1024,
            apiKey: defaults.string(forKey: apiKeyKey) ?? ""
        )
    }

    public func save(provider: AIProvider, baseURL: String, model: String, defaultLanguage: String, timeoutSeconds: TimeInterval, maxTokens: Int) {
        defaults.set(provider.rawValue, forKey: providerKey)
        defaults.set(baseURL, forKey: baseURLKey)
        defaults.set(model, forKey: modelKey)
        defaults.set(defaultLanguage, forKey: languageKey)
        defaults.set(timeoutSeconds, forKey: timeoutKey)
        defaults.set(maxTokens, forKey: maxTokensKey)
    }

    public func saveAPIKey(_ apiKey: String) {
        defaults.set(apiKey, forKey: apiKeyKey)
    }
}
