import Foundation

public enum ClipboardCategory: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case texts = "Text"
    case images = "Images"
    case files = "Files"
    case favorites = "Favorites"

    public var id: String { rawValue }
}
