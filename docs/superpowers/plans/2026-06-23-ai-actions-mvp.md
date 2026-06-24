# FCat AI Actions MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal AI Actions flow to FCat so users can run built-in AI text actions on selected clipboard history items and copy/paste the result.

**Architecture:** Keep the existing clipboard storage model unchanged. Add focused AI modules under `Sources/FCatCore/AI`, inject them into `HistoryPanelViewModel`, and render the action/result state from `HistoryPanelView`. Persist non-secret AI settings with `UserDefaults` and store API keys with macOS Keychain.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Foundation `URLSession`, Security Keychain APIs, existing custom `FCatCoreTests` executable.

---

## Current Status (2026-06-24)

- All tasks (1-8) completed and merged.
- Latest commit: `660fb03 fix: address quality review issues for AI actions UI`.
- Task 9 verification:
  - `swift run FCatCoreTests` — passed
  - `swift build` — passed
  - `swift build -c release` — passed
- Remaining: Manual smoke test only (run `swift run FCat` and verify settings/history/AI actions work).

---

## File Structure

Create:

- `Sources/FCatCore/AI/AIAction.swift` — built-in AI action definitions and prompt generation.
- `Sources/FCatCore/AI/AISettings.swift` — `AISettings` model and validation.
- `Sources/FCatCore/AI/AISettingsStore.swift` — `UserDefaults` settings persistence and Keychain API key storage.
- `Sources/FCatCore/AI/AIService.swift` — OpenAI-compatible request building, network execution, response parsing, errors.
- `Sources/FCatCore/AI/JSONFormatter.swift` — local JSON formatting helper for the JSON action.

Modify:

- `Package.swift` — link the Security framework for Keychain access.
- `Sources/FCatCore/Pasteboard/PasteboardClient.swift` — add direct text writing for AI result copy/paste.
- `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift` — add AI state, action selection, execution, result copy, and item-change cleanup.
- `Sources/FCatCore/Views/HistoryPanelView.swift` — add action menu UI, AI result preview, and key handling.
- `Sources/FCatCore/ViewModels/SettingsViewModel.swift` — expose AI settings fields and save/load methods.
- `Sources/FCatCore/Views/HotKeyRecorderView.swift` — add AI settings controls below shortcut settings.
- `Sources/FCat/AppDelegate.swift` — pass `AIService` and settings store into the history view model; enlarge settings window.
- `Tests/FCatCoreTests/TestRunner.swift` — add tests for AI actions, settings validation, request JSON, ViewModel state, JSON formatting, and pasteboard text writing.

---

### Task 1: Add AI action definitions

**Files:**
- Create: `Sources/FCatCore/AI/AIAction.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing tests for built-in actions and prompt generation**

In `Tests/FCatCoreTests/TestRunner.swift`, add these calls in `main()` after `testHistoryViewModelCopySelectedWritesToPasteboard()`:

```swift
try testAIActionsContainExpectedBuiltIns()
try testAIActionSupportsOnlyTextItems()
try testAIActionPromptUsesInputAndDefaultLanguage()
```

Add these test functions before `makeStore(...)`:

```swift
static func testAIActionsContainExpectedBuiltIns() throws {
    let actions = AIAction.builtIn
    try expect(actions.map(\.id) == ["translate-zh", "summarize", "rewrite", "explain-code", "format-json"], "built-in AI action ids")
    try expect(actions.map(\.title) == ["Translate to Chinese", "Summarize", "Rewrite", "Explain Code", "Format JSON"], "built-in AI action titles")
}

static func testAIActionSupportsOnlyTextItems() throws {
    let text = makeItem(title: "text", type: .text)
    let image = makeItem(title: "image", type: .image)
    try expect(AIAction.summarize.supports(text), "AI action supports text")
    try expect(!AIAction.summarize.supports(image), "AI action rejects image")
}

