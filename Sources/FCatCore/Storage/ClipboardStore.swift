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
            if existing.assetPath != item.assetPath { removeAsset(existing.assetPath) }
            try database.execute(
                """
                UPDATE clipboard_items
                SET type = ?, preview_title = ?, content_text = ?, asset_path = ?, source_app_name = ?, last_used_at = ?, is_favorite = ?
                WHERE id = ?
                """,
                bindings: [
                    .text(item.type.rawValue),
                    .text(item.previewTitle),
                    item.contentText.map(SQLiteBinding.text) ?? .null,
                    item.assetPath.map(SQLiteBinding.text) ?? .null,
                    item.sourceAppName.map(SQLiteBinding.text) ?? .null,
                    .int(Int64(item.lastUsedAt.timeIntervalSince1970)),
                    .int(item.isFavorite ? 1 : 0),
                    .text(existing.id.uuidString)
                ]
            )
        } else {
            try database.execute(
                """
                INSERT INTO clipboard_items (id, type, preview_title, content_text, asset_path, source_app_name, created_at, last_used_at, is_favorite, content_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(item.id.uuidString),
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
        var nonFavorites = try fetchAll().filter { !$0.isFavorite }.sorted { $0.createdAt < $1.createdAt }
        while nonFavorites.count > 500, let first = nonFavorites.first {
            try delete(id: first.id)
            nonFavorites.removeFirst()
        }

        var images = try fetchAll().filter { $0.type == .image && !$0.isFavorite }.sorted { $0.createdAt < $1.createdAt }
        while images.count > imageCountLimit, let first = images.first {
            try delete(id: first.id)
            images.removeFirst()
        }
        while totalImageBytes(images) > imageByteLimit, let first = images.first {
            try delete(id: first.id)
            images.removeFirst()
        }
    }

    private func totalImageBytes(_ items: [ClipboardItem]) -> Int64 {
        items.reduce(0) { $0 + byteSize($1.assetPath) }
    }

    private func findByHash(_ hash: String) throws -> ClipboardItem? {
        try database.query("SELECT * FROM clipboard_items WHERE content_hash = ? LIMIT 1", bindings: [.text(hash)]).first.map(decode)
    }

    private func fetchByID(_ id: UUID) throws -> ClipboardItem? {
        try database.query("SELECT * FROM clipboard_items WHERE id = ? LIMIT 1", bindings: [.text(id.uuidString)]).first.map(decode)
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
