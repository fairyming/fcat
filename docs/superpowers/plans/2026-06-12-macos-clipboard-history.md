# macOS Clipboard History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar clipboard history app with user-defined global hotkey, persistent text/image/file history, fuzzy search, categories, favorites, and retention limits.

**Architecture:** Use a Swift Package with a testable `FCatCore` library and a small `FCat` executable target. Core owns models, hashing, persistence, search, retention, pasteboard monitoring, and view models; the executable owns AppKit/SwiftUI menu bar wiring, windows, and app lifecycle.

**Tech Stack:** Swift 5.9+, macOS 13+, SwiftUI, AppKit, SQLite3, XCTest, CryptoKit, Carbon global hotkeys.

---

## File Structure

Create these files:

- `Package.swift` — SwiftPM package definition with `FCatCore`, `FCat`, and `FCatCoreTests`.
- `Sources/FCat/main.swift` — starts the AppKit application.
- `Sources/FCat/AppDelegate.swift` — creates menu bar item, services, windows, and app menu actions.
- `Sources/FCatCore/Models/ClipboardItem.swift` — clipboard item type and content enum.
- `Sources/FCatCore/Models/ClipboardCategory.swift` — category filter enum.
- `Sources/FCatCore/Models/HotKey.swift` — serializable hotkey model.
- `Sources/FCatCore/Hashing/ContentHasher.swift` — SHA-256 hashing for text, files, and PNG image data.
- `Sources/FCatCore/Search/FuzzyMatcher.swift` — local fuzzy scoring and matching.
- `Sources/FCatCore/Search/SearchService.swift` — category filtering and result ordering.
- `Sources/FCatCore/Storage/SQLiteDatabase.swift` — small SQLite wrapper.
- `Sources/FCatCore/Storage/ImageAssetStore.swift` — stores and deletes image files under App Support.
- `Sources/FCatCore/Storage/ClipboardStore.swift` — SQLite-backed history persistence and retention.
- `Sources/FCatCore/Pasteboard/PasteboardClient.swift` — protocol plus system pasteboard implementation.
- `Sources/FCatCore/Pasteboard/ClipboardMonitor.swift` — pasteboard polling and item ingestion.
- `Sources/FCatCore/HotKeys/GlobalHotKeyManager.swift` — Carbon hotkey registration and callback.
- `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift` — panel state and actions.
- `Sources/FCatCore/ViewModels/SettingsViewModel.swift` — first-run hotkey state.
- `Sources/FCatCore/Views/HistoryPanelView.swift` — SwiftUI history panel.
- `Sources/FCatCore/Views/SettingsView.swift` — SwiftUI first-run/settings view.
- `Tests/FCatCoreTests/ContentHasherTests.swift`
- `Tests/FCatCoreTests/FuzzyMatcherTests.swift`
- `Tests/FCatCoreTests/SearchServiceTests.swift`
- `Tests/FCatCoreTests/ClipboardStoreTests.swift`
- `Tests/FCatCoreTests/ClipboardMonitorTests.swift`
- `Tests/FCatCoreTests/HistoryPanelViewModelTests.swift`

Because the current directory is not a git repository, commit steps are written as local checkpoints. If a git repo is initialized before execution, replace each checkpoint with the listed `git add` and `git commit` command.

---

### Task 1: Bootstrap Swift package and app shell

**Files:**
- Create: `Package.swift`
- Create: `Sources/FCat/main.swift`
- Create: `Sources/FCat/AppDelegate.swift`
- Create: `Sources/FCatCore/Models/ClipboardItem.swift`
- Create: `Tests/FCatCoreTests/BootstrapTests.swift`

- [ ] **Step 1: Write the first failing test**

Create `Tests/FCatCoreTests/BootstrapTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class BootstrapTests: XCTestCase {
    func testClipboardItemCanBeConstructed() {
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

        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.previewTitle, "Hello")
        XCTAssertEqual(item.contentText, "Hello world")
        XCTAssertEqual(item.sourceAppName, "Safari")
        XCTAssertFalse(item.isFavorite)
    }
}
```

- [ ] **Step 2: Run test to verify package is missing**

Run:

```bash
swift test
```

Expected: FAIL because `Package.swift` does not exist.

- [ ] **Step 3: Create package and minimal model**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FCat",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FCatCore", targets: ["FCatCore"]),
        .executable(name: "FCat", targets: ["FCat"])
    ],
    targets: [
        .target(
            name: "FCatCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "FCat",
            dependencies: ["FCatCore"]
        ),
        .testTarget(
            name: "FCatCoreTests",
            dependencies: ["FCatCore"]
        )
    ]
)
```

Create `Sources/FCatCore/Models/ClipboardItem.swift`:

```swift
import Foundation

public enum ClipboardContentType: String, Codable, CaseIterable, Equatable {
    case text
    case image
    case file
}

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: ClipboardContentType
    public var previewTitle: String
    public var contentText: String?
    public var assetPath: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var isFavorite: Bool
    public let contentHash: String

    public init(
        id: UUID,
        type: ClipboardContentType,
        previewTitle: String,
        contentText: String?,
        assetPath: String?,
        sourceAppName: String?,
        createdAt: Date,
        lastUsedAt: Date,
        isFavorite: Bool,
        contentHash: String
    ) {
        self.id = id
        self.type = type
        self.previewTitle = previewTitle
        self.contentText = contentText
        self.assetPath = assetPath
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
        self.contentHash = contentHash
    }
}
```

Create `Sources/FCat/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

Create `Sources/FCat/AppDelegate.swift`:

