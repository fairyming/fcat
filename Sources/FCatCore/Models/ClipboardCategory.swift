import Foundation

public enum ClipboardCategory: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case favorites = "Favorites"
    case images = "Images"
    case files = "Files"

    public var id: String { rawValue }
}
