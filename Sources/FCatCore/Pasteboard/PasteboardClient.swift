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
        case .text, .file:
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