```swift
import AppKit
import FCatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "F"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openHistory() {}
    @objc private func openSettings() {}
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 4: Run test and build app shell**

Run:

```bash
swift test && swift build
```

Expected: PASS for `BootstrapTests`; build completes.

- [ ] **Step 5: Checkpoint**

If this is a git repo, run:

```bash
git add Package.swift Sources Tests
git commit -m "chore: bootstrap macOS clipboard app"
```

Otherwise record checkpoint: package builds and the minimal menu bar executable compiles.

---

### Task 2: Add hashing and category models

**Files:**
- Create: `Sources/FCatCore/Models/ClipboardCategory.swift`
- Create: `Sources/FCatCore/Hashing/ContentHasher.swift`
- Create: `Tests/FCatCoreTests/ContentHasherTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/FCatCoreTests/ContentHasherTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class ContentHasherTests: XCTestCase {
    func testTextHashIsStable() {
        let first = ContentHasher.hashText("hello")
        let second = ContentHasher.hashText("hello")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    func testTextHashChangesWhenContentChanges() {
        XCTAssertNotEqual(ContentHasher.hashText("hello"), ContentHasher.hashText("hello!"))
    }

    func testFileHashUsesJoinedPathsInOrder() {
        let hash = ContentHasher.hashFilePaths(["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(hash, ContentHasher.hashFilePaths(["/tmp/a.txt", "/tmp/b.txt"]))
        XCTAssertNotEqual(hash, ContentHasher.hashFilePaths(["/tmp/b.txt", "/tmp/a.txt"]))
    }

    func testImageHashUsesData() {
        let data = Data([0, 1, 2, 3])
        XCTAssertEqual(ContentHasher.hashImagePNGData(data), ContentHasher.hashImagePNGData(data))
        XCTAssertNotEqual(ContentHasher.hashImagePNGData(data), ContentHasher.hashImagePNGData(Data([3, 2, 1, 0])))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter ContentHasherTests
```

Expected: FAIL because `ContentHasher` does not exist.

- [ ] **Step 3: Implement category and hasher**

Create `Sources/FCatCore/Models/ClipboardCategory.swift`:

```swift
import Foundation

public enum ClipboardCategory: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case favorites = "Favorites"
    case images = "Images"
    case files = "Files"

    public var id: String { rawValue }
}
```

Create `Sources/FCatCore/Hashing/ContentHasher.swift`:

```swift
import CryptoKit
import Foundation

public enum ContentHasher {
    public static func hashText(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    public static func hashFilePaths(_ paths: [String]) -> String {
        sha256(Data(paths.joined(separator: "\n").utf8))
    }

    public static func hashImagePNGData(_ data: Data) -> String {
        sha256(data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter ContentHasherTests
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Models/ClipboardCategory.swift Sources/FCatCore/Hashing/ContentHasher.swift Tests/FCatCoreTests/ContentHasherTests.swift
git commit -m "feat: add clipboard content hashing"
```

Otherwise record checkpoint: hashing and categories pass tests.

---

### Task 3: Add fuzzy search and sorting

**Files:**
- Create: `Sources/FCatCore/Search/FuzzyMatcher.swift`
- Create: `Sources/FCatCore/Search/SearchService.swift`
- Create: `Tests/FCatCoreTests/FuzzyMatcherTests.swift`
- Create: `Tests/FCatCoreTests/SearchServiceTests.swift`

- [ ] **Step 1: Write failing fuzzy matcher tests**

Create `Tests/FCatCoreTests/FuzzyMatcherTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesWithZeroScore() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", candidate: "hello"), 0)
    }

    func testContiguousMatchScoresHigherThanSpreadMatch() {
        let contiguous = FuzzyMatcher.score(query: "cat", candidate: "clipboard cat")
        let spread = FuzzyMatcher.score(query: "cat", candidate: "c-l-i-p-b-o-a-r-d a t")
        XCTAssertGreaterThan(contiguous, spread)
    }

    func testMissingCharactersDoNotMatch() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "clipboard"))
    }

    func testCaseInsensitiveMatch() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "clip", candidate: "Clipboard History"))
    }
}
```

- [ ] **Step 2: Write failing search service tests**

Create `Tests/FCatCoreTests/SearchServiceTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class SearchServiceTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testFiltersFavoritesCategory() {
        let items = [
            item(title: "normal", favorite: false),
            item(title: "fav", favorite: true)
        ]

        let results = SearchService.search(items: items, query: "", category: .favorites)
        XCTAssertEqual(results.map(\.previewTitle), ["fav"])
    }

    func testFiltersImagesCategory() {
        let items = [
            item(title: "text", type: .text),
            item(title: "image", type: .image)
        ]

        let results = SearchService.search(items: items, query: "", category: .images)
        XCTAssertEqual(results.map(\.type), [.image])
    }

    func testFavoritesSortBeforeNonFavoritesForSearch() {
        let items = [
            item(title: "cat normal", favorite: false, lastUsedOffset: 20),
            item(title: "cat favorite", favorite: true, lastUsedOffset: 1)
        ]

        let results = SearchService.search(items: items, query: "cat", category: .all)
        XCTAssertEqual(results.first?.previewTitle, "cat favorite")
    }

    func testTitleMatchBeatsBodyMatch() {
        let items = [
            item(title: "notes", text: "cat appears in body", lastUsedOffset: 20),
            item(title: "cat title", text: "body", lastUsedOffset: 1)
        ]

        let results = SearchService.search(items: items, query: "cat", category: .all)
        XCTAssertEqual(results.first?.previewTitle, "cat title")
    }

    private func item(
        title: String,
        type: ClipboardContentType = .text,
        text: String? = nil,
        favorite: Bool = false,
        lastUsedOffset: TimeInterval = 0
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: type,
            previewTitle: title,
            contentText: text ?? title,
            assetPath: nil,
            sourceAppName: nil,
            createdAt: baseDate.addingTimeInterval(lastUsedOffset),
            lastUsedAt: baseDate.addingTimeInterval(lastUsedOffset),
            isFavorite: favorite,
            contentHash: UUID().uuidString
        )
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
swift test --filter FuzzyMatcherTests && swift test --filter SearchServiceTests
```

Expected: FAIL because search types do not exist.

- [ ] **Step 4: Implement fuzzy matcher and search service**

Create `Sources/FCatCore/Search/FuzzyMatcher.swift`:

```swift
import Foundation