static func testAIActionPromptUsesInputAndDefaultLanguage() throws {
    let prompt = AIAction.translateToChinese.prompt(for: "Hello", defaultLanguage: "中文")
    try expect(prompt.contains("Translate the following text to 中文"), "translate prompt language")
    try expect(prompt.contains("Hello"), "translate prompt input")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because `AIAction` does not exist.

- [ ] **Step 3: Create minimal AIAction implementation**

Create `Sources/FCatCore/AI/AIAction.swift`:

```swift
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
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.supportedTypes == rhs.supportTypesForComparison
    }

    private var supportTypesForComparison: Set<ClipboardContentType> { supportedTypes }
}
```

Fix the equality typo before running by replacing the `==` implementation with:

```swift
public static func == (lhs: AIAction, rhs: AIAction) -> Bool {
    lhs.id == rhs.id && lhs.title == rhs.title && lhs.supportedTypes == rhs.supportedTypes
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FCatCore/AI/AIAction.swift Tests/FCatCoreTests/TestRunner.swift
git commit -m "feat: add built-in AI actions"
```

---

### Task 2: Add AI settings model and storage

**Files:**
- Create: `Sources/FCatCore/AI/AISettings.swift`
- Create: `Sources/FCatCore/AI/AISettingsStore.swift`
- Modify: `Package.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing settings tests**

In `main()`, add after Task 1 tests:

```swift
try testAISettingsValidationRequiresBaseURLModelAndAPIKey()
try testAISettingsStorePersistsNonSecretSettings()
```

Add tests:

```swift
static func testAISettingsValidationRequiresBaseURLModelAndAPIKey() throws {
    let complete = AISettings(baseURL: "https://api.example.com/v1", model: "test-model", defaultLanguage: "中文", timeoutSeconds: 30, apiKey: "secret")
    try expect(complete.isComplete, "complete AI settings")

    let missingKey = AISettings(baseURL: "https://api.example.com/v1", model: "test-model", defaultLanguage: "中文", timeoutSeconds: 30, apiKey: "")
    try expect(!missingKey.isComplete, "missing API key")
}

static func testAISettingsStorePersistsNonSecretSettings() throws {
    let defaults = UserDefaults(suiteName: "FCatTests.AISettings")!
    defaults.removePersistentDomain(forName: "FCatTests.AISettings")

    let store = AISettingsStore(defaults: defaults, keychain: InMemoryAPIKeyStore())
    store.save(baseURL: "https://api.example.com/v1", model: "model-a", defaultLanguage: "中文", timeoutSeconds: 12)

    let loaded = store.loadSettings()
    try expect(loaded.baseURL == "https://api.example.com/v1", "stored AI base URL")
    try expect(loaded.model == "model-a", "stored AI model")
    try expect(loaded.defaultLanguage == "中文", "stored AI language")
    try expect(loaded.timeoutSeconds == 12, "stored AI timeout")
}
```

Add this fake near other test fakes:

```swift
final class InMemoryAPIKeyStore: APIKeyStore {
    var value = ""

    func loadAPIKey() -> String { value }
    func saveAPIKey(_ apiKey: String) throws { value = apiKey }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because `AISettingsStore`, `AISettings`, and `APIKeyStore` do not exist.

- [ ] **Step 3: Link Security framework**

Modify `Package.swift` target `FCatCore` linker settings:

```swift
.target(
    name: "FCatCore",
    linkerSettings: [
        .linkedLibrary("sqlite3"),
        .linkedFramework("Security")
    ]
),
```

- [ ] **Step 4: Add AISettings**

Create `Sources/FCatCore/AI/AISettings.swift`:

```swift
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
```

- [ ] **Step 5: Add AISettingsStore and Keychain store**

Create `Sources/FCatCore/AI/AISettingsStore.swift`:

```swift
import Foundation
import Security

public protocol APIKeyStore {
    func loadAPIKey() -> String
    func saveAPIKey(_ apiKey: String) throws
}

public final class AISettingsStore {
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
        var deleteQuery = baseQuery()
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
```

- [ ] **Step 6: Run tests to verify pass**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/FCatCore/AI/AISettings.swift Sources/FCatCore/AI/AISettingsStore.swift Tests/FCatCoreTests/TestRunner.swift
git commit -m "feat: add AI settings storage"
```

---

### Task 3: Add JSON formatting helper

**Files:**
- Create: `Sources/FCatCore/AI/JSONFormatter.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing JSON formatter tests**

In `main()`, add:

```swift
try testJSONFormatterFormatsValidJSON()
try testJSONFormatterRejectsInvalidJSON()
```

Add tests:

```swift
static func testJSONFormatterFormatsValidJSON() throws {
    let formatted = try JSONFormatter.format("{\"b\":2,\"a\":1}")
    try expect(formatted.contains("\n"), "formatted JSON has line breaks")
    try expect(formatted.contains("\"a\""), "formatted JSON contains key")
}

static func testJSONFormatterRejectsInvalidJSON() throws {
    do {
        _ = try JSONFormatter.format("not json")
        try expect(false, "invalid JSON should throw")
    } catch {
        try expect(true, "invalid JSON throws")
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because `JSONFormatter` does not exist.

- [ ] **Step 3: Add implementation**

Create `Sources/FCatCore/AI/JSONFormatter.swift`:

```swift
import Foundation

public enum JSONFormatter {
    public static func format(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let output = String(data: formatted, encoding: .utf8) else {
            throw NSError(domain: "FCat.JSONFormatter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode formatted JSON"])
        }
        return output
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FCatCore/AI/JSONFormatter.swift Tests/FCatCoreTests/TestRunner.swift
git commit -m "feat: add local JSON formatting"
```

---

### Task 4: Add OpenAI-compatible AI service

**Files:**
- Create: `Sources/FCatCore/AI/AIService.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing AIService tests**

In `main()`, add:

```swift
try awaitTestAIServiceBuildsOpenAICompatibleRequest()
try awaitTestAIServiceRejectsMissingConfiguration()
try awaitTestAIServiceRejectsLongTextBeforeNetwork()
try awaitTestAIServiceParsesSuccessfulResponse()
```

Because `main()` is not async, add this helper near tests:

```swift
static func runAsync(_ operation: @escaping () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var capturedError: Error?
    Task {
        do { try await operation() }
        catch { capturedError = error }
        semaphore.signal()
    }
    semaphore.wait()
    if let capturedError { throw capturedError }
}
```

Add test functions:

```swift
static func awaitTestAIServiceBuildsOpenAICompatibleRequest() throws {
    try runAsync {
        let client = FakeAIHTTPClient(responseData: Data("""{"choices":[{"message":{"content":"ok"}}]}""".utf8), statusCode: 200)
        let service = AIService(httpClient: client)
        let settings = AISettings(baseURL: "https://api.example.com/v1", model: "model-a", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "secret")
        _ = try await service.run(action: .summarize, item: makeItem(title: "hello", content: "Hello world"), settings: settings)

        try expect(client.lastRequest?.url?.absoluteString == "https://api.example.com/v1/chat/completions", "chat completions URL")
        try expect(client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret", "authorization header")
        let body = String(data: client.lastBody ?? Data(), encoding: .utf8) ?? ""
        try expect(body.contains("\"model\":\"model-a\""), "request model")
        try expect(body.contains("Summarize the following text"), "request prompt")
    }
}

static func awaitTestAIServiceRejectsMissingConfiguration() throws {
    try runAsync {
        let client = FakeAIHTTPClient(responseData: Data(), statusCode: 200)
        let service = AIService(httpClient: client)
        let settings = AISettings(baseURL: "", model: "", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "")
        do {
            _ = try await service.run(action: .summarize, item: makeItem(title: "hello", content: "Hello"), settings: settings)
            try expect(false, "missing configuration should throw")
        } catch AIServiceError.missingConfiguration {
            try expect(client.lastRequest == nil, "missing configuration avoids network")
        }
    }
}

static func awaitTestAIServiceRejectsLongTextBeforeNetwork() throws {
    try runAsync {
        let client = FakeAIHTTPClient(responseData: Data(), statusCode: 200)
        let service = AIService(httpClient: client, maxInputCharacters: 5)
        let settings = AISettings(baseURL: "https://api.example.com/v1", model: "model-a", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "secret")
        do {
            _ = try await service.run(action: .summarize, item: makeItem(title: "hello", content: "123456"), settings: settings)
            try expect(false, "long text should throw")
        } catch AIServiceError.inputTooLong {
            try expect(client.lastRequest == nil, "long input avoids network")
        }
    }
}

static func awaitTestAIServiceParsesSuccessfulResponse() throws {
    try runAsync {
        let client = FakeAIHTTPClient(responseData: Data("""{"choices":[{"message":{"content":"summary result"}}]}""".utf8), statusCode: 200)
        let service = AIService(httpClient: client)
        let settings = AISettings(baseURL: "https://api.example.com/v1", model: "model-a", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "secret")
        let result = try await service.run(action: .summarize, item: makeItem(title: "hello", content: "Hello"), settings: settings)
        try expect(result == "summary result", "AI response content")
    }
}
```

Update `makeItem` helper signature if needed so it can accept content:

```swift
static func makeItem(title: String, type: ClipboardContentType = .text, favorite: Bool = false, content: String? = nil) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        type: type,
        previewTitle: title,
        contentText: content ?? title,
        assetPath: nil,
        sourceAppName: nil,
        createdAt: Date(),
        lastUsedAt: Date(),
        isFavorite: favorite,
        contentHash: UUID().uuidString
    )
}
```

Add fake HTTP client near other fakes:

```swift
final class FakeAIHTTPClient: AIHTTPClient {
    var responseData: Data
    var statusCode: Int
    var lastRequest: URLRequest?
    var lastBody: Data?

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        lastBody = request.httpBody
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (responseData, response)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because `AIService`, `AIHTTPClient`, and `AIServiceError` do not exist.

- [ ] **Step 3: Add AIService implementation**

Create `Sources/FCatCore/AI/AIService.swift`:

```swift
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
    case httpStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Configure AI Base URL, API Key, and Model in Settings."
        case .unsupportedItem: return "AI actions only support text in this version."
        case .inputTooLong: return "Selected text is too long to send."
        case .invalidBaseURL: return "AI Base URL is invalid."
        case .httpStatus(let status): return "AI request failed with HTTP \(status)."
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
        guard action.supports(item), let input = item.contentText else { throw AIServiceError.unsupportedItem }
        guard input.count <= maxInputCharacters else { throw AIServiceError.inputTooLong }

        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/chat/completions") else { throw AIServiceError.invalidBaseURL }

        var request = URLRequest(url: url, timeoutInterval: settings.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: settings.model,
            messages: [ChatMessage(role: "user", content: action.prompt(for: input, defaultLanguage: settings.defaultLanguage))]
        ))

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw AIServiceError.httpStatus(response.statusCode) }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FCatCore/AI/AIService.swift Tests/FCatCoreTests/TestRunner.swift
git commit -m "feat: add AI service client"
```

---

### Task 5: Add direct text pasteboard writing

**Files:**
- Modify: `Sources/FCatCore/Pasteboard/PasteboardClient.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing pasteboard text write test**

In `main()`, add:

```swift
try testHistoryViewModelCopyAIResultWritesTextToPasteboard()
```

This test will compile after Task 6 adds `copyAIResult()`. Add it now:

```swift
static func testHistoryViewModelCopyAIResultWritesTextToPasteboard() throws {
    let pasteboard = WritableFakePasteboard()
    let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "source")]), pasteboard: pasteboard)
    viewModel.aiResult = "AI output"
    try viewModel.copyAIResult()
    try expect(pasteboard.writtenText == "AI output", "AI result written as text")
}
```

Update `WritableFakePasteboard` to include a failing stub requirement after the protocol changes:

```swift
var writtenText: String?
func writeText(_ text: String) throws { writtenText = text }
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because `PasteboardClient.writeText` and `HistoryPanelViewModel.copyAIResult` do not exist.

- [ ] **Step 3: Add writeText to PasteboardClient**

Modify `Sources/FCatCore/Pasteboard/PasteboardClient.swift` protocol:

```swift
public protocol PasteboardClient {
    func currentChangeCount() -> Int
    func readSnapshot() -> PasteboardSnapshot?
    func write(_ item: ClipboardItem) throws
    func writeText(_ text: String) throws
}
```

Add implementation to `SystemPasteboardClient`:

```swift
public func writeText(_ text: String) throws {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
```

Update all test fakes implementing `PasteboardClient` with:

```swift
func writeText(_ text: String) throws {}
```

For `WritableFakePasteboard`, store it:

```swift
var writtenText: String?
func writeText(_ text: String) throws { writtenText = text }
```

- [ ] **Step 4: Run tests and keep expected failure for ViewModel**

Run: `swift run FCatCoreTests`

Expected: FAIL only because `copyAIResult()` and `aiResult` are not added yet.

- [ ] **Step 5: Do not commit yet**

This task intentionally pairs with Task 6 because the test is red until ViewModel supports AI results.

---

### Task 6: Add AI state and execution to HistoryPanelViewModel

**Files:**
- Modify: `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift`
- Modify: `Tests/FCatCoreTests/TestRunner.swift`

- [ ] **Step 1: Add failing ViewModel AI tests**

In `main()`, add:

```swift
try testHistoryViewModelShowsUnsupportedMessageForImageAIAction()
try awaitTestHistoryViewModelRunsAIAction()
try testHistoryViewModelFormatsJSONLocally()
try testHistoryViewModelClearsAIResultWhenSelectionChanges()
```

Add tests:

```swift
static func testHistoryViewModelShowsUnsupportedMessageForImageAIAction() throws {
    let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "image", type: .image)]), pasteboard: WritableFakePasteboard())
    viewModel.openAIActions()
    try expect(viewModel.aiError == "AI actions only support text in this version.", "unsupported AI action message")
}

