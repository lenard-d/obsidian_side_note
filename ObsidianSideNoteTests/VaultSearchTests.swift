import AppKit
import Foundation
import Testing
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @Test(arguments: ["Team's Weekly Review", "Team’s Weekly Review", "TEAMS WEEKLY REVIEW", "teams   weekly\u{00A0}review", "team's weekly review.MD", "\"Team's Weekly Review\"", "teams-weekly-review"])
    func exactSearchAcceptsCommonFilenameSpellings(query: String) {
        let exact = searchNote("Personal/Team’s Weekly Review.md")
        let distractors = (0..<120).map { searchNote("Archive/Team's Weekly Review Archive \($0).md") }
        let results = VaultNoteSearch.rankedNotes(distractors + [exact], matching: query)
        #expect(results.first == exact)
    }

    @Test func exactTitleWinsOverPathWordsAndLongFuzzyScores() {
        let exact = searchNote("Deep/Archive/Team's Weekly Review.md")
        let notes = [searchNote("Team's Weekly Review/Team's Weekly Review Archive.md"),
                     searchNote("Weekly Review/Team's Planning Notes.md"), exact]
        #expect(VaultNoteSearch.rankedNotes(notes, matching: "team's weekly review").first == exact)
    }

    @Test func searchSupportsReorderedWordsAndWordInitials() {
        let intended = searchNote("Work/Image Paste Regression.md")
        let notes = [searchNote("Other/Shipwreck.md"), intended]
        #expect(VaultNoteSearch.rankedNotes(notes, matching: "regression image").first == intended)
        #expect(VaultNoteSearch.rankedNotes(notes, matching: "ipr").first == intended)
    }

    @Test(arguments: ["meeting noets", "meeting nots", "meeting nottes", "meeting nptes"])
    func searchAllowsOneTypoInALongWord(query: String) {
        let note = searchNote("Meeting Notes.md")
        #expect(VaultNoteSearch.rankedNotes([note], matching: query) == [note])
    }

    @Test func shortUnrelatedWordsDoNotGetTypoMatches() {
        #expect(VaultNoteSearch.rankedNotes([searchNote("Cat.md")], matching: "car").isEmpty)
    }

    @Test func searchNormalizesUnicodeWithoutChangingReturnedPaths() {
        let note = searchNote("Perso\u{0308}nliches/Cafe\u{0301} Ideas.md")
        #expect(VaultNoteSearch.rankedNotes([note], matching: "Persönliches/cafe ideas.md") == [note])
    }

    @Test func browsingSeparatesDirectFilesAndSubfoldersAndExcludesSiblings() {
        let notes = [searchNote("Work/Plan.md"), searchNote("Work/Archive/Old.md"), searchNote("Workshop/Other.md")]
        let folders = [searchFolder("Work"), searchFolder("Work/Archive"), searchFolder("Work/Archive/Empty")]
        let results = VaultNoteSearch(notes: notes, folders: folders).suggestions(matching: "Work/")
        #expect(results.sections.map(\.kind) == [.folders, .files, .subfolderFiles])
        #expect(results.rows.map(\.note.relativePath) == ["Work/Archive", "Work/Plan.md", "Work/Archive/Old.md"])
        #expect(results.nextSection(after: 0) == 1)
        #expect(results.nextSection(after: 1) == 2)
        #expect(results.previousSection(before: 2) == 1)
    }

    @Test func scopedExactMatchInSubfolderWinsOverDirectPartialMatch() {
        let exact = searchNote("Work/Archive/Plan.md")
        let search = VaultNoteSearch(notes: [searchNote("Work/Plan Later.md"), exact], folders: [searchFolder("Work/Plans")])
        let results = search.suggestions(matching: "Work/plan")
        #expect(results.sections.map(\.kind) == [.folders, .exactMatches, .files])
        #expect(results.rows[results.preferredIndex].note == exact)
    }

    @Test(arguments: [("Projects", true), ("Projects.md", false), ("PROJECTS.MD  ", false),
                      ("Work/Projects", true), ("Work/Projects.md", false)])
    func folderNoteDoesNotInterceptFolderNavigation(query: String, selectsFolder: Bool) {
        let folder = searchFolder("Work/Projects")
        let note = searchNote("Work/Projects/Projects.md")
        let results = VaultNoteSearch(notes: [note], folders: [folder]).suggestions(matching: query)
        #expect(results.rows[results.preferredIndex].isFolder == selectsFolder)
        #expect(results.rows.map(\.note) == [folder, note])
        #expect(results.nextSection(after: 0) == 1)
    }

    @Test func folderSearchMatchesNamesInsteadOfEveryDescendant() {
        let search = VaultNoteSearch(notes: [], folders: [searchFolder("Projects"), searchFolder("Projects/Archive"), searchFolder("Projects/Empty")])
        #expect(search.suggestions(matching: "Projects").rows.map(\.note.relativePath) == ["Projects"])
        #expect(search.suggestions(matching: "Projects/Empty/").rows.isEmpty)
        #expect(search.suggestions(matching: "Missing/").rows.isEmpty)
        #expect(search.suggestions(matching: "Projects/Emp/").rows.isEmpty)
    }

    @Test func fullAndPartialPathQueriesFindTheFile() {
        let note = searchNote("Projects/Archive/Meeting Notes.md")
        let search = VaultNoteSearch(notes: [note, searchNote("Other/Meeting Notes.md")])
        #expect(search.rankedNotes(matching: "Projects/Archive/Meeting Notes.md") == [note])
        #expect(search.rankedNotes(matching: "proj/arch/meeting").first == note)
        #expect(search.rankedNotes(matching: "Projects\\Archive\\meeting notes.md") == [note])
    }

    @Test func matchingFilesAreNotSilentlyTruncatedAtEighty() {
        let notes = (0..<125).map { searchNote("Note \($0).md") }
        let results = VaultNoteSearch(notes: notes).suggestions(matching: "note")
        #expect(results.rows.count == 125)
    }

    @MainActor
    @Test func searchKeyboardRequiresFocusAndHandlesSectionNavigationAndEscape() throws {
        let model = ContentViewModel(mode: .editVaultFile)
        model.vaultSearchQuery = "work"
        model.setEventWindowNumber(42)
        model.searchSuggestions = VaultNoteSearch(notes: [searchNote("Work Notes.md")], folders: [searchFolder("Work")]).suggestions(matching: "work")
        let down = try searchKey(code: 125, modifiers: .command)
        #expect(!model.handleSearchKey(down))
        model.isSearchFocused = true
        #expect(model.handleSearchKey(down))
        #expect(model.highlightedSearchIndex == 1)
        #expect(model.handleSearchKey(try searchKey(code: 126, modifiers: .command)))
        #expect(model.highlightedSearchIndex == 0)
        #expect(!model.handleSearchKey(try searchKey(code: 125, modifiers: .option)))
        #expect(model.handleSearchKey(try searchKey(code: 53)))
        #expect(!model.shouldShowSearchSuggestions)
        #expect(!model.handleSearchKey(try searchKey(code: 53)))
    }

    @MainActor
    @Test func rapidQueriesClearStaleResultsAndKeepTheActiveNote() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vault)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
        }
        try "Alpha".write(to: vault.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try "Beta".write(to: vault.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)
        VaultStore.saveVaultURL(vault)
        let model = ContentViewModel(mode: .editVaultFile)
        let activeNote = try #require(VaultStore.markdownNotes(matching: "Alpha").first)
        model.selectNote(activeNote)
        defer { model.stop() }
        model.vaultSearchQuery = "Alpha"
        model.searchQueryDidChange()
        let oldTask = model.searchTask
        model.vaultSearchQuery = "Beta"
        model.searchQueryDidChange()
        await oldTask?.value
        await model.searchTask?.value
        #expect(model.searchResults.map(\.title) == ["Beta"])
        #expect(model.selectedNote == activeNote)
        #expect(model.noteText == "Alpha")
        model.vaultSearchQuery = "Alpha"
        model.searchQueryDidChange()
        model.vaultSearchQuery = ""
        model.searchQueryDidChange()
        await model.searchTask?.value
        #expect(model.searchSuggestions.rows.isEmpty)
        #expect(!model.isSearching)

        try "New".write(to: vault.appendingPathComponent("New.md"), atomically: true, encoding: .utf8)
        model.vaultSearchQuery = "New"
        model.searchFocusDidChange(true)
        model.setEventWindowNumber(42)
        #expect(model.handleSearchKey(try searchKey(code: 36)))
        await model.searchTask?.value
        #expect(model.searchResults.map(\.title) == ["New"])
        #expect(model.selectedNote?.title == "New")
        #expect(model.noteText == "New")
    }

    private func searchNote(_ path: String) -> VaultNote {
        VaultNote(relativePath: path, title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                  url: URL(fileURLWithPath: "/tmp/search-fixture").appendingPathComponent(path))
    }

    private func searchFolder(_ path: String) -> VaultNote {
        VaultNote(relativePath: path, title: URL(fileURLWithPath: path).lastPathComponent,
                  url: URL(fileURLWithPath: "/tmp/search-fixture").appendingPathComponent(path))
    }

    private func searchKey(code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                     timestamp: 0, windowNumber: 42, context: nil, characters: "",
                                     charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
}