public enum FuzzyMatcher {
    public static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased())
        if q.isEmpty { return 0 }

        let c = Array(candidate.lowercased())
        var queryIndex = 0
        var score = 0
        var previousMatchIndex: Int?

        for candidateIndex in c.indices {
            if c[candidateIndex] == q[queryIndex] {
                score += 10
                if let previousMatchIndex {
                    score += max(0, 8 - (candidateIndex - previousMatchIndex - 1))
                }
                if candidateIndex == 0 || c[candidateIndex - 1].isWhitespace || c[candidateIndex - 1] == "/" || c[candidateIndex - 1] == "-" || c[candidateIndex - 1] == "_" {
                    score += 5
                }
                previousMatchIndex = candidateIndex
                queryIndex += 1
                if queryIndex == q.count { return score }
            }
        }

        return nil
    }
}
```

Create `Sources/FCatCore/Search/SearchService.swift`:

```swift
import Foundation

public enum SearchService {
    public static func search(items: [ClipboardItem], query: String, category: ClipboardCategory) -> [ClipboardItem] {
        let filtered = items.filter { item in
            switch category {
            case .all:
                return true
            case .favorites:
                return item.isFavorite
            case .images:
                return item.type == .image
            case .files:
                return item.type == .file
            }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return filtered.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
                return lhs.createdAt > rhs.createdAt
            }
        }

        return filtered.compactMap { item -> (ClipboardItem, Int)? in
            let titleScore = FuzzyMatcher.score(query: trimmedQuery, candidate: item.previewTitle).map { $0 + 1_000 }
            let bodyScore = item.contentText.flatMap { FuzzyMatcher.score(query: trimmedQuery, candidate: $0) }
            guard let score = [titleScore, bodyScore].compactMap({ $0 }).max() else { return nil }
            return (item, score)
        }
        .sorted { lhs, rhs in
            if lhs.0.isFavorite != rhs.0.isFavorite { return lhs.0.isFavorite && !rhs.0.isFavorite }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.lastUsedAt != rhs.0.lastUsedAt { return lhs.0.lastUsedAt > rhs.0.lastUsedAt }
            return lhs.0.createdAt > rhs.0.createdAt
        }
        .map(\.0)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter FuzzyMatcherTests && swift test --filter SearchServiceTests
```

Expected: PASS.

- [ ] **Step 6: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Search Tests/FCatCoreTests/FuzzyMatcherTests.swift Tests/FCatCoreTests/SearchServiceTests.swift
git commit -m "feat: add fuzzy clipboard search"
```

Otherwise record checkpoint: fuzzy search and sorting pass tests.

---

### Task 4: Add SQLite persistence and retention

**Files:**
- Create: `Sources/FCatCore/Storage/SQLiteDatabase.swift`
- Create: `Sources/FCatCore/Storage/ImageAssetStore.swift`
- Create: `Sources/FCatCore/Storage/ClipboardStore.swift`
- Create: `Tests/FCatCoreTests/ClipboardStoreTests.swift`

- [ ] **Step 1: Write failing persistence and retention tests**

Create `Tests/FCatCoreTests/ClipboardStoreTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class ClipboardStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testInsertedItemPersistsAcrossStoreInstances() throws {
        let first = try makeStore()
        let item = makeItem(index: 1, type: .text)
        try first.upsert(item)

        let second = try makeStore()
        XCTAssertEqual(try second.fetchAll().map(\.id), [item.id])
    }

    func testDuplicateHashUpdatesExistingItemInsteadOfInserting() throws {
        let store = try makeStore()
        let first = makeItem(index: 1, hash: "same")
        var second = makeItem(index: 2, hash: "same")
        second.previewTitle = "Updated"

        try store.upsert(first)
        try store.upsert(second)

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].previewTitle, "Updated")
    }

    func testNonFavoriteHistoryIsCappedAtFiveHundred() throws {
        let store = try makeStore()
        for index in 0..<501 {
            try store.upsert(makeItem(index: index, type: .text, favorite: false))
        }

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 500)
        XCTAssertFalse(all.contains { $0.previewTitle == "item-0" })
    }

    func testFavoritesAreNotRemovedByHistoryCap() throws {
        let store = try makeStore()
        try store.upsert(makeItem(index: -1, type: .text, favorite: true))
        for index in 0..<501 {
            try store.upsert(makeItem(index: index, type: .text, favorite: false))
        }

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 501)
        XCTAssertTrue(all.contains { $0.previewTitle == "item--1" && $0.isFavorite })
    }

    func testNonFavoriteImageCountIsCappedAtOneHundred() throws {
        let store = try makeStore()
        for index in 0..<101 {
            let assetURL = tempDirectory.appendingPathComponent("image-\(index).png")
            try Data(repeating: UInt8(index % 255), count: 10).write(to: assetURL)
            try store.upsert(makeItem(index: index, type: .image, assetPath: assetURL.path))
        }

        let images = try store.fetchAll().filter { $0.type == .image }
        XCTAssertEqual(images.count, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("image-0.png").path))
    }

    func testNonFavoriteImageBytesAreCappedAtFiveHundredMegabytes() throws {
        let store = try makeStore(imageByteLimit: 100)
        for index in 0..<3 {
            let assetURL = tempDirectory.appendingPathComponent("large-\(index).png")
            try Data(repeating: UInt8(index), count: 60).write(to: assetURL)
            try store.upsert(makeItem(index: index, type: .image, assetPath: assetURL.path))
        }

        let images = try store.fetchAll().filter { $0.type == .image }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.previewTitle, "item-2")
    }

    func testFavoriteImagesAreNotRemovedByImageCaps() throws {
        let store = try makeStore(imageCountLimit: 1, imageByteLimit: 10)
        let favoriteURL = tempDirectory.appendingPathComponent("favorite.png")
        try Data(repeating: 1, count: 100).write(to: favoriteURL)
        try store.upsert(makeItem(index: 1, type: .image, favorite: true, assetPath: favoriteURL.path))

        let normalURL = tempDirectory.appendingPathComponent("normal.png")
        try Data(repeating: 2, count: 100).write(to: normalURL)
        try store.upsert(makeItem(index: 2, type: .image, favorite: false, assetPath: normalURL.path))

        let all = try store.fetchAll()
        XCTAssertTrue(all.contains { $0.isFavorite && $0.assetPath == favoriteURL.path })
    }

    private func makeStore(imageCountLimit: Int = 100, imageByteLimit: Int64 = 500 * 1024 * 1024) throws -> ClipboardStore {
        let dbURL = tempDirectory.appendingPathComponent("history.sqlite")
        return try ClipboardStore(databaseURL: dbURL, imageCountLimit: imageCountLimit, imageByteLimit: imageByteLimit)
    }

    private func makeItem(
        index: Int,
        type: ClipboardContentType = .text,
        favorite: Bool = false,
        hash: String? = nil,
        assetPath: String? = nil
    ) -> ClipboardItem {
        let date = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
        return ClipboardItem(
            id: UUID(),
            type: type,
            previewTitle: "item-\(index)",
            contentText: type == .file ? "/tmp/item-\(index)" : "content-\(index)",
            assetPath: assetPath,
            sourceAppName: nil,
            createdAt: date,
            lastUsedAt: date,
            isFavorite: favorite,
            contentHash: hash ?? "hash-\(index)"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter ClipboardStoreTests
```

Expected: FAIL because store types do not exist.

- [ ] **Step 3: Implement SQLite wrapper**

Create `Sources/FCatCore/Storage/SQLiteDatabase.swift`:

```swift
import Foundation
import SQLite3

public final class SQLiteDatabase {
    private var db: OpaquePointer?

    public init(url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw SQLiteError.open(message)
        }
    }

    deinit { sqlite3_close(db) }

    public func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_DONE {
            throw SQLiteError.step(message)
        }
    }

    public func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_NULL:
                    row[name] = .null
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepare(message)
        }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private var message: String { String(cString: sqlite3_errmsg(db)) }
}

public enum SQLiteBinding {
    case text(String)
    case int(Int64)
    case null
}

public enum SQLiteValue: Equatable {
    case text(String)
    case integer(Int64)
    case null

    public var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var int64: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}

public enum SQLiteError: Error, Equatable {
    case open(String)
    case prepare(String)
    case step(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

- [ ] **Step 4: Implement image asset deletion helper**

Create `Sources/FCatCore/Storage/ImageAssetStore.swift`:

```swift
import Foundation

public final class ImageAssetStore {
    private let fileManager: FileManager
    public let directory: URL

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func savePNGData(_ data: Data, id: UUID) throws -> String {
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    public func removeAsset(at path: String?) {
        guard let path, fileManager.fileExists(atPath: path) else { return }
        try? fileManager.removeItem(atPath: path)
    }

    public func byteSize(at path: String?) -> Int64 {
        guard let path else { return 0 }
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64 ?? 0
    }
}
```

- [ ] **Step 5: Implement clipboard store**

Create `Sources/FCatCore/Storage/ClipboardStore.swift`:

```swift
import Foundation

public final class ClipboardStore {
    private let database: SQLiteDatabase
    private let imageCountLimit: Int
    private let imageByteLimit: Int64
    private let fileManager: FileManager

