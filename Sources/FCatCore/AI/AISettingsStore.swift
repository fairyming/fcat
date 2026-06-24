import Foundation

public protocol AISettingsProviding {
    func loadSettings() -> AISettings
}

public final class AISettingsStore: AISettingsProviding {
    private let defaults: UserDefaults
    private let baseURLKey = "FCat.ai.baseURL"
    private let modelKey = "FCat.ai.model"
    private let languageKey = "FCat.ai.defaultLanguage"
    private let timeoutKey = "FCat.ai.timeoutSeconds"
    private let apiKeyKey = "FCat.ai.apiKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> AISettings {
        AISettings(
            baseURL: defaults.string(forKey: baseURLKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? "",
            defaultLanguage: defaults.string(forKey: languageKey) ?? "中文",
            timeoutSeconds: defaults.object(forKey: timeoutKey) as? TimeInterval ?? 30,
            apiKey: defaults.string(forKey: apiKeyKey) ?? ""
        )
    }

    public func save(baseURL: String, model: String, defaultLanguage: String, timeoutSeconds: TimeInterval) {
        defaults.set(baseURL, forKey: baseURLKey)
        defaults.set(model, forKey: modelKey)
        defaults.set(defaultLanguage, forKey: languageKey)
        defaults.set(timeoutSeconds, forKey: timeoutKey)
    }

    public func saveAPIKey(_ apiKey: String) {
        defaults.set(apiKey, forKey: apiKeyKey)
    }
}
