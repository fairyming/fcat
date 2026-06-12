import Foundation

public enum FuzzyMatcher {
    public static func score(query: String, candidate: String) -> Int? {
        let queryCharacters = Array(query.lowercased())
        if queryCharacters.isEmpty { return 0 }

        let candidateCharacters = Array(candidate.lowercased())
        var queryIndex = 0
        var score = 0
        var previousMatchIndex: Int?

        for candidateIndex in candidateCharacters.indices {
            if candidateCharacters[candidateIndex] == queryCharacters[queryIndex] {
                score += 10
                if let previousMatchIndex {
                    let gap = candidateIndex - previousMatchIndex - 1
                    score += max(0, 8 - gap)
                    score -= min(gap, 10)
                }
                if candidateIndex == 0 || candidateCharacters[candidateIndex - 1].isWhitespace || candidateCharacters[candidateIndex - 1] == "/" || candidateCharacters[candidateIndex - 1] == "-" || candidateCharacters[candidateIndex - 1] == "_" {
                    score += 5
                }
                previousMatchIndex = candidateIndex
                queryIndex += 1
                if queryIndex == queryCharacters.count { return score }
            }
        }

        return nil
    }
}