    public init(
        databaseURL: URL,
        imageCountLimit: Int = 100,
        imageByteLimit: Int64 = 500 * 1024 * 1024,
        fileManager: FileManager = .default
    ) throws {
        self.database = try SQLiteDatabase(url: databaseURL)
        self.imageCountLimit = imageCountLimit
        self.imageByteLimit = imageByteLimit
        self.fileManager = fileManager
        try migrate()
    }

    public func upsert(_ item: ClipboardItem) throws {
        if let existing = try findByHash(item.contentHash) {
            try database.execute(
                """
                UPDATE clipboard_items
                SET type = ?, preview_title = ?, content_text = ?, asset_path = ?, source_app_name = ?, last_used_at = ?, is_favorite = ?
                WHERE id = ?
                """,
                bindings: bindings(for: item, includeID: false) + [.text(existing.id.uuidString)]
            )
        } else {
            try database.execute(
                """
                INSERT INTO clipboard_items (id, type, preview_title, content_text, asset_path, source_app_name, created_at, last_used_at, is_favorite, content_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [.text(item.id.uuidString)] + bindings(for: item, includeID: true)
            )
        }
        try enforceRetention()
    }

    public func fetchAll() throws -> [ClipboardItem] {
        try database.query("SELECT * FROM clipboard_items ORDER BY last_used_at DESC, created_at DESC").map(decode)
    }

    public func toggleFavorite(id: UUID) throws {
        try database.execute("UPDATE clipboard_items SET is_favorite = CASE is_favorite WHEN 0 THEN 1 ELSE 0 END WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func delete(id: UUID) throws {
        if let item = try fetchByID(id) { removeAsset(item.assetPath) }
        try database.execute("DELETE FROM clipboard_items WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func clearNonFavorites() throws {
        let items = try fetchAll().filter { !$0.isFavorite }
        for item in items { removeAsset(item.assetPath) }
        try database.execute("DELETE FROM clipboard_items WHERE is_favorite = 0")
    }

    private func migrate() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                preview_title TEXT NOT NULL,
                content_text TEXT,
                asset_path TEXT,
                source_app_name TEXT,
                created_at INTEGER NOT NULL,
                last_used_at INTEGER NOT NULL,
                is_favorite INTEGER NOT NULL,
                content_hash TEXT NOT NULL UNIQUE
            )
            """
        )
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_hash ON clipboard_items(content_hash)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_retention ON clipboard_items(is_favorite, created_at)")
    }

    private func enforceRetention() throws {
        let nonFavorites = try fetchAll().filter { !$0.isFavorite }.sorted { $0.createdAt < $1.createdAt }
        if nonFavorites.count > 500 {
            for item in nonFavorites.prefix(nonFavorites.count - 500) { try delete(id: item.id) }
        }

        var images = try fetchAll().filter { $0.type == .image && !$0.isFavorite }.sorted { $0.createdAt < $1.createdAt }
        while images.count > imageCountLimit, let first = images.first {
            try delete(id: first.id)
            images.removeFirst()
        }

        func totalImageBytes(_ items: [ClipboardItem]) -> Int64 { items.reduce(0) { $0 + byteSize($1.assetPath) } }
        while totalImageBytes(images) > imageByteLimit, let first = images.first {
            try delete(id: first.id)
            images.removeFirst()
        }
    }

    private func findByHash(_ hash: String) throws -> ClipboardItem? {
        try database.query("SELECT * FROM clipboard_items WHERE content_hash = ? LIMIT 1", bindings: [.text(hash)]).first.map(decode)
    }

    private func fetchByID(_ id: UUID) throws -> ClipboardItem? {
        try database.query("SELECT * FROM clipboard_items WHERE id = ? LIMIT 1", bindings: [.text(id.uuidString)]).first.map(decode)
    }

    private func bindings(for item: ClipboardItem, includeID: Bool) -> [SQLiteBinding] {
        [
            .text(item.type.rawValue),
            .text(item.previewTitle),
            item.contentText.map(SQLiteBinding.text) ?? .null,
            item.assetPath.map(SQLiteBinding.text) ?? .null,
            item.sourceAppName.map(SQLiteBinding.text) ?? .null,
            .int(Int64(item.createdAt.timeIntervalSince1970)),
            .int(Int64(item.lastUsedAt.timeIntervalSince1970)),
            .int(item.isFavorite ? 1 : 0),
            .text(item.contentHash)
        ]
    }

    private func decode(row: [String: SQLiteValue]) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: row["id"]?.string ?? "") ?? UUID(),
            type: ClipboardContentType(rawValue: row["type"]?.string ?? "text") ?? .text,
            previewTitle: row["preview_title"]?.string ?? "",
            contentText: row["content_text"]?.string,
            assetPath: row["asset_path"]?.string,
            sourceAppName: row["source_app_name"]?.string,
            createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"]?.int64 ?? 0)),
            lastUsedAt: Date(timeIntervalSince1970: TimeInterval(row["last_used_at"]?.int64 ?? 0)),
            isFavorite: (row["is_favorite"]?.int64 ?? 0) == 1,
            contentHash: row["content_hash"]?.string ?? ""
        )
    }