static func awaitTestHistoryViewModelRunsAIAction() throws {
    try runAsync {
        let aiService = FakeAIService(result: "summary")
        let settingsStore = StaticAISettingsStore(settings: AISettings(baseURL: "https://api.example.com/v1", model: "model", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "secret"))
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "source", content: "Hello")]), pasteboard: WritableFakePasteboard(), aiService: aiService, aiSettingsStore: settingsStore)
        await viewModel.runSelectedAIAction()
        try expect(viewModel.aiResult == "summary", "AI result state")
        try expect(!viewModel.aiLoading, "AI loading cleared")
    }
}

static func testHistoryViewModelFormatsJSONLocally() throws {
    let aiService = FakeAIService(result: "should not be used")
    let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "json", content: "{\"a\":1}")]), pasteboard: WritableFakePasteboard(), aiService: aiService)
    viewModel.selectedAIActionIndex = 4
    viewModel.runSelectedAIActionSynchronouslyForLocalActions()
    try expect(viewModel.aiResult?.contains("\"a\"") == true, "local JSON result")
    try expect(aiService.calls == 0, "JSON formatter skips AI service")
}

static func testHistoryViewModelClearsAIResultWhenSelectionChanges() throws {
    let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "one"), makeItem(title: "two")]), pasteboard: WritableFakePasteboard())
    viewModel.aiResult = "old"
    viewModel.moveSelection(delta: 1)
    try expect(viewModel.aiResult == nil, "selection change clears AI result")
}
```

Add fakes:

```swift
final class FakeAIService: AIServiceProtocol {
    var result: String
    var calls = 0

