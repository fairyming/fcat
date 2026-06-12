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