    private func removeAsset(_ path: String?) {
        guard let path, fileManager.fileExists(atPath: path) else { return }
        try? fileManager.removeItem(atPath: path)
    }

    private func byteSize(_ path: String?) -> Int64 {
        guard let path else { return 0 }
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64 ?? 0
    }
}
```

- [ ] **Step 6: Run store tests**

Run:

```bash
swift test --filter ClipboardStoreTests
```

Expected: PASS.

- [ ] **Step 7: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 8: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Storage Tests/FCatCoreTests/ClipboardStoreTests.swift
git commit -m "feat: persist clipboard history in sqlite"
```

Otherwise record checkpoint: SQLite store and retention tests pass.

---

### Task 5: Add pasteboard monitoring and ingestion

**Files:**
- Create: `Sources/FCatCore/Pasteboard/PasteboardClient.swift`
- Create: `Sources/FCatCore/Pasteboard/ClipboardMonitor.swift`
- Create: `Tests/FCatCoreTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: Write failing monitor tests**

Create `Tests/FCatCoreTests/ClipboardMonitorTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class ClipboardMonitorTests: XCTestCase {
    func testTextChangeCreatesTextItem() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .text("hello world"))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: { Date(timeIntervalSince1970: 10) })

        try monitor.pollOnce()

        XCTAssertEqual(sink.items.count, 1)
        XCTAssertEqual(sink.items[0].type, .text)
        XCTAssertEqual(sink.items[0].previewTitle, "hello world")
        XCTAssertEqual(sink.items[0].contentText, "hello world")
    }

    func testSameChangeCountDoesNotCreateItemTwice() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .text("hello"))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: Date.init)

        try monitor.pollOnce()
        try monitor.pollOnce()

        XCTAssertEqual(sink.items.count, 1)
    }

    func testFilePathsCreateFileItem() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .files(["/tmp/a.txt", "/tmp/b.txt"]))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, now: Date.init)

        try monitor.pollOnce()

        XCTAssertEqual(sink.items[0].type, .file)
        XCTAssertEqual(sink.items[0].previewTitle, "a.txt, b.txt")
        XCTAssertEqual(sink.items[0].contentText, "/tmp/a.txt\n/tmp/b.txt")
    }

    func testImageDataCreatesImageItemWithAssetPath() throws {
        let pasteboard = FakePasteboard(changeCount: 1, snapshot: .imagePNG(Data([1, 2, 3])))
        let sink = CapturingSink()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, sink: sink, imageSaver: { data, id in "/tmp/\(id.uuidString).png" }, now: Date.init)

        try monitor.pollOnce()

        XCTAssertEqual(sink.items[0].type, .image)
        XCTAssertNotNil(sink.items[0].assetPath)
    }

    private final class CapturingSink: ClipboardItemSink {
        var items: [ClipboardItem] = []
        func ingest(_ item: ClipboardItem) throws { items.append(item) }
    }

    private struct FakePasteboard: PasteboardClient {
        var changeCount: Int
        var snapshot: PasteboardSnapshot?
        func currentChangeCount() -> Int { changeCount }
        func readSnapshot() -> PasteboardSnapshot? { snapshot }
        func write(_ item: ClipboardItem) throws {}
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter ClipboardMonitorTests
```

Expected: FAIL because monitor types do not exist.

- [ ] **Step 3: Implement pasteboard abstractions**

Create `Sources/FCatCore/Pasteboard/PasteboardClient.swift`:

```swift
import AppKit
import Foundation

public enum PasteboardSnapshot: Equatable {
    case text(String)
    case files([String])
    case imagePNG(Data)
}

public protocol PasteboardClient {
    func currentChangeCount() -> Int
    func readSnapshot() -> PasteboardSnapshot?
    func write(_ item: ClipboardItem) throws
}

public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func currentChangeCount() -> Int { pasteboard.changeCount }

    public func readSnapshot() -> PasteboardSnapshot? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            return .imagePNG(data)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    public func write(_ item: ClipboardItem) throws {
        pasteboard.clearContents()
        switch item.type {
        case .text:
            pasteboard.setString(item.contentText ?? "", forType: .string)
        case .file:
            pasteboard.setString(item.contentText ?? "", forType: .string)
        case .image:
            if let path = item.assetPath, let image = NSImage(contentsOfFile: path) {
                pasteboard.writeObjects([image])
            }
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 4: Implement monitor**

Create `Sources/FCatCore/Pasteboard/ClipboardMonitor.swift`:

```swift
import Foundation

public protocol ClipboardItemSink {
    func ingest(_ item: ClipboardItem) throws
}

extension ClipboardStore: ClipboardItemSink {
    public func ingest(_ item: ClipboardItem) throws { try upsert(item) }
}

public final class ClipboardMonitor {
    private let pasteboard: PasteboardClient
    private let sink: ClipboardItemSink
    private let imageSaver: (Data, UUID) throws -> String
    private let now: () -> Date
    private var lastChangeCount: Int?
    private var timer: Timer?

    public init(
        pasteboard: PasteboardClient,
        sink: ClipboardItemSink,
        imageSaver: @escaping (Data, UUID) throws -> String = { _, _ in throw ClipboardMonitorError.imageSaverMissing },
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.sink = sink
        self.imageSaver = imageSaver
        self.now = now
    }

    public func start(interval: TimeInterval = 0.5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            try? self?.pollOnce()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func pollOnce() throws {
        let changeCount = pasteboard.currentChangeCount()
        if lastChangeCount == changeCount { return }
        lastChangeCount = changeCount
        guard let snapshot = pasteboard.readSnapshot() else { return }
        try sink.ingest(makeItem(from: snapshot))
    }

    private func makeItem(from snapshot: PasteboardSnapshot) throws -> ClipboardItem {
        let id = UUID()
        let date = now()
        switch snapshot {
        case .text(let text):
            return ClipboardItem(id: id, type: .text, previewTitle: preview(text), contentText: text, assetPath: nil, sourceAppName: nil, createdAt: date, lastUsedAt: date, isFavorite: false, contentHash: ContentHasher.hashText(text))
        case .files(let paths):
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            let content = paths.joined(separator: "\n")
            return ClipboardItem(id: id, type: .file, previewTitle: names, contentText: content, assetPath: nil, sourceAppName: nil, createdAt: date, lastUsedAt: date, isFavorite: false, contentHash: ContentHasher.hashFilePaths(paths))
        case .imagePNG(let data):
            let path = try imageSaver(data, id)
            return ClipboardItem(id: id, type: .image, previewTitle: "Image", contentText: nil, assetPath: path, sourceAppName: nil, createdAt: date, lastUsedAt: date, isFavorite: false, contentHash: ContentHasher.hashImagePNGData(data))
        }
    }

    private func preview(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(80))
    }
}

public enum ClipboardMonitorError: Error, Equatable {
    case imageSaverMissing
}
```

- [ ] **Step 5: Run monitor tests**

Run:

```bash
swift test --filter ClipboardMonitorTests
```

Expected: PASS.

- [ ] **Step 6: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Pasteboard Tests/FCatCoreTests/ClipboardMonitorTests.swift
git commit -m "feat: monitor macOS pasteboard changes"
```

Otherwise record checkpoint: pasteboard monitoring tests pass.

---

### Task 6: Add view models for history and settings

**Files:**
- Create: `Sources/FCatCore/Models/HotKey.swift`
- Create: `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift`
- Create: `Sources/FCatCore/ViewModels/SettingsViewModel.swift`
- Create: `Tests/FCatCoreTests/HistoryPanelViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/FCatCoreTests/HistoryPanelViewModelTests.swift`:

```swift
import XCTest
@testable import FCatCore

final class HistoryPanelViewModelTests: XCTestCase {
    func testSearchFiltersItems() {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [item("alpha cat"), item("beta dog")]), pasteboard: FakePasteboard())
        viewModel.query = "cat"
        XCTAssertEqual(viewModel.visibleItems.map(\.previewTitle), ["alpha cat"])
    }

    func testCategoryFiltersItems() {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [item("text", type: .text), item("image", type: .image)]), pasteboard: FakePasteboard())
        viewModel.category = .images
        XCTAssertEqual(viewModel.visibleItems.map(\.type), [.image])
    }

    func testMoveSelectionClampsToVisibleItems() {
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [item("one"), item("two")]), pasteboard: FakePasteboard())
        viewModel.moveSelection(delta: 1)
        viewModel.moveSelection(delta: 1)
        viewModel.moveSelection(delta: 1)
        XCTAssertEqual(viewModel.selectedIndex, 1)
        viewModel.moveSelection(delta: -3)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testCopySelectedWritesToPasteboard() throws {
        let pasteboard = FakePasteboard()
        let viewModel = HistoryPanelViewModel(store: InMemoryHistoryStore(items: [item("one")]), pasteboard: pasteboard)
        try viewModel.copySelected()
        XCTAssertEqual(pasteboard.written.first?.previewTitle, "one")
    }

    private func item(_ title: String, type: ClipboardContentType = .text) -> ClipboardItem {
        ClipboardItem(id: UUID(), type: type, previewTitle: title, contentText: title, assetPath: nil, sourceAppName: nil, createdAt: Date(), lastUsedAt: Date(), isFavorite: false, contentHash: title)
    }

    private final class FakePasteboard: PasteboardClient {
        var written: [ClipboardItem] = []
        func currentChangeCount() -> Int { 0 }
        func readSnapshot() -> PasteboardSnapshot? { nil }
        func write(_ item: ClipboardItem) throws { written.append(item) }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter HistoryPanelViewModelTests
```

Expected: FAIL because view model types do not exist.

- [ ] **Step 3: Add store protocol and in-memory test store**

Append to `Sources/FCatCore/Storage/ClipboardStore.swift` after `ClipboardStore`:

```swift
public protocol HistoryStore {
    func fetchAll() throws -> [ClipboardItem]
    func toggleFavorite(id: UUID) throws
    func delete(id: UUID) throws
    func clearNonFavorites() throws
}

extension ClipboardStore: HistoryStore {}

public final class InMemoryHistoryStore: HistoryStore {
    private var items: [ClipboardItem]

    public init(items: [ClipboardItem]) {
        self.items = items
    }

    public func fetchAll() throws -> [ClipboardItem] { items }

    public func toggleFavorite(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
    }

    public func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    public func clearNonFavorites() throws {
        items.removeAll { !$0.isFavorite }
    }
}
```

- [ ] **Step 4: Add hotkey and view models**

Create `Sources/FCatCore/Models/HotKey.swift`:

```swift
import Foundation

public struct HotKey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
```

Create `Sources/FCatCore/ViewModels/HistoryPanelViewModel.swift`:

```swift
import Foundation

public final class HistoryPanelViewModel: ObservableObject {
    @Published public var query: String = "" { didSet { selectedIndex = 0 } }
    @Published public var category: ClipboardCategory = .all { didSet { selectedIndex = 0 } }
    @Published public private(set) var selectedIndex: Int = 0

    private let store: HistoryStore
    private let pasteboard: PasteboardClient

    public init(store: HistoryStore, pasteboard: PasteboardClient) {
        self.store = store
        self.pasteboard = pasteboard
    }

    public var visibleItems: [ClipboardItem] {
        let items = (try? store.fetchAll()) ?? []
        return SearchService.search(items: items, query: query, category: category)
    }

    public func moveSelection(delta: Int) {
        let maxIndex = max(visibleItems.count - 1, 0)
        selectedIndex = min(max(selectedIndex + delta, 0), maxIndex)
    }

    public func copySelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try pasteboard.write(visibleItems[selectedIndex])
    }

    public func toggleFavoriteSelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try store.toggleFavorite(id: visibleItems[selectedIndex].id)
        objectWillChange.send()
    }

    public func deleteSelected() throws {
        guard visibleItems.indices.contains(selectedIndex) else { return }
        try store.delete(id: visibleItems[selectedIndex].id)
        selectedIndex = min(selectedIndex, max(visibleItems.count - 1, 0))
        objectWillChange.send()
    }

    public func clearNonFavorites() throws {
        try store.clearNonFavorites()
        selectedIndex = 0
        objectWillChange.send()
    }
}
```

Create `Sources/FCatCore/ViewModels/SettingsViewModel.swift`:

```swift
import Foundation

