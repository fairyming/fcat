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
