import Foundation

/// Prepared once per vault index. Query scoring does not read files or normalize every filename again.
nonisolated struct VaultNoteSearch: Sendable {
    private let notes: [Candidate]
    private let folders: [Candidate]
    private let directories: Set<String>

    init(notes: [VaultNote], folders: [VaultNote] = []) {
        self.notes = notes.map { Candidate($0) }
        self.folders = folders.map { Candidate($0) }
        var directories = Set(folders.map { Self.pathKey($0.relativePath) })
        for note in notes {
            var components = note.relativePath.split(separator: "/").dropLast()
            while !components.isEmpty {
                directories.insert(Self.pathKey(components.joined(separator: "/")))
                components = components.dropLast()
            }
        }
        self.directories = directories
    }

    static func rankedNotes(_ notes: [VaultNote], matching query: String, limit: Int? = nil) -> [VaultNote] {
        VaultNoteSearch(notes: notes).rankedNotes(matching: query, limit: limit)
    }

    func rankedNotes(matching query: String, limit: Int? = nil) -> [VaultNote] {
        let matches = ranked(notes, request: request(for: query))
        let result = matches.map(\.candidate.note)
        guard let limit, limit >= 0 else { return result }
        return Array(result.prefix(limit))
    }

    func suggestions(matching query: String) -> VaultSearchResults {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        let request = request(for: query)
        let files = ranked(notes, request: request)
        let folderMatches = ranked(folders, request: request, foldersOnly: true)
        let exact = files.filter { $0.rank <= .exactTitle }
        let otherFiles = files.filter { $0.rank > .exactTitle }
        let directFiles = otherFiles.filter { request.directory == nil || $0.candidate.parent == request.directory }
        let nestedFiles = otherFiles.filter { request.directory != nil && $0.candidate.parent != request.directory }
        let sections = [
            VaultSearchSection(kind: .folders, notes: folderMatches.map(\.candidate.note)),
            VaultSearchSection(kind: .exactMatches, notes: exact.map(\.candidate.note)),
            VaultSearchSection(kind: .files, notes: directFiles.map(\.candidate.note)),
            VaultSearchSection(kind: .subfolderFiles, notes: nestedFiles.map(\.candidate.note))
        ].filter { !$0.notes.isEmpty }
        let explicitlyNamesFile = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasSuffix(".md")
        let preferredID: String?
        if !explicitlyNamesFile, let folder = folderMatches.first, folder.rank <= .exactTitle {
            // A folder note must not intercept navigation into its namesake folder.
            preferredID = folder.candidate.note.id
        } else if let first = exact.first {
            preferredID = first.candidate.note.id
        } else if request.term.isEmpty {
            preferredID = folderMatches.first?.candidate.note.id ?? files.first?.candidate.note.id
        } else {
            // Searching by name should make Enter open the best file, even with folders above it.
            preferredID = files.first?.candidate.note.id ?? folderMatches.first?.candidate.note.id
        }
        return VaultSearchResults(sections: sections, preferredID: preferredID)
    }

    private func request(for query: String) -> Request {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        // A trailing slash always means browse this folder, including an empty or missing folder.
        if query.hasSuffix("/") {
            return Request(directory: Self.pathKey(query), term: "")
        }
        let slashes = query.indices.filter { query[$0] == "/" }
        for slash in slashes.reversed() {
            let directory = Self.pathKey(String(query[..<slash]))
            if directories.contains(directory) || directory.isEmpty {
                return Request(directory: directory, term: Self.searchKey(String(query[query.index(after: slash)...])))
            }
        }
        return Request(directory: nil, term: Self.searchKey(query))
    }

    private func ranked(_ candidates: [Candidate], request: Request, foldersOnly: Bool = false) -> [Match] {
        let tokens = request.term.split(separator: " ").map(String.init)
        return candidates.compactMap { candidate -> Match? in
            guard !Task.isCancelled else { return nil }
            if let directory = request.directory,
               !directory.isEmpty,
               !candidate.path.hasPrefix(directory + "/") { return nil }
            if request.term.isEmpty {
                if foldersOnly, candidate.parent != request.directory { return nil }
                return Match(candidate: candidate, rank: .browse, score: 0)
            }
            let relativeSearchPath: String
            if let directory = request.directory, !directory.isEmpty {
                relativeSearchPath = candidate.searchPath.split(separator: "/")
                    .dropFirst(directory.split(separator: "/").count).joined(separator: "/")
            } else {
                relativeSearchPath = candidate.searchPath
            }
            if candidate.title == request.term {
                return Match(candidate: candidate, rank: .exactTitle, score: 0)
            }
            if relativeSearchPath == request.term {
                return Match(candidate: candidate, rank: .exactPath, score: 0)
            }
            if candidate.title.hasPrefix(request.term) {
                return Match(candidate: candidate, rank: .prefix, score: -candidate.title.count)
            }
            if let range = candidate.title.range(of: request.term) {
                return Match(candidate: candidate, rank: .substring,
                             score: -candidate.title.distance(from: candidate.title.startIndex, to: range.lowerBound))
            }
            if let score = Self.tokenScore(tokens, in: candidate.title, fuzzy: false) {
                return Match(candidate: candidate, rank: .words, score: score)
            }
            if let score = Self.tokenScore(tokens, in: candidate.title, fuzzy: true) {
                return Match(candidate: candidate, rank: .abbreviation, score: score)
            }
            // Folder names should not flood the list just because an ancestor matches.
            if (!foldersOnly || request.term.contains("/")),
               let score = Self.tokenScore(tokens, in: relativeSearchPath, fuzzy: true) {
                return Match(candidate: candidate, rank: .path, score: score)
            }
            if Self.matchesWithTypo(tokens, words: candidate.words) {
                return Match(candidate: candidate, rank: .typo, score: -candidate.title.count)
            }
            return nil
        }.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            if left.score != right.score { return left.score > right.score }
            if left.rank != .browse, left.candidate.title.count != right.candidate.title.count {
                return left.candidate.title.count < right.candidate.title.count
            }
            let order = left.candidate.note.relativePath.localizedStandardCompare(right.candidate.note.relativePath)
            if order != .orderedSame { return order == .orderedAscending }
            return left.candidate.note.relativePath < right.candidate.note.relativePath
        }
    }

    private static func tokenScore(_ tokens: [String], in text: String, fuzzy: Bool) -> Int? {
        var total = 0
        for token in tokens {
            if let range = text.range(of: token) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                let boundary = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
                total += 100 + (boundary ? 40 : 0) - min(offset, 80)
            } else if fuzzy, let score = subsequenceScore(token, in: text) {
                total += score
            } else {
                return nil
            }
        }
        return total
    }

    /// Scores the best alignment, not just the first occurrence of each character.
    /// Adjacent letters and word starts win over letters spread across a long name.
    private static func subsequenceScore(_ token: String, in text: String) -> Int? {
        let query = Array(token)
        let target = Array(text)
        guard !query.isEmpty, query.count <= target.count else { return nil }
        var matched = 0
        for character in target where character == query[matched] {
            matched += 1
            if matched == query.count { break }
        }
        guard matched == query.count else { return nil }
        var previous = Array(repeating: Int.min / 2, count: target.count)
        for (queryIndex, character) in query.enumerated() {
            var current = Array(repeating: Int.min / 2, count: target.count)
            var bestEarlier = Int.min / 2
            for index in target.indices {
                if index > 0 { bestEarlier = max(bestEarlier - 1, previous[index - 1]) }
                guard target[index] == character else { continue }
                let boundary = index == 0 || !target[index - 1].isLetter && !target[index - 1].isNumber
                let bonus = 10 + (boundary ? 20 : 0)
                if queryIndex == 0 {
                    current[index] = bonus - min(index, 30)
                } else if index > 0 {
                    current[index] = max(bestEarlier + bonus, previous[index - 1] + bonus + 25)
                }
            }
            previous = current
        }
        guard let score = previous.max(), score > Int.min / 4 else { return nil }
        return score
    }

    private static func matchesWithTypo(_ tokens: [String], words: [String]) -> Bool {
        var typoCount = 0
        for token in tokens {
            if words.contains(where: { $0.contains(token) }) { continue }
            guard token.count >= 4, typoCount == 0,
                  words.contains(where: { oneEditApart(token, $0) }) else { return false }
            typoCount += 1
        }
        return typoCount == 1
    }

    /// Allows one insertion, deletion, substitution, or adjacent transposition in one query word.
    private static func oneEditApart(_ left: String, _ right: String) -> Bool {
        let a = Array(left), b = Array(right)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        if i == min(a.count, b.count) { return true }
        if a.count == b.count {
            if a.dropFirst(i + 1).elementsEqual(b.dropFirst(i + 1)) { return true }
            return i + 1 < a.count && a[i] == b[i + 1] && a[i + 1] == b[i]
                && a.dropFirst(i + 2).elementsEqual(b.dropFirst(i + 2))
        }
        if a.count > b.count { return a.dropFirst(i + 1).elementsEqual(b.dropFirst(i)) }
        return a.dropFirst(i).elementsEqual(b.dropFirst(i + 1))
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    static func pathKey(_ text: String) -> String {
        folded(text).replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    private static func searchKey(_ text: String) -> String {
        var text = folded(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.hasSuffix(".md") { text.removeLast(3) }
        let apostrophes: Set<Character> = ["'", "’", "‘", "ʼ", "＇"]
        let separators: Set<Character> = ["-", "_", "–", "—", ".", "\"", "“", "”"]
        text = String(text.filter { !apostrophes.contains($0) && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
            .map { $0.isWhitespace || separators.contains($0) ? Character(" ") : $0 })
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private struct Candidate: Sendable {
        let note: VaultNote
        let title: String
        let path: String
        let searchPath: String
        let parent: String
        let words: [String]

        init(_ note: VaultNote) {
            self.note = note
            title = searchKey(note.title)
            path = pathKey(note.relativePath)
            searchPath = searchKey(note.relativePath)
            parent = path.split(separator: "/").dropLast().joined(separator: "/")
            words = title.split(separator: " ").map(String.init)
        }
    }

    private struct Request {
        let directory: String?
        let term: String
    }

    private enum Rank: Int, Comparable {
        case exactPath, exactTitle, prefix, substring, words, abbreviation, path, typo, browse
        static func < (left: Rank, right: Rank) -> Bool { left.rawValue < right.rawValue }
    }

    private struct Match {
        let candidate: Candidate
        let rank: Rank
        let score: Int
    }
}