public final class SettingsViewModel: ObservableObject {
    @Published public var hotKey: HotKey?
    private let defaults: UserDefaults
    private let key = "FCat.hotKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotKey = Self.load(defaults: defaults, key: key)
    }

    public var hasHotKey: Bool { hotKey != nil }

    public func save(hotKey: HotKey) {
        self.hotKey = hotKey
        let data = try? JSONEncoder().encode(hotKey)
        defaults.set(data, forKey: key)
    }

    private static func load(defaults: UserDefaults, key: String) -> HotKey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
}
```

- [ ] **Step 5: Run view model tests**

Run:

```bash
swift test --filter HistoryPanelViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Models/HotKey.swift Sources/FCatCore/ViewModels Tests/FCatCoreTests/HistoryPanelViewModelTests.swift
git commit -m "feat: add clipboard history view models"
```

Otherwise record checkpoint: view model tests pass.

---

### Task 7: Add global hotkey manager

**Files:**
- Create: `Sources/FCatCore/HotKeys/GlobalHotKeyManager.swift`

- [ ] **Step 1: Add implementation file**

Create `Sources/FCatCore/HotKeys/GlobalHotKeyManager.swift`:

```swift
import Carbon
import Foundation

public final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    public init() {}

    deinit { unregister() }

    public func register(_ hotKey: HotKey, action: @escaping () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.action?()
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        guard installStatus == noErr else { throw GlobalHotKeyError.cannotInstallHandler(status: installStatus) }

        var identifier = EventHotKeyID(signature: OSType(0x46434154), id: 1)
        let registerStatus = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else { throw GlobalHotKeyError.cannotRegister(status: registerStatus) }
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
        action = nil
    }
}