    init(result: String) { self.result = result }

    func run(action: AIAction, item: ClipboardItem, settings: AISettings) async throws -> String {
        calls += 1
        return result
    }
}

final class StaticAISettingsStore: AISettingsProviding {
    let settings: AISettings
    init(settings: AISettings) { self.settings = settings }
    func loadSettings() -> AISettings { settings }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run FCatCoreTests`

Expected: FAIL because ViewModel AI APIs and `AISettingsProviding` do not exist.

- [ ] **Step 3: Add settings provider protocol**

In `Sources/FCatCore/AI/AISettingsStore.swift`, add above `AISettingsStore`:

```swift
public protocol AISettingsProviding {
    func loadSettings() -> AISettings
}
```

Make `AISettingsStore` conform:

```swift
public final class AISettingsStore: AISettingsProviding {
```

- [ ] **Step 4: Add ViewModel AI state and dependencies**

Modify `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift`.

Add published properties after existing published properties:

```swift
@Published public var aiActionsVisible: Bool = false
@Published public var selectedAIActionIndex: Int = 0
@Published public var aiLoading: Bool = false
@Published public var aiResult: String?
@Published public var aiError: String?
```

Add dependencies:

```swift
private let aiService: AIServiceProtocol
private let aiSettingsStore: AISettingsProviding
```

Change initializer:

```swift
public init(
    store: HistoryStore,
    pasteboard: PasteboardClient,
    aiService: AIServiceProtocol = AIService(),
    aiSettingsStore: AISettingsProviding = AISettingsStore()
) {
    self.store = store
    self.pasteboard = pasteboard
    self.aiService = aiService
    self.aiSettingsStore = aiSettingsStore
}
```

Add computed selected item/action:

```swift
public var aiActions: [AIAction] { AIAction.builtIn }

public var selectedItem: ClipboardItem? {
    guard visibleItems.indices.contains(selectedIndex) else { return nil }
    return visibleItems[selectedIndex]
}

public var selectedAIAction: AIAction {
    aiActions[min(max(selectedAIActionIndex, 0), aiActions.count - 1)]
}
```

- [ ] **Step 5: Add ViewModel AI methods**

Add methods before `#if !DEBUG`:

```swift
public func openAIActions() {
    guard let selectedItem, selectedItem.type == .text else {
        aiActionsVisible = true
        aiError = AIServiceError.unsupportedItem.localizedDescription
        aiResult = nil
        return
    }
    aiActionsVisible = true
    aiError = nil
}

public func closeAIActions() {
    aiActionsVisible = false
}

public func moveAIActionSelection(delta: Int) {
    let maxIndex = max(aiActions.count - 1, 0)
    selectedAIActionIndex = min(max(selectedAIActionIndex + delta, 0), maxIndex)
}

@MainActor
public func runSelectedAIAction() async {
    guard !aiLoading, let selectedItem else { return }
    aiLoading = true
    aiResult = nil
    aiError = nil

    if selectedAIAction.id == AIAction.formatJSON.id {
        runSelectedAIActionSynchronouslyForLocalActions()
        aiLoading = false
        return
    }

    do {
        aiResult = try await aiService.run(action: selectedAIAction, item: selectedItem, settings: aiSettingsStore.loadSettings())
    } catch {
        aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    aiLoading = false
}

public func runSelectedAIActionSynchronouslyForLocalActions() {
    guard let selectedItem, let text = selectedItem.contentText else { return }
    if selectedAIAction.id == AIAction.formatJSON.id {
        do { aiResult = try JSONFormatter.format(text) }
        catch { aiError = "Selected text is not valid JSON." }
    }
}

public func copyAIResult() throws {
    guard let aiResult else { return }
    try pasteboard.writeText(aiResult)
}

private func clearAIOutput() {
    aiResult = nil
    aiError = nil
    aiLoading = false
}
```

Update `moveSelection(delta:)` to clear AI output when index changes:

```swift
public func moveSelection(delta: Int) {
    let oldIndex = selectedIndex
    let maxIndex = max(visibleItems.count - 1, 0)
    selectedIndex = min(max(selectedIndex + delta, 0), maxIndex)
    if selectedIndex != oldIndex { clearAIOutput() }
}
```

Update `select(index:)` similarly:

```swift
public func select(index: Int) {
    let oldIndex = selectedIndex
    let maxIndex = max(visibleItems.count - 1, 0)
    selectedIndex = min(max(index, 0), maxIndex)
    if selectedIndex != oldIndex { clearAIOutput() }
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 7: Commit Task 5 and Task 6 together**

```bash
git add Sources/FCatCore/Pasteboard/PasteboardClient.swift Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift Sources/FCatCore/AI/AISettingsStore.swift Tests/FCatCoreTests/TestRunner.swift
git commit -m "feat: add AI state to history view model"
```

---

### Task 7: Add AI settings UI

**Files:**
- Modify: `Sources/FCatCore/ViewModels/SettingsViewModel.swift`
- Modify: `Sources/FCatCore/Views/HotKeyRecorderView.swift`
- Modify: `Sources/FCat/AppDelegate.swift`

- [ ] **Step 1: Add settings ViewModel fields**

Modify `SettingsViewModel` to hold an AI settings store and published fields:

```swift
@Published public var aiBaseURL: String
@Published public var aiAPIKey: String
@Published public var aiModel: String
@Published public var aiDefaultLanguage: String
@Published public var aiTimeoutSeconds: Double
@Published public var aiSettingsMessage: String?
private let aiSettingsStore: AISettingsStore
```

Update initializer:

```swift
public init(defaults: UserDefaults = .standard, aiSettingsStore: AISettingsStore = AISettingsStore()) {
    self.defaults = defaults
    self.aiSettingsStore = aiSettingsStore
    self.hotKey = Self.load(defaults: defaults, key: key)
    let ai = aiSettingsStore.loadSettings()
    self.aiBaseURL = ai.baseURL
    self.aiAPIKey = ai.apiKey
    self.aiModel = ai.model
    self.aiDefaultLanguage = ai.defaultLanguage
    self.aiTimeoutSeconds = ai.timeoutSeconds
}
```

Add save method:

```swift
public func saveAISettings() {
    aiSettingsStore.save(baseURL: aiBaseURL, model: aiModel, defaultLanguage: aiDefaultLanguage, timeoutSeconds: aiTimeoutSeconds)
    do {
        try aiSettingsStore.saveAPIKey(aiAPIKey)
        aiSettingsMessage = "AI settings saved"
    } catch {
        aiSettingsMessage = "Failed to save API key"
    }
}
```

- [ ] **Step 2: Add AI controls to HotKeyRecorderView**

In `HotKeyRecorderView.body`, after the shortcut section, add a divider and settings fields:

```swift
Divider()

Text("AI Actions")
    .font(.title3.bold())

TextField("API Base URL", text: $viewModel.aiBaseURL)
    .textFieldStyle(.roundedBorder)

SecureField("API Key", text: $viewModel.aiAPIKey)
    .textFieldStyle(.roundedBorder)

TextField("Model", text: $viewModel.aiModel)
    .textFieldStyle(.roundedBorder)

HStack {
    TextField("Default Language", text: $viewModel.aiDefaultLanguage)
        .textFieldStyle(.roundedBorder)
    TextField("Timeout", value: $viewModel.aiTimeoutSeconds, format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)
}

HStack {
    Button("Save AI Settings") { viewModel.saveAISettings() }
    if let message = viewModel.aiSettingsMessage {
        Text(message)
            .font(.caption)
            .foregroundStyle(message.contains("Failed") ? .red : .green)
    }
}
```

Change frame size:

```swift
.frame(width: 520, height: 460)
```

- [ ] **Step 3: Enlarge settings window**

In `Sources/FCat/AppDelegate.swift`, change settings window size:

```swift
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
```

- [ ] **Step 4: Build to verify UI code compiles**

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Run tests**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FCatCore/ViewModels/SettingsViewModel.swift Sources/FCatCore/Views/HotKeyRecorderView.swift Sources/FCat/AppDelegate.swift
git commit -m "feat: add AI settings UI"
```

---

### Task 8: Add AI Actions UI to history panel

**Files:**
- Modify: `Sources/FCatCore/Views/HistoryPanelView.swift`
- Modify: `Sources/FCat/AppDelegate.swift`

- [ ] **Step 1: Pass AI dependencies from AppDelegate**

Add properties to `AppDelegate`:

```swift
private let aiSettingsStore = AISettingsStore()
private let aiService = AIService()
```

Change ViewModel creation:

```swift
let viewModel = HistoryPanelViewModel(store: store, pasteboard: pasteboard, aiService: aiService, aiSettingsStore: aiSettingsStore)
```

- [ ] **Step 2: Render AI action menu under search field**

In `HistoryPanelView`, after the search `TextField`, add:

```swift
if viewModel.aiActionsVisible {
    VStack(alignment: .leading, spacing: 4) {
        if let selected = viewModel.selectedItem, selected.type == .text {
            ForEach(Array(viewModel.aiActions.enumerated()), id: \.element.id) { index, action in
                HStack {
                    Text(action.title)
                    Spacer()
                    if index == viewModel.selectedAIActionIndex { Text("↩") }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(index == viewModel.selectedAIActionIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedAIActionIndex = index
                    Task { await viewModel.runSelectedAIAction() }
                }
            }
        } else {
            Text("AI actions only support text in this version")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
}
```

- [ ] **Step 3: Render AI result/error/loading in right preview**

In the right preview area, before normal selected-item content, add branches:

```swift
if viewModel.aiLoading {
    Text("Running AI action…")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else if let aiError = viewModel.aiError {
    Text(aiError)
        .foregroundStyle(.red)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
} else if let aiResult = viewModel.aiResult {
    ScrollView {
        Text(aiResult)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}
```

Keep the existing selected-item preview in the final `else` branch.

- [ ] **Step 4: Add key handling for AI actions**

In `installKeyMonitor()`, add these cases before the existing Return handling:

```swift
if keyCode == kVK_Tab || (keyCode == kVK_ANSI_K && modifiers.contains(.command)) {
    if viewModel.aiActionsVisible { viewModel.closeAIActions() }
    else { viewModel.openAIActions() }
    return nil
}

if viewModel.aiActionsVisible && keyCode == kVK_UpArrow {
    viewModel.moveAIActionSelection(delta: -1)
    return nil
}

if viewModel.aiActionsVisible && keyCode == kVK_DownArrow {
    viewModel.moveAIActionSelection(delta: 1)
    return nil
}

if viewModel.aiActionsVisible && keyCode == kVK_Return {
    Task { await viewModel.runSelectedAIAction() }
    return nil
}

if viewModel.aiResult != nil && keyCode == kVK_ANSI_C && modifiers.contains(.command) {
    try? viewModel.copyAIResult()
    return nil
}
```

Update existing Return handling so AI result takes priority:

```swift
if keyCode == kVK_Return && modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
    if viewModel.aiResult != nil {
        try? viewModel.copyAIResult()
        close()
        NSApp.hide(nil)
        #if !DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            viewModel.simulatePaste()
        }
        #endif
        return nil
    }
    // existing selected history item copy/paste logic remains here
}
```

Update Escape handling:

```swift
if keyCode == kVK_Escape {
    if viewModel.aiActionsVisible || viewModel.aiResult != nil || viewModel.aiError != nil {
        viewModel.closeAIActions()
        viewModel.aiResult = nil
        viewModel.aiError = nil
    } else {
        close()
    }
    return nil
}
```

- [ ] **Step 5: Build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 6: Run tests**

Run: `swift run FCatCoreTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/FCat/AppDelegate.swift Sources/FCatCore/Views/HistoryPanelView.swift
git commit -m "feat: add AI actions history UI"
```

---

### Task 9: Final verification and manual smoke test

**Files:**
- No code changes expected.

- [ ] **Step 1: Run full test suite**

Run: `swift run FCatCoreTests`

Expected: PASS and output includes `FCatCoreTests passed`.

- [ ] **Step 2: Build debug app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Build release app**

Run: `swift build -c release`

Expected: PASS.

- [ ] **Step 4: Manual smoke test in debug**

Run: `swift run FCat`

Expected manual checks:

- Settings window allows saving AI Base URL, API Key, Model, language, and timeout.
- Copy a text snippet in another app.
- Open FCat history panel.
- Select the text item.
- Press `Tab` and see AI Actions menu.
- Pick `Format JSON` on valid JSON and verify local formatted result appears without requiring network.
- Press `⌘C` and verify the AI result is copied.
- Select an image or file item and press `Tab`; verify unsupported text appears.

- [ ] **Step 5: Check git status**

Run: `git status --short`

Expected: clean, unless the final manual run changed local app support data outside the repo.

---

## Self-Review

- Spec coverage: The plan covers AI actions, settings, OpenAI-compatible calls, Keychain, non-text rejection, local JSON formatting, right-panel results, copy/paste, errors, tests, and verification.
- Placeholder scan: No `TBD`, `TODO`, vague edge handling, or missing test instructions remain.
- Type consistency: `AIAction`, `AISettings`, `AISettingsStore`, `AIServiceProtocol`, `AIHTTPClient`, `HistoryPanelViewModel` AI state, and `PasteboardClient.writeText` are consistently named across tasks.
