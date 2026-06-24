import Foundation

public protocol AIServiceProtocol {
    func run(action: AIAction, item: ClipboardItem, settings: AISettings) async throws -> String
}

public protocol AIHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionAIHTTPClient: AIHTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public enum AIServiceError: Error, Equatable, LocalizedError {
    case missingConfiguration
    case unsupportedItem
    case inputTooLong
    case invalidBaseURL
    case httpStatus(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Configure AI Base URL, API Key, and Model in Settings."
        case .unsupportedItem: return "AI actions only support text in this version."
        case .inputTooLong: return "Selected text is too long to send."
        case .invalidBaseURL: return "AI Base URL is invalid."
        case .httpStatus(let status, let url): return "AI request to \(url) failed with HTTP \(status)."
        case .invalidResponse: return "AI response could not be parsed."
        }
    }
}

public final class AIService: AIServiceProtocol {
    private let httpClient: AIHTTPClient
    private let maxInputCharacters: Int

    public init(httpClient: AIHTTPClient = URLSessionAIHTTPClient(), maxInputCharacters: Int = 20_000) {
        self.httpClient = httpClient
        self.maxInputCharacters = maxInputCharacters
    }

    public func run(action: AIAction, item: ClipboardItem, settings: AISettings) async throws -> String {
        guard settings.isComplete else { throw AIServiceError.missingConfiguration }
        guard action.supports(item) else { throw AIServiceError.unsupportedItem }
        guard let input = item.contentText else { throw AIServiceError.invalidResponse }
        guard input.count <= maxInputCharacters else { throw AIServiceError.inputTooLong }

        switch settings.provider {
        case .openAICompatible:
            return try await runOpenAICompatible(action: action, input: input, settings: settings)
        case .anthropic:
            return try await runAnthropic(action: action, input: input, settings: settings)
        }
    }

    private func runOpenAICompatible(action: AIAction, input: String, settings: AISettings) async throws -> String {
        let trimmedBase = settings.effectiveBaseURL.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard let url = URL(string: trimmedBase + "/chat/completions") else { throw AIServiceError.invalidBaseURL }

        var request = URLRequest(url: url, timeoutInterval: settings.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: settings.model,
            messages: [RequestMessage(role: "user", content: action.prompt(for: input, defaultLanguage: settings.defaultLanguage))]
        ))

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw AIServiceError.httpStatus(response.statusCode, url.absoluteString) }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIServiceError.invalidResponse
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    private func runAnthropic(action: AIAction, input: String, settings: AISettings) async throws -> String {
        let trimmedBase = settings.effectiveBaseURL.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard let url = URL(string: trimmedBase + "/messages") else { throw AIServiceError.invalidBaseURL }

        var request = URLRequest(url: url, timeoutInterval: settings.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: settings.model,
            max_tokens: settings.maxTokens,
            messages: [AnthropicMessage(role: "user", content: action.prompt(for: input, defaultLanguage: settings.defaultLanguage))]
        ))

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw AIServiceError.httpStatus(response.statusCode, url.absoluteString) }
        let decoded: AnthropicResponse
        do {
            decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw AIServiceError.invalidResponse
        }
        guard let text = decoded.content.first?.text, !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
}

private struct RequestMessage: Encodable {
    let role: String
    let content: String
}

private struct ResponseMessage: Decodable {
    let role: String?
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [AnthropicMessage]
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Decodable {
    let content: [AnthropicContentBlock]
}

private struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
}