public enum GlobalHotKeyError: Error, Equatable {
    case cannotInstallHandler(status: OSStatus)
    case cannotRegister(status: OSStatus)
}
```

- [ ] **Step 2: Build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Manual verification**

Use a temporary call from `AppDelegate.applicationDidFinishLaunching` during this task only:

```swift
try? GlobalHotKeyManager().register(HotKey(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))) {
    print("hotkey pressed")
}
```

Run:

```bash
swift run FCat
```

Expected: pressing Command+Option+Space prints `hotkey pressed` in the terminal. Remove the temporary call before the checkpoint.

- [ ] **Step 4: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/HotKeys/GlobalHotKeyManager.swift
git commit -m "feat: register global macos hotkeys"
```

Otherwise record checkpoint: hotkey manager builds and manual registration works.

---

### Task 8: Add SwiftUI history and settings views

**Files:**
- Create: `Sources/FCatCore/Views/HistoryPanelView.swift`
- Create: `Sources/FCatCore/Views/SettingsView.swift`

- [ ] **Step 1: Create history panel view**

Create `Sources/FCatCore/Views/HistoryPanelView.swift`:

```swift
import SwiftUI

public struct HistoryPanelView: View {
    @ObservedObject private var viewModel: HistoryPanelViewModel
    private let close: () -> Void

    public init(viewModel: HistoryPanelViewModel, close: @escaping () -> Void) {
        self.viewModel = viewModel
        self.close = close
    }

    public var body: some View {
        VStack(spacing: 8) {
            TextField("Search clipboard history", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .padding([.top, .horizontal], 12)

            Picker("Category", selection: $viewModel.category) {
                ForEach(ClipboardCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            List(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text(icon(for: item))
                    VStack(alignment: .leading) {
                        Text(item.previewTitle).lineLimit(1)
                        if let contentText = item.contentText {
                            Text(contentText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if item.isFavorite { Text("★") }
                }
                .padding(.vertical, 4)
                .background(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
        .frame(width: 620, height: 520)
        .onExitCommand { close() }
        .onMoveCommand { direction in
            switch direction {
            case .up: viewModel.moveSelection(delta: -1)
            case .down: viewModel.moveSelection(delta: 1)
            default: break
            }
        }
        .commands {
            CommandMenu("Clipboard") {
                Button("Copy Selected") { try? viewModel.copySelected(); close() }.keyboardShortcut(.return, modifiers: [])
                Button("Favorite Selected") { try? viewModel.toggleFavoriteSelected() }.keyboardShortcut("d", modifiers: [.command])
                Button("Delete Selected") { try? viewModel.deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
            }
        }
    }

    private func icon(for item: ClipboardItem) -> String {
        switch item.type {
        case .text: return "T"
        case .image: return "I"
        case .file: return "F"
        }
    }
}
```

