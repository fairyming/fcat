import AppKit
import Foundation
import FCatCore

@main
struct FCatCoreTestRunner {
    static func main() throws {
        try testClipboardItemCanBeConstructed()
        try testTextHashIsStable()
        try testTextHashChangesWhenContentChanges()
        try testFileHashUsesJoinedPathsInOrder()
        try testImageHashUsesData()
        try testClipboardCategoryIDsMatchRawValues()
        try testEmptyQueryMatchesWithZeroScore()
        try testContiguousMatchScoresHigherThanSpreadMatch()
        try testMissingCharactersDoNotMatch()
        try testCaseInsensitiveMatch()
        try testSearchFiltersFavoritesCategory()
        try testSearchFiltersImagesCategory()
        try testFavoritesSortBeforeNonFavoritesForSearch()
        try testTitleMatchBeatsBodyMatch()
        try testInsertedItemPersistsAcrossStoreInstances()
        try testDuplicateHashUpdatesExistingItemInsteadOfInserting()
        try testNonFavoriteHistoryIsCappedAtFiveHundred()
        try testFavoritesAreNotRemovedByHistoryCap()
        try testNonFavoriteImageCountIsCappedAtOneHundred()
        try testNonFavoriteImageBytesAreCapped()
        try testFavoriteImagesAreNotRemovedByImageCaps()
        try testTextChangeCreatesTextItem()
        try testWhitespaceOnlyTextDoesNotCreateTextItem()
        try testSameChangeCountDoesNotCreateItemTwice()
        try testFilePathsCreateFileItem()
        try testImageDataCreatesImageItemWithAssetPath()
        try testHistoryViewModelSearchFiltersItems()
        try testHistoryViewModelCategoryFiltersItems()
        try testHistoryViewModelMoveSelectionClampsToVisibleItems()
        try testHistoryViewModelCopySelectedWritesToPasteboard()
        try testAIActionsContainExpectedBuiltIns()
        try testAIActionSupportsOnlyTextItems()
        try testAIActionPromptUsesInputAndDefaultLanguage()
        try testAISettingsValidationRequiresBaseURLModelAndAPIKey()
        try testAISettingsStorePersistsNonSecretSettings()
        try testAISettingsStoreSaveAPIKeyRoundTrip()
        try testAISettingsWhitespaceOnlyIsIncomplete()
        try testJSONFormatterFormatsValidJSON()
        try testJSONFormatterRejectsInvalidJSON()
        try awaitTestAIServiceBuildsOpenAICompatibleRequest()
        try awaitTestAIServiceRejectsMissingConfiguration()
        try awaitTestAIServiceRejectsLongTextBeforeNetwork()
        try awaitTestAIServiceParsesSuccessfulResponse()
        print("FCatCoreTests passed")
    }

