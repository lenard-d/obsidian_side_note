import Foundation

struct VaultNoteSearch {
    static func rankedNotes(_ notes: [VaultNote], matching query: String, limit: Int? = nil) -> [VaultNote] {
        let request = searchRequest(for: query, in: notes)
        let candidateNotes = request.directoryScope.map { notesInDirectory($0, from: notes) } ?? notes
        let normalizedQuery = normalize(request.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else {
            return limited(candidateNotes, limit: limit)
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let rankedNotes = candidateNotes.compactMap { note -> RankedNote? in
            guard let score = score(note, query: normalizedQuery, tokens: tokens) else {
                return nil
            }

            return RankedNote(note: note, score: score)
        }
        .sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }

            return left.note.relativePath.localizedCaseInsensitiveCompare(right.note.relativePath) == .orderedAscending
        }
        .map(\.note)

        return limited(rankedNotes, limit: limit)
    }

    private static func searchRequest(for query: String, in notes: [VaultNote]) -> SearchRequest {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slashIndex = trimmedQuery.lastIndex(of: "/") else {
            return SearchRequest(directoryScope: nil, searchTerm: trimmedQuery)
        }

        let directory = normalizedDirectory(String(trimmedQuery[..<slashIndex]))
        guard !directory.isEmpty, notes.contains(where: { noteIsInDirectory($0, directory) }) else {
            return SearchRequest(directoryScope: nil, searchTerm: trimmedQuery)
        }

        let searchTermStart = trimmedQuery.index(after: slashIndex)
        return SearchRequest(
            directoryScope: directory,
            searchTerm: String(trimmedQuery[searchTermStart...])
        )
    }

    private static func notesInDirectory(_ directory: String, from notes: [VaultNote]) -> [VaultNote] {
        notes.filter { noteIsInDirectory($0, directory) }
    }

    private static func noteIsInDirectory(_ note: VaultNote, _ directory: String) -> Bool {
        normalizedPath(note.relativePath).hasPrefix("\(directory)/")
    }

    private static func score(_ note: VaultNote, query: String, tokens: [String]) -> Int? {
        let title = normalize(note.title)
        let relativePath = normalize(note.relativePath)
        let searchablePath = "\(title) \(relativePath)"
        var totalScore = 0

        for token in tokens {
            let tokenScores = [
                score(token, in: title, weight: 120),
                score(token, in: relativePath, weight: 70),
                score(token, in: searchablePath, weight: 35)
            ].compactMap { $0 }

            guard let bestScore = tokenScores.max() else {
                return nil
            }

            totalScore += bestScore
        }

        if title == query {
            totalScore += 1_000
        } else if title.hasPrefix(query) {
            totalScore += 700
        } else if relativePath.hasPrefix(query) {
            totalScore += 500
        } else if title.contains(query) {
            totalScore += 350
        } else if relativePath.contains(query) {
            totalScore += 220
        }

        return totalScore
    }

    private static func score(_ token: String, in candidate: String, weight: Int) -> Int? {
        guard !token.isEmpty, !candidate.isEmpty else { return nil }

        if candidate == token {
            return weight + 1_000
        }

        if candidate.hasPrefix(token) {
            return weight + 800 - min(candidate.count - token.count, 120)
        }

        if let range = candidate.range(of: token) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            let boundaryBonus = isBoundary(in: candidate, at: range.lowerBound) ? 120 : 0
            return weight + 560 + boundaryBonus - min(offset, 180)
        }

        guard let fuzzyScore = fuzzyScore(token, in: candidate) else {
            return nil
        }

        return weight + fuzzyScore
    }

    private static func fuzzyScore(_ token: String, in candidate: String) -> Int? {
        let queryCharacters = Array(token)
        let candidateCharacters = Array(candidate)
        var queryIndex = 0
        var lastMatchIndex = -2
        var score = 160

        for (candidateIndex, character) in candidateCharacters.enumerated() {
            guard character == queryCharacters[queryIndex] else {
                continue
            }

            if queryIndex == 0 {
                score += max(0, 120 - candidateIndex)
            }
            score += candidateIndex == lastMatchIndex + 1 ? 80 : 18
            if isBoundary(in: candidateCharacters, at: candidateIndex) {
                score += 48
            }

            queryIndex += 1
            lastMatchIndex = candidateIndex

            if queryIndex == queryCharacters.count {
                return score - min(candidateCharacters.count - queryCharacters.count, 120)
            }
        }

        return nil
    }

    private static func isBoundary(in candidate: String, at index: String.Index) -> Bool {
        guard index != candidate.startIndex else { return true }
        let previousIndex = candidate.index(before: index)
        return isSeparator(candidate[previousIndex])
    }

    private static func isBoundary(in characters: [Character], at index: Int) -> Bool {
        index == 0 || isSeparator(characters[index - 1])
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_" || character == "/" || character == "."
    }

    private static func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func normalizedDirectory(_ path: String) -> String {
        normalizedPath(path)
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private static func normalizedPath(_ path: String) -> String {
        normalize(path).replacingOccurrences(of: "\\", with: "/")
    }

    private static func limited(_ notes: [VaultNote], limit: Int?) -> [VaultNote] {
        guard let limit, limit >= 0, notes.count > limit else {
            return notes
        }

        return Array(notes.prefix(limit))
    }

    private struct RankedNote {
        let note: VaultNote
        let score: Int
    }

    private struct SearchRequest {
        let directoryScope: String?
        let searchTerm: String
    }
}