- [ ] **Step 2: Create settings view**

Create `Sources/FCatCore/Views/SettingsView.swift`:

```swift
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    private let saveHotKey: (HotKey) -> Void

    public init(viewModel: SettingsViewModel, saveHotKey: @escaping (HotKey) -> Void) {
        self.viewModel = viewModel
        self.saveHotKey = saveHotKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set a global shortcut")
                .font(.title2.bold())
            Text("Choose the shortcut used to show and hide clipboard history.")
                .foregroundStyle(.secondary)

            Button("Use Command + Option + Space") {
                let hotKey = HotKey(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
                viewModel.save(hotKey: hotKey)
                saveHotKey(hotKey)
            }
            .keyboardShortcut(.space, modifiers: [.command, .option])

            if viewModel.hasHotKey {
                Text("Shortcut saved")
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}
```

- [ ] **Step 3: Build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCatCore/Views
git commit -m "feat: add clipboard history views"
```

Otherwise record checkpoint: SwiftUI views build.

---

### Task 9: Wire services into the menu bar app

**Files:**
- Modify: `Sources/FCat/AppDelegate.swift`

- [ ] **Step 1: Replace app delegate with full wiring**

Replace `Sources/FCat/AppDelegate.swift` with:

```swift
import AppKit
import FCatCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var monitor: ClipboardMonitor?
    private let hotKeyManager = GlobalHotKeyManager()
    private var store: ClipboardStore?
    private var pasteboard: SystemPasteboardClient?
    private var settingsViewModel = SettingsViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = try appSupportDirectory()
            let assetStore = try ImageAssetStore(directory: support.appendingPathComponent("Images", isDirectory: true))
            let store = try ClipboardStore(databaseURL: support.appendingPathComponent("history.sqlite"))
            let pasteboard = SystemPasteboardClient()
            self.store = store
            self.pasteboard = pasteboard
            self.monitor = ClipboardMonitor(pasteboard: pasteboard, sink: store, imageSaver: assetStore.savePNGData)
            self.monitor?.start()
            createStatusItem()
            if let hotKey = settingsViewModel.hotKey {
                try register(hotKey)
            } else {
                openSettings()
            }
        } catch {
            showError("Failed to start FCat: \(error)")
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "F"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear Non-Favorites", action: #selector(clearNonFavorites), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openHistory() {
        guard let store, let pasteboard else { return }
        if let historyWindow, historyWindow.isVisible {
            historyWindow.orderOut(nil)
            return
        }

        let viewModel = HistoryPanelViewModel(store: store, pasteboard: pasteboard)
        let view = HistoryPanelView(viewModel: viewModel) { [weak self] in self?.historyWindow?.orderOut(nil) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.title = "Clipboard History"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        let view = SettingsView(viewModel: settingsViewModel) { [weak self] hotKey in
            do { try self?.register(hotKey) }
            catch { self?.showError("Shortcut registration failed. Choose another shortcut.") }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.title = "FCat Settings"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func clearNonFavorites() {
        try? store?.clearNonFavorites()
    }

    @objc private func quit() {
        monitor?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func register(_ hotKey: HotKey) throws {
        try hotKeyManager.register(hotKey) { [weak self] in self?.openHistory() }
    }

    private func appSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("FCat", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Run app manually**

Run:

```bash
swift run FCat
```

Expected: menu bar item appears; if no shortcut is saved, settings window opens.

- [ ] **Step 4: Manual acceptance checks**

While `swift run FCat` is active:

1. Click "Use Command + Option + Space" in settings.
2. Copy text in another app.
3. Press Command+Option+Space.
4. Confirm the history window appears with the copied text.
5. Press Return on the selected item.
6. Confirm the item is copied back to the system pasteboard.
7. Quit and restart with `swift run FCat`.
8. Confirm the text history is still present.

- [ ] **Step 5: Checkpoint**

If this is a git repo, run:

```bash
git add Sources/FCat/AppDelegate.swift
git commit -m "feat: wire menu bar clipboard app"
```

Otherwise record checkpoint: the end-to-end menu bar app runs manually.

---

### Task 10: Final verification

**Files:**
- Modify only if verification finds a specific failure.

- [ ] **Step 1: Run all unit tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build debug executable**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Run manual verification matrix**

Run:

```bash
swift run FCat
```

Verify these behaviors:

- Menu bar item is visible.
- First launch without saved shortcut opens settings.
- Saving Command+Option+Space registers the shortcut.
- Shortcut toggles the history window.
- Text copy appears in All.
- Image copy appears in All and Images.
- File copy appears in All and Files as file paths.
- Search finds text by fuzzy query.
- Favorites appear in Favorites.
- Delete removes the selected item.
- Clear Non-Favorites keeps favorites.
- Restart keeps persisted history.

- [ ] **Step 4: Verify retention with tests**

Run:

```bash
swift test --filter ClipboardStoreTests
```

Expected: PASS, covering 500 non-favorite cap, 100 non-favorite image cap, 500MB image byte cap, and favorite preservation.

- [ ] **Step 5: Final checkpoint**

If this is a git repo, run:

```bash
git add Package.swift Sources Tests docs/superpowers/specs docs/superpowers/plans
git commit -m "feat: build macos clipboard history app"
```

Otherwise record checkpoint: tests pass, build passes, and manual verification matrix passes.

---

## Self-Review

- Spec coverage: menu bar app, custom shortcut flow, text/image/file history, SQLite persistence, 500 non-favorite cap, image 100 count and 500MB caps, favorites, fuzzy search, category tabs, copy-back, delete, clear non-favorites, and restart persistence are covered.
- Placeholder scan: no incomplete markers or unspecified implementation steps remain.
- Type consistency: plan consistently uses `ClipboardItem`, `ClipboardContentType`, `ClipboardCategory`, `HotKey`, `ClipboardStore`, `HistoryStore`, `PasteboardClient`, `ClipboardMonitor`, and `HistoryPanelViewModel`.
- Scope check: this is one coherent MVP. Sensitive app exclusion, sync, and multi-platform support remain out of scope as specified.