    static func testClipboardItemCanBeConstructed() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            type: .text,
            previewTitle: "Hello",
            contentText: "Hello world",
            assetPath: nil,
            sourceAppName: "Safari",
            createdAt: date,
            lastUsedAt: date,
            isFavorite: false,
            contentHash: "abc123"
        )

        try expect(item.type == .text, "item.type")
        try expect(item.previewTitle == "Hello", "item.previewTitle")
        try expect(item.contentText == "Hello world", "item.contentText")
        try expect(item.sourceAppName == "Safari", "item.sourceAppName")
        try expect(!item.isFavorite, "item.isFavorite")
    }

    static func testTextHashIsStable() throws {
        let first = ContentHasher.hashText("hello")
        let second = ContentHasher.hashText("hello")
        try expect(first == second, "text hash stable")
        try expect(first.count == 64, "text hash length")
    }

    static func testTextHashChangesWhenContentChanges() throws {
        try expect(ContentHasher.hashText("hello") != ContentHasher.hashText("hello!"), "text hash changes")
    }

    static func testFileHashUsesJoinedPathsInOrder() throws {
        let hash = ContentHasher.hashFilePaths(["/tmp/a.txt", "/tmp/b.txt"])
        try expect(hash == ContentHasher.hashFilePaths(["/tmp/a.txt", "/tmp/b.txt"]), "file hash stable")
        try expect(hash != ContentHasher.hashFilePaths(["/tmp/b.txt", "/tmp/a.txt"]), "file hash order")
    }

    static func testImageHashUsesData() throws {
        let data = Data([0, 1, 2, 3])
        try expect(ContentHasher.hashImagePNGData(data) == ContentHasher.hashImagePNGData(data), "image hash stable")
        try expect(ContentHasher.hashImagePNGData(data) != ContentHasher.hashImagePNGData(Data([3, 2, 1, 0])), "image hash changes")
    }

    static func testClipboardCategoryIDsMatchRawValues() throws {
        try expect(ClipboardCategory.all.id == "All", "all category id")
        try expect(ClipboardCategory.favorites.id == "Favorites", "favorites category id")
        try expect(ClipboardCategory.images.id == "Images", "images category id")
        try expect(ClipboardCategory.files.id == "Files", "files category id")
    }

    static func testEmptyQueryMatchesWithZeroScore() throws {
        try expect(FuzzyMatcher.score(query: "", candidate: "hello") == 0, "empty fuzzy query")
    }

    static func testContiguousMatchScoresHigherThanSpreadMatch() throws {
        let contiguous = FuzzyMatcher.score(query: "cat", candidate: "clipboard cat") ?? -1
        let spread = FuzzyMatcher.score(query: "cat", candidate: "c-l-i-p-b-o-a-r-d a t") ?? -1
        try expect(contiguous > spread, "contiguous fuzzy score")
    }

    static func testMissingCharactersDoNotMatch() throws {
        try expect(FuzzyMatcher.score(query: "xyz", candidate: "clipboard") == nil, "missing fuzzy chars")
    }

    static func testCaseInsensitiveMatch() throws {
        try expect(FuzzyMatcher.score(query: "clip", candidate: "Clipboard History") != nil, "case insensitive fuzzy match")
    }

    static func testSearchFiltersFavoritesCategory() throws {
        let items = [makeItem(title: "normal", favorite: false), makeItem(title: "fav", favorite: true)]
        let results = SearchService.search(items: items, query: "", category: .favorites)
        try expect(results.map(\.previewTitle) == ["fav"], "favorites category filter")
    }

    static func testSearchFiltersImagesCategory() throws {
        let items = [makeItem(title: "text", type: .text), makeItem(title: "image", type: .image)]
        let results = SearchService.search(items: items, query: "", category: .images)
        try expect(results.map(\.type) == [.image], "images category filter")
    }

    static func testFavoritesSortBeforeNonFavoritesForSearch() throws {
        let items = [
            makeItem(title: "cat normal", favorite: false, lastUsedOffset: 20),
            makeItem(title: "cat favorite", favorite: true, lastUsedOffset: 1)
        ]
        let results = SearchService.search(items: items, query: "cat", category: .all)
        try expect(results.first?.previewTitle == "cat favorite", "favorite search priority")
    }

    static func testTitleMatchBeatsBodyMatch() throws {
        let items = [
            makeItem(title: "notes", text: "cat appears in body", lastUsedOffset: 20),
            makeItem(title: "cat title", text: "body", lastUsedOffset: 1)
        ]
        let results = SearchService.search(items: items, query: "cat", category: .all)
        try expect(results.first?.previewTitle == "cat title", "title search priority")
    }

    static func testInsertedItemPersistsAcrossStoreInstances() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = makeItem(title: "item-1", hash: "hash-1")
        try makeStore(directory: directory).upsert(item)
        let second = try makeStore(directory: directory)
        let ids = try second.fetchAll().map(\.id)
        try expect(ids == [item.id], "store persistence")
    }

    static func testDuplicateHashUpdatesExistingItemInsteadOfInserting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory)
        let first = makeItem(title: "First", hash: "same")
        let second = makeItem(title: "Updated", hash: "same")
        try store.upsert(first)
        try store.upsert(second)
        let all = try store.fetchAll()
        try expect(all.count == 1, "duplicate hash count")
        try expect(all[0].previewTitle == "Updated", "duplicate hash update")
    }

    static func testNonFavoriteHistoryIsCappedAtFiveHundred() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory)
        for index in 0..<501 { try store.upsert(makeItem(title: "item-\(index)", hash: "hash-\(index)", lastUsedOffset: TimeInterval(index))) }
        let all = try store.fetchAll()
        try expect(all.count == 500, "history cap count")
        try expect(!all.contains { $0.previewTitle == "item-0" }, "history cap removes oldest")
    }

    static func testFavoritesAreNotRemovedByHistoryCap() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory)
        try store.upsert(makeItem(title: "favorite", favorite: true, hash: "favorite", lastUsedOffset: -1))
        for index in 0..<501 { try store.upsert(makeItem(title: "item-\(index)", hash: "hash-\(index)", lastUsedOffset: TimeInterval(index))) }
        let all = try store.fetchAll()
        try expect(all.count == 501, "favorites not capped count")
        try expect(all.contains { $0.previewTitle == "favorite" && $0.isFavorite }, "favorite preserved")
    }

    static func testNonFavoriteImageCountIsCappedAtOneHundred() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory)
        for index in 0..<101 {
            let assetURL = directory.appendingPathComponent("image-\(index).png")
            try Data(repeating: UInt8(index % 255), count: 10).write(to: assetURL)
            try store.upsert(makeItem(title: "image-\(index)", type: .image, hash: "image-hash-\(index)", assetPath: assetURL.path, lastUsedOffset: TimeInterval(index)))
        }
        let images = try store.fetchAll().filter { $0.type == .image }
        try expect(images.count == 100, "image count cap")
        try expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("image-0.png").path), "oldest image asset removed")
    }

    static func testNonFavoriteImageBytesAreCapped() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory, imageByteLimit: 100)
        for index in 0..<3 {
            let assetURL = directory.appendingPathComponent("large-\(index).png")
            try Data(repeating: UInt8(index), count: 60).write(to: assetURL)
            try store.upsert(makeItem(title: "large-\(index)", type: .image, hash: "large-hash-\(index)", assetPath: assetURL.path, lastUsedOffset: TimeInterval(index)))
        }
        let images = try store.fetchAll().filter { $0.type == .image }
        try expect(images.count == 1, "image byte cap count")
        try expect(images.first?.previewTitle == "large-2", "image byte cap keeps newest")
    }

    static func testFavoriteImagesAreNotRemovedByImageCaps() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore(directory: directory, imageCountLimit: 1, imageByteLimit: 10)
        let favoriteURL = directory.appendingPathComponent("favorite.png")
        try Data(repeating: 1, count: 100).write(to: favoriteURL)
        try store.upsert(makeItem(title: "favorite-image", type: .image, favorite: true, hash: "favorite-image", assetPath: favoriteURL.path))
        let normalURL = directory.appendingPathComponent("normal.png")
        try Data(repeating: 2, count: 100).write(to: normalURL)
        try store.upsert(makeItem(title: "normal-image", type: .image, hash: "normal-image", assetPath: normalURL.path))
        let all = try store.fetchAll()
        try expect(all.contains { $0.isFavorite && $0.assetPath == favoriteURL.path }, "favorite image preserved")
    }

    static func testTextChangeCreatesTextItem() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .text("hello world"))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: { Date(timeIntervalSince1970: 10) })
        try monitor.pollOnce()
        try expect(sink.items.count == 1, "text monitor item count")
        try expect(sink.items[0].type == .text, "text monitor type")
        try expect(sink.items[0].previewTitle == "hello world", "text monitor preview")
        try expect(sink.items[0].contentText == "hello world", "text monitor content")
    }

    static func testWhitespaceOnlyTextDoesNotCreateTextItem() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString(" \n\t", forType: .string)
        let client = SystemPasteboardClient(pasteboard: pasteboard)
        try expect(client.readSnapshot() == nil, "whitespace-only clipboard text ignored")
    }

    static func testSameChangeCountDoesNotCreateItemTwice() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .text("hello"))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: Date.init)
        try monitor.pollOnce()
        try monitor.pollOnce()
        try expect(sink.items.count == 1, "same change count ignored")
    }

    static func testFilePathsCreateFileItem() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .files(["/tmp/a.txt", "/tmp/b.txt"]))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: Date.init)
        try monitor.pollOnce()
        try expect(sink.items[0].type == .file, "file monitor type")
        try expect(sink.items[0].previewTitle == "a.txt, b.txt", "file monitor preview")
        try expect(sink.items[0].contentText == "/tmp/a.txt\n/tmp/b.txt", "file monitor content")
    }

    static func testImageDataCreatesImageItemWithAssetPath() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .imagePNG(Data([1, 2, 3])))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, imageSaver: { _, id in "/tmp/\(id.uuidString).png" }, now: Date.init)
        try monitor.pollOnce()
        try expect(sink.items[0].type == .image, "image monitor type")
        try expect(sink.items[0].assetPath != nil, "image monitor asset path")
    }

    static func testHistoryViewModelSearchFiltersItems() throws {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "alpha cat"), makeItem(title: "beta dog")]), pasteboard: WritableFakePasteboard())
        viewModel.query = "cat"
        try expect(viewModel.visibleItems.map(\.previewTitle) == ["alpha cat"], "view model search filter")
    }

    static func testHistoryViewModelCategoryFiltersItems() throws {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "text", type: .text), makeItem(title: "image", type: .image)]), pasteboard: WritableFakePasteboard())
        viewModel.category = .images
        try expect(viewModel.visibleItems.map(\.type) == [.image], "view model category filter")
    }

    static func testHistoryViewModelMoveSelectionClampsToVisibleItems() throws {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "one"), makeItem(title: "two")]), pasteboard: WritableFakePasteboard())
        viewModel.moveSelection(delta: 1)
        viewModel.moveSelection(delta: 1)
        viewModel.moveSelection(delta: 1)
        try expect(viewModel.selectedIndex == 1, "selection clamp upper")
        viewModel.moveSelection(delta: -3)
        try expect(viewModel.selectedIndex == 0, "selection clamp lower")
    }

    static func testHistoryViewModelCopySelectedWritesToPasteboard() throws {
        let pasteboard = WritableFakePasteboard()
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [makeItem(title: "one")]), pasteboard: pasteboard)
        try viewModel.copySelected()
        try expect(pasteboard.written.first?.previewTitle == "one", "copy selected writes pasteboard")
    }

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

    static func testAISettingsStoreSaveAPIKeyRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "FCatTests.AISettings.APIKey")!
        defaults.removePersistentDomain(forName: "FCatTests.AISettings.APIKey")

        let keychain = InMemoryAPIKeyStore()
        let store = AISettingsStore(defaults: defaults, keychain: keychain)
        try store.saveAPIKey("secret")

        let loaded = store.loadSettings()
        try expect(loaded.apiKey == "secret", "saveAPIKey round trip")
    }

    static func testAISettingsWhitespaceOnlyIsIncomplete() throws {
        let whitespaceSettings = AISettings(baseURL: "  ", model: "  ", defaultLanguage: "中文", timeoutSeconds: 30, apiKey: "  ")
        try expect(!whitespaceSettings.isComplete, "whitespace-only AI settings are incomplete")
    }

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

    static func awaitTestAIServiceBuildsOpenAICompatibleRequest() throws {
        try runAsync {
            let client = FakeAIHTTPClient(responseData: Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8), statusCode: 200)
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
            let client = FakeAIHTTPClient(responseData: Data("{\"choices\":[{\"message\":{\"content\":\"summary result\"}}]}".utf8), statusCode: 200)
            let service = AIService(httpClient: client)
            let settings = AISettings(baseURL: "https://api.example.com/v1", model: "model-a", defaultLanguage: "中文", timeoutSeconds: 10, apiKey: "secret")
            let result = try await service.run(action: .summarize, item: makeItem(title: "hello", content: "Hello"), settings: settings)
            try expect(result == "summary result", "AI response content")
        }
    }

    static func makeStore(directory: URL, imageCountLimit: Int = 100, imageByteLimit: Int64 = 500 * 1024 * 1024) throws -> ClipboardStore {
        try ClipboardStore(databaseURL: directory.appendingPathComponent("history.sqlite"), imageCountLimit: imageCountLimit, imageByteLimit: imageByteLimit)
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeItem(title: String, type: ClipboardContentType = .text, text: String? = nil, content: String? = nil, favorite: Bool = false, hash: String? = nil, assetPath: String? = nil, lastUsedOffset: TimeInterval = 0) -> ClipboardItem {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        return ClipboardItem(
            id: UUID(),
            type: type,
            previewTitle: title,
            contentText: content ?? text ?? title,
            assetPath: assetPath,
            sourceAppName: nil,
            createdAt: baseDate.addingTimeInterval(lastUsedOffset),
            lastUsedAt: baseDate.addingTimeInterval(lastUsedOffset),
            isFavorite: favorite,
            contentHash: hash ?? UUID().uuidString
        )
    }
}

final class CapturingSink: ClipboardItemSink {
    var items: [ClipboardItem] = []
    func ingest(_ item: ClipboardItem) throws { items.append(item) }
}

struct FakePasteboard: PasteboardClient {
    var changeCount: Int
    var snapshot: PasteboardSnapshot?
    func currentChangeCount() -> Int { changeCount }
    func readSnapshot() -> PasteboardSnapshot? { snapshot }
    func write(_ item: ClipboardItem) throws {}
}

final class WritableFakePasteboard: PasteboardClient {
    var written: [ClipboardItem] = []
    func currentChangeCount() -> Int { 0 }
    func readSnapshot() -> PasteboardSnapshot? { nil }
    func write(_ item: ClipboardItem) throws { written.append(item) }
}

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.failed(message) }
}

final class InMemoryAPIKeyStore: APIKeyStore {
    var value = ""

    func loadAPIKey() -> String { value }
    func saveAPIKey(_ apiKey: String) throws { value = apiKey }
}

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
