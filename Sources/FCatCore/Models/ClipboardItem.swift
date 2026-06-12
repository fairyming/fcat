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
