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
