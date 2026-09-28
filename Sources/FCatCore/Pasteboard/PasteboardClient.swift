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
    func writeText(_ text: String) throws
}

public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func currentChangeCount() -> Int { pasteboard.changeCount }

    public func readSnapshot() -> PasteboardSnapshot? {
        if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            return .imagePNG(data)
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    public func write(_ item: ClipboardItem) throws {
        pasteboard.clearContents()
        switch item.type {
        case .text, .file:
            pasteboard.setString(item.contentText ?? "", forType: .string)
        case .image:
            guard let path = item.assetPath,
                  let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = NSImage(data: imageData),
                  let png = image.pngData() else {
                throw PasteboardWriteError.imageUnavailable
            }
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            guard pasteboard.setData(png, forType: .png) else {
                throw PasteboardWriteError.imageWriteFailed
            }
            if let tiff = image.tiffRepresentation, !pasteboard.setData(tiff, forType: .tiff) {
                throw PasteboardWriteError.imageWriteFailed
            }
        }
    }

    public func writeText(_ text: String) throws {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

public enum PasteboardWriteError: Error, LocalizedError {
    case imageUnavailable
    case imageWriteFailed

    public var errorDescription: String? {
        "The image could not be loaded for copying."
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
