import Foundation

public struct AISettings: Equatable {
    public var baseURL: String
    public var model: String
    public var defaultLanguage: String
    public var timeoutSeconds: TimeInterval
    public var apiKey: String

    public init(
        baseURL: String = "",
        model: String = "",
        defaultLanguage: String = "中文",
        timeoutSeconds: TimeInterval = 30,
        apiKey: String = ""
    ) {
        self.baseURL = baseURL
        self.model = model
        self.defaultLanguage = defaultLanguage
        self.timeoutSeconds = timeoutSeconds
        self.apiKey = apiKey
    }

    public var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
