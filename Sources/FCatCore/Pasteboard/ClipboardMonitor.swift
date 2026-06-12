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
