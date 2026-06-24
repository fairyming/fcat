import Combine
import Foundation

public final class SettingsViewModel: ObservableObject {
    @Published public var hotKey: HotKey?
    @Published public var aiProvider: AIProvider
    @Published public var aiBaseURL: String
    @Published public var aiAPIKey: String
    @Published public var aiModel: String
    @Published public var aiDefaultLanguage: String
    @Published public var aiTimeoutSeconds: Double
    @Published public var aiMaxTokens: Int
    @Published public var aiSettingsMessage: String?
    private let defaults: UserDefaults
    private let key = "FCat.hotKey"
    private let aiSettingsStore: AISettingsStore

    public init(defaults: UserDefaults = .standard, aiSettingsStore: AISettingsStore = AISettingsStore()) {
        self.defaults = defaults
        self.aiSettingsStore = aiSettingsStore
        self.hotKey = Self.load(defaults: defaults, key: key)
        let ai = aiSettingsStore.loadSettings()
        self.aiProvider = ai.provider
        self.aiBaseURL = ai.baseURL
        self.aiAPIKey = ai.apiKey
        self.aiModel = ai.model
        self.aiDefaultLanguage = ai.defaultLanguage
        self.aiTimeoutSeconds = ai.timeoutSeconds
        self.aiMaxTokens = ai.maxTokens
    }

    public var hasHotKey: Bool { hotKey != nil }

    public func save(hotKey: HotKey?) {
        self.hotKey = hotKey
        if let hotKey {
            let data = try? JSONEncoder().encode(hotKey)
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func selectAIProvider(_ provider: AIProvider) {
        aiProvider = provider
        let trimmed = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == AIProvider.openAICompatible.defaultBaseURL || trimmed == AIProvider.anthropic.defaultBaseURL {
            aiBaseURL = provider.defaultBaseURL
        }
    }

    public func saveAISettings() {
        aiSettingsStore.save(provider: aiProvider, baseURL: aiBaseURL, model: aiModel, defaultLanguage: aiDefaultLanguage, timeoutSeconds: aiTimeoutSeconds, maxTokens: aiMaxTokens)
        aiSettingsStore.saveAPIKey(aiAPIKey)
        aiSettingsMessage = "AI settings saved"
    }

    private static func load(defaults: UserDefaults, key: String) -> HotKey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
}
