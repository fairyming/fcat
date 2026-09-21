import Foundation

public enum TextMatcher {
    public static func score(query: String, candidate: String) -> Int? {
        let normalizedQuery = query.lowercased()
        if normalizedQuery.isEmpty { return 0 }

        let normalizedCandidate = candidate.lowercased()
        guard let range = normalizedCandidate.range(of: normalizedQuery) else { return nil }

        // Prefer an earlier occurrence when both title/body matches otherwise
        // have the same priority.
        let offset = normalizedCandidate.distance(from: normalizedCandidate.startIndex, to: range.lowerBound)
        return normalizedQuery.count * 10 - min(offset, 10)
    }
}
