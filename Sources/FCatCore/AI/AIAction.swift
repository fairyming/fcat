import Foundation

public struct AIAction: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let supportedTypes: Set<ClipboardContentType>
    private let promptBuilder: (String, String) -> String

    public init(
        id: String,
        title: String,
        supportedTypes: Set<ClipboardContentType> = [.text],
        promptBuilder: @escaping (String, String) -> String
    ) {
        self.id = id
        self.title = title
        self.supportedTypes = supportedTypes
        self.promptBuilder = promptBuilder
    }

    public func supports(_ item: ClipboardItem) -> Bool {
        supportedTypes.contains(item.type)
    }

    public func prompt(for input: String, defaultLanguage: String) -> String {
        promptBuilder(input, defaultLanguage)
    }

    public static let translateToChinese = AIAction(id: "translate-zh", title: "Translate to Chinese") { input, language in
        "Translate the following text to \(language). Return only the translation.\n\n\(input)"
    }

    public static let summarize = AIAction(id: "summarize", title: "Summarize") { input, _ in
        "Summarize the following text concisely. Return only the summary.\n\n\(input)"
    }

    public static let rewrite = AIAction(id: "rewrite", title: "Rewrite") { input, _ in
        "Rewrite the following text to be clearer and more polished. Return only the rewritten text.\n\n\(input)"
    }

    public static let explainCode = AIAction(id: "explain-code", title: "Explain Code") { input, _ in
        "Explain what the following code does. Be concise and practical.\n\n\(input)"
    }

    public static let formatJSON = AIAction(id: "format-json", title: "Format JSON") { input, _ in
        "Format the following JSON. Return only formatted JSON.\n\n\(input)"
    }

    public static let builtIn: [AIAction] = [
        .translateToChinese,
        .summarize,
        .rewrite,
        .explainCode,
        .formatJSON
    ]

    public static func == (lhs: AIAction, rhs: AIAction) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.supportedTypes == rhs.supportedTypes
    }
}
