import Foundation

nonisolated struct VaultSearchSection: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case folders = "folder"
        case exactMatches = "exact matches"
        case files = "files"
        case subfolderFiles = "files in subfolders"
    }

    let kind: Kind
    let notes: [VaultNote]
    var id: Kind { kind }
}

nonisolated struct VaultSearchResults: Sendable {
    static let empty = VaultSearchResults(sections: [], preferredID: nil)

    struct Row: Identifiable, Sendable {
        let note: VaultNote
        let section: VaultSearchSection.Kind
        var id: String { note.id }
        var isFolder: Bool { section == .folders }
    }

    let sections: [VaultSearchSection]
    let rows: [Row]
    let preferredIndex: Int
    let sectionStarts: [Int]

    init(sections: [VaultSearchSection], preferredID: String?) {
        self.sections = sections
        rows = sections.flatMap { section in section.notes.map { Row(note: $0, section: section.kind) } }
        preferredIndex = rows.firstIndex { $0.id == preferredID } ?? 0
        var offset = 0
        sectionStarts = sections.map { section in
            defer { offset += section.notes.count }
            return offset
        }
    }

    func nextSection(after index: Int) -> Int {
        sectionStarts.first { $0 > index } ?? index
    }

    func previousSection(before index: Int) -> Int {
        guard let current = sectionStarts.lastIndex(where: { $0 <= index }), current > 0 else { return 0 }
        return sectionStarts[current - 1]
    }
}
