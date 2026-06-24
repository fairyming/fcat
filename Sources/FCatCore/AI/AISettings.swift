import Foundation

public enum AIProvider: String, CaseIterable, Identifiable {
    case openAICompatible = "openai-compatible"
    case anthropic = "anthropic"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropic: return "Anthropic"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAICompatible: return ""
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }
}

public struct AISettings: Equatable {
    public var provider: AIProvider
    public var baseURL: String
    public var model: String
    public var defaultLanguage: String
    public var timeoutSeconds: TimeInterval
    public var maxTokens: Int
    public var apiKey: String

    public init(
        provider: AIProvider = .openAICompatible,
        baseURL: String = "",
        model: String = "",
        defaultLanguage: String = "中文",
        timeoutSeconds: TimeInterval = 30,
        maxTokens: Int = 1024,
        apiKey: String = ""
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.defaultLanguage = defaultLanguage
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
        self.apiKey = apiKey
    }

    public var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return provider.defaultBaseURL }
        return trimmed
    }

    public var isComplete: Bool {
        !effectiveBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        maxTokens > 0
    }
}
