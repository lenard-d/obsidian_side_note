import Testing
import Foundation
import AppKit
import SwiftUI
import Defaults
import KeyboardShortcuts
import WebKit
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @Test func newNoteIsNotCreatedWithoutContent() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = VaultStore.createOrUpdateNote(
            title: "Only Title",
            text: "   \n",
            fallbackDate: "2026-06-01 13-30"
        )

        #expect(note == nil)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: temporaryVaultURL.path))?.isEmpty == true)
    }

    @Test func newNoteResumeIntervalUsesSavedAllowedValue() {
        defer {
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.resumeIntervalMinutesKey)
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.sessionStartedAtKey)
            Defaults.reset(.newNoteResumeIntervalMinutes)
        }

        NewNotePreferences.setResumeIntervalMinutes(3)
        NewNotePreferences.startSession(now: Date(timeIntervalSince1970: 100))

        #expect(NewNotePreferences.resumeIntervalMinutes == 3)
        #expect(NewNotePreferences.shouldResumeVisibleSession(now: Date(timeIntervalSince1970: 279)))
        #expect(!NewNotePreferences.shouldResumeVisibleSession(now: Date(timeIntervalSince1970: 281)))
    }

    @Test func newNoteResumeIntervalRefreshesOnDraftActivity() {
        defer {
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.sessionStartedAtKey)
            Defaults.reset(.newNoteResumeIntervalMinutes)
        }

        NewNotePreferences.setResumeIntervalMinutes(3)
        NewNotePreferences.startSession(now: Date(timeIntervalSince1970: 100))
        NewNotePreferences.touchSession(now: Date(timeIntervalSince1970: 250))

        #expect(NewNotePreferences.shouldResumeVisibleSession(now: Date(timeIntervalSince1970: 429)))
        #expect(!NewNotePreferences.shouldResumeVisibleSession(now: Date(timeIntervalSince1970: 431)))
    }

    @Test func newNotePreferencesRejectUnsupportedIntervals() {
        defer {
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.resumeIntervalMinutesKey)
            Defaults.reset(.newNoteResumeIntervalMinutes)
        }

        NewNotePreferences.setResumeIntervalMinutes(7)

        #expect(NewNotePreferences.resumeIntervalMinutes == 5)
    }

    @Test func newNoteCreatesMarkdownFileWhenContentExists() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        clearNewNoteFolderPreferences()
        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.createOrUpdateNote(
            title: "Project Plan",
            text: "# Plan",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Project Plan.md")
        #expect((try? String(contentsOf: note.url, encoding: .utf8)) == "# Plan")
    }

    @Test func newNoteUsesConfiguredObsidianDefaultFolder() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try #"{"newFileLocation":"folder","newFileFolderPath":"Inbox"}"#.write(
            to: configURL.appendingPathComponent("app.json"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        NewNotePreferences.setUseObsidianNewNoteFolder(true)
        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.createOrUpdateNote(
            title: "",
            text: "Capture",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Inbox/QuickNote 2026-06-01 13-30.md")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent(note.relativePath).path))
    }

    @Test func newNoteCanUseConfiguredSideNoteFolderInsteadOfObsidianDefault() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try #"{"newFileLocation":"folder","newFileFolderPath":"Obsidian Inbox"}"#.write(
            to: configURL.appendingPathComponent("app.json"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        NewNotePreferences.setUseObsidianNewNoteFolder(false)
        NewNotePreferences.setFolderPath("./Side Note Inbox")
        VaultStore.saveVaultURL(temporaryVaultURL)

        let note = try #require(VaultStore.createOrUpdateNote(
            title: "Capture",
            text: "Body",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(NewNotePreferences.folderPath == "Side Note Inbox")
        #expect(note.relativePath == "Side Note Inbox/Capture.md")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent(note.relativePath).path))
        #expect(!FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent("Obsidian Inbox/Capture.md").path))
    }

    @Test func newNoteRejectsUnsafeSideNoteFolderOverride() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outsideURL = temporaryVaultURL.deletingLastPathComponent().appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            try? FileManager.default.removeItem(at: outsideURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        NewNotePreferences.setUseObsidianNewNoteFolder(false)
        NewNotePreferences.setFolderPath("../Outside")
        VaultStore.saveVaultURL(temporaryVaultURL)

        let note = try #require(VaultStore.createOrUpdateNote(
            title: "Capture",
            text: "Body",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Capture.md")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent("Capture.md").path))
        #expect(!FileManager.default.fileExists(atPath: outsideURL.appendingPathComponent("Capture.md").path))
    }

    @Test func newNoteRejectsUnsafeConfiguredDefaultFolder() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        let outsideURL = temporaryVaultURL.deletingLastPathComponent().appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try #"{"newFileLocation":"folder","newFileFolderPath":"../Outside"}"#.write(
            to: configURL.appendingPathComponent("app.json"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            try? FileManager.default.removeItem(at: outsideURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        NewNotePreferences.setUseObsidianNewNoteFolder(true)
        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.createOrUpdateNote(
            title: "Capture",
            text: "Body",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Capture.md")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent("Capture.md").path))
        #expect(!FileManager.default.fileExists(atPath: outsideURL.appendingPathComponent("Capture.md").path))
    }

    @Test func newNoteTitleRenameUpdatesExistingFile() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        clearNewNoteFolderPreferences()
        VaultStore.saveVaultURL(temporaryVaultURL)
        let original = try #require(VaultStore.createOrUpdateNote(
            title: "QuickNote 2026-06-01 13-30",
            text: "Capture",
            fallbackDate: "2026-06-01 13-30"
        ))
        let renamed = try #require(VaultStore.rename(original, toTitle: "Meeting Notes"))

        #expect(renamed.relativePath == "Meeting Notes.md")
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
        #expect((try? String(contentsOf: renamed.url, encoding: .utf8)) == "Capture")
    }

    private func clearNewNoteFolderPreferences() {
        UserDefaults.standard.removeObject(forKey: NewNotePreferences.useObsidianNewNoteFolderKey)
        UserDefaults.standard.removeObject(forKey: NewNotePreferences.folderPathKey)
    }

    @Test func vaultSearchFindsMarkdownAndSkipsObsidianMetadata() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = temporaryVaultURL.appendingPathComponent("Projects", isDirectory: true)
        let metadataURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "# Plan".write(to: nestedURL.appendingPathComponent("Project Plan.md"), atomically: true, encoding: .utf8)
        try "cache".write(to: metadataURL.appendingPathComponent("Internal.md"), atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let results = VaultStore.markdownNotes(matching: "plan")

        #expect(results.map(\.relativePath) == ["Projects/Project Plan.md"])
    }

    @Test func vaultSearchIndexInvalidatesAfterWrite() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            clearNewNoteFolderPreferences()
        }

        clearNewNoteFolderPreferences()
        VaultStore.saveVaultURL(temporaryVaultURL)
        #expect(VaultStore.markdownNotes().isEmpty)

        let note = try #require(VaultStore.createOrUpdateNote(
            title: "Indexed Later",
            text: "Body",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Indexed Later.md")
        #expect(VaultStore.markdownNotes(matching: "later").map(\.relativePath) == ["Indexed Later.md"])
    }

    @Test func vaultSearchFindsFuzzyAbbreviationMatches() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryVaultURL.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        try "Body".write(
            to: temporaryVaultURL.appendingPathComponent("Projects/Image Paste Regression.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: temporaryVaultURL.appendingPathComponent("Projects/Keyboard Shortcut Bugs.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: temporaryVaultURL.appendingPathComponent("Daily Note.md"),
            atomically: true,
            encoding: .utf8
        )

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.markdownNotes(matching: "ipr").map(\.relativePath).first == "Projects/Image Paste Regression.md")
        #expect(VaultStore.markdownNotes(matching: "ksb").map(\.relativePath).first == "Projects/Keyboard Shortcut Bugs.md")
    }

    @Test func vaultSearchScopesSlashQueriesToDirectorySubtree() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scopedDirectory = temporaryVaultURL.appendingPathComponent("0009 Persönliches/00 Inbox", isDirectory: true)
        let siblingDirectory = temporaryVaultURL.appendingPathComponent("0009 Persönliches/01 Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: scopedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        try "Body".write(
            to: scopedDirectory.appendingPathComponent("Budapest Ideas.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: scopedDirectory.appendingPathComponent("Plain Inbox.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: siblingDirectory.appendingPathComponent("Budapest Archive.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: temporaryVaultURL.appendingPathComponent("Budapest Root.md"),
            atomically: true,
            encoding: .utf8
        )

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.markdownNotes(matching: "Budapest").map(\.relativePath).contains("0009 Persönliches/01 Archive/Budapest Archive.md"))
        #expect(VaultStore.markdownNotes(matching: "0009 Persönliches/00 Inbox/Budapest").map(\.relativePath) == [
            "0009 Persönliches/00 Inbox/Budapest Ideas.md"
        ])
    }

    @Test func vaultSearchTrailingSlashListsOnlyDirectorySubtree() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scopedDirectory = temporaryVaultURL.appendingPathComponent("Projects/Active", isDirectory: true)
        let nestedDirectory = scopedDirectory.appendingPathComponent("Nested", isDirectory: true)
        let siblingDirectory = temporaryVaultURL.appendingPathComponent("Projects/Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        try "Body".write(
            to: scopedDirectory.appendingPathComponent("Alpha.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: nestedDirectory.appendingPathComponent("Beta.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Body".write(
            to: siblingDirectory.appendingPathComponent("Gamma.md"),
            atomically: true,
            encoding: .utf8
        )

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.markdownNotes(matching: "Projects/Active/").map(\.relativePath) == [
            "Projects/Active/Alpha.md",
            "Projects/Active/Nested/Beta.md"
        ])
    }

    @Test func vaultSearchCanLimitRankedResultsForLazySuggestionRendering() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        for index in 0..<8 {
            try "Body".write(
                to: temporaryVaultURL.appendingPathComponent(String(format: "Note %02d.md", index)),
                atomically: true,
                encoding: .utf8
            )
        }

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.markdownNotes(matching: "note", limit: 3).map(\.relativePath) == [
            "Note 00.md",
            "Note 01.md",
            "Note 02.md"
        ])
    }

    @MainActor
    @Test func editVaultFileEmptySearchDoesNotPopulateVaultResults() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
        }

        try "Body".write(to: temporaryVaultURL.appendingPathComponent("Existing.md"), atomically: true, encoding: .utf8)
        VaultStore.saveVaultURL(temporaryVaultURL)

        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.vaultSearchQuery = ""
        viewModel.searchQueryDidChange()

        #expect(viewModel.searchResults.isEmpty)
    }

    @MainActor
    @Test func editVaultFileSearchKeepsAllMatchesNavigable() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
        }

        for index in 0..<12 {
            try "Body".write(
                to: temporaryVaultURL.appendingPathComponent(String(format: "Note %02d.md", index)),
                atomically: true,
                encoding: .utf8
            )
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.highlightedSearchIndex = 11
        viewModel.vaultSearchQuery = "Note"
        viewModel.searchQueryDidChange()

        #expect(viewModel.searchResults.count == 12)
        #expect(viewModel.highlightedSearchIndex == 11)
    }

    @MainActor
    @Test func editVaultFileRestoresSelectedDraftPathAndLoadsContent() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let personalFolder = "0009 Perso\u{0308}nliches"
        let noteDirectory = temporaryVaultURL.appendingPathComponent("\(personalFolder)/00 Inbox", isDirectory: true)
        let relativePath = "\(personalFolder)/00 Inbox/00 Inbox.md"
        let persistedPathWithLiteralCombiningEscape = "0009 Persou0308nliches/00 Inbox/00 Inbox.md"
        let noteURL = temporaryVaultURL.appendingPathComponent(relativePath)
        let noteBody = "# 00 Inbox\n\nThis content must be visible."

        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        try noteBody.write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.path")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.text")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        UserDefaults.standard.set(persistedPathWithLiteralCombiningEscape, forKey: "draft.editVaultFile.path")
        UserDefaults.standard.set(persistedPathWithLiteralCombiningEscape, forKey: "draft.editVaultFile.search")
        UserDefaults.standard.set("", forKey: "draft.editVaultFile.text")

        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.start(clearSearchFocus: {}, focusEditor: {})
        defer { viewModel.stop() }

        #expect(viewModel.selectedNote?.relativePath == relativePath)
        #expect(viewModel.noteTitle == relativePath)
        #expect(viewModel.vaultSearchQuery == relativePath)
        #expect(viewModel.noteText == noteBody)
        #expect(viewModel.saveErrorMessage == nil)
        #expect(UserDefaults.standard.string(forKey: "draft.editVaultFile.path") == relativePath)
        #expect(UserDefaults.standard.string(forKey: "draft.editVaultFile.search") == relativePath)
    }

    @MainActor
    @Test func editVaultFileReloadsExternalFileChangesBeforeNextAutosave() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        let noteURL = temporaryVaultURL.appendingPathComponent("Draft.md")
        try "Before".write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.text")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.path")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.note(relativePath: "Draft.md"))
        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.selectNote(note)
        defer { viewModel.stop() }

        try "Changed in Obsidian".write(to: noteURL, atomically: true, encoding: .utf8)
        viewModel.syncActiveNoteFromDiskIfNeeded()

        #expect(viewModel.noteText == "Changed in Obsidian")
        #expect(try VaultStore.readNote(note) == "Changed in Obsidian")

        viewModel.noteText += "\nSide Note continues from latest disk text"
        viewModel.textDidChange()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(try VaultStore.readNote(note) == "Changed in Obsidian\nSide Note continues from latest disk text")
    }

    @MainActor
    @Test func editVaultFileExternalChangeCancelsPendingStaleAutosave() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        let noteURL = temporaryVaultURL.appendingPathComponent("Draft.md")
        try "Original".write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.text")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.path")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.note(relativePath: "Draft.md"))
        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.selectNote(note)
        defer { viewModel.stop() }

        viewModel.noteText = "Stale Side Note edit"
        viewModel.textDidChange()
        try "External Obsidian edit wins".write(to: noteURL, atomically: true, encoding: .utf8)
        viewModel.syncActiveNoteFromDiskIfNeeded()

        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(viewModel.noteText == "External Obsidian edit wins")
        #expect(try VaultStore.readNote(note) == "External Obsidian edit wins")
    }

    @MainActor
    @Test func newNoteMonitorReloadsExternalChangesAutomatically() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            NewNotePreferences.clearDraft()
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let viewModel = ContentViewModel(mode: .newNote)
        viewModel.noteTitle = "Draft"
        viewModel.noteText = "Created in Side Note"
        viewModel.textDidChange()
        defer { viewModel.stop() }

        let note = try #require(viewModel.createdNewNote)
        #expect(try VaultStore.readNote(note) == "Created in Side Note")

        try await Task.sleep(nanoseconds: 100_000_000)
        try "Changed in Obsidian".write(to: note.url, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(2)
        while viewModel.noteText != "Changed in Obsidian" && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(viewModel.noteText == "Changed in Obsidian")

        viewModel.noteText += "\nSide Note continues from latest disk text"
        viewModel.textDidChange()

        #expect(try VaultStore.readNote(note) == "Changed in Obsidian\nSide Note continues from latest disk text")
    }

    @MainActor
    @Test func editVaultFileMonitorReloadsExternalChangesAutomatically() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        let noteURL = temporaryVaultURL.appendingPathComponent("Draft.md")
        try "Original".write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.text")
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.path")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.note(relativePath: "Draft.md"))
        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.selectNote(note)
        defer { viewModel.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)
        try "Automatic external update".write(to: noteURL, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(2)
        while viewModel.noteText != "Automatic external update" && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(viewModel.noteText == "Automatic external update")
    }

    @Test func vaultWriteUpdatesSelectedMarkdownFile() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        let fileURL = temporaryVaultURL.appendingPathComponent("Draft.md")
        try "Before".write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = VaultNote(relativePath: "Draft.md", title: "Draft", url: fileURL)
        try VaultStore.write("After", to: note)

        #expect(try VaultStore.readNote(note) == "After")
    }

    @Test func noteFileMonitorReportsAtomicExternalWrite() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        let noteURL = temporaryDirectoryURL.appendingPathComponent("Draft.md")
        try "Before".write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        let monitor = VaultNoteFileMonitor(
            callbackQueue: .global(qos: .utility),
            notificationDelay: 0.01
        )
        let didChange = DispatchSemaphore(value: 0)
        monitor.start(url: noteURL) {
            didChange.signal()
        }
        defer { monitor.stop() }

        Thread.sleep(forTimeInterval: 0.05)
        try "After".write(to: noteURL, atomically: true, encoding: .utf8)

        #expect(didChange.wait(timeout: .now() + 2) == .success)
    }

    @Test func vaultStoreResolvesRelativeMarkdownLinksInsideSelectedVault() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let resolvedURL = try #require(VaultStore.url(forMarkdownLink: "Attachments/Image.png"))

        #expect(resolvedURL.path == temporaryVaultURL.appendingPathComponent("Attachments/Image.png").path)
    }

    @Test func vaultStoreRejectsMarkdownLinksOutsideSelectedVault() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.url(forMarkdownLink: "../Secrets.md") == nil)
        #expect(VaultStore.url(forMarkdownLink: "%2E%2E/Secrets.md") == nil)
        #expect(VaultStore.note(relativePath: "../Secrets.md") == nil)
    }

    @Test func vaultStoreRejectsSymlinkEscapesOutsideSelectedVault() throws {
        let temporaryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vaultURL = temporaryRootURL.appendingPathComponent("Vault", isDirectory: true)
        let outsideURL = temporaryRootURL.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outsideURL.appendingPathComponent("secret.png"))
        try FileManager.default.createSymbolicLink(
            at: vaultURL.appendingPathComponent("escape", isDirectory: true),
            withDestinationURL: outsideURL
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryRootURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(vaultURL)

        #expect(VaultStore.url(forMarkdownLink: "escape/secret.png") == nil)
    }

    @Test func vaultStoreResolvesWikiLinksByFileName() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = temporaryVaultURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let linkedURL = nestedURL.appendingPathComponent("Project Plan.md")
        try "# Plan".write(to: linkedURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let resolvedURL = try #require(VaultStore.url(forWikiLink: "Project Plan"))

        #expect(resolvedURL.standardizedFileURL.path == linkedURL.standardizedFileURL.path)
    }

    @Test func vaultStoreConfigurationReflectsSavedVault() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")

        #expect(!VaultStore.isVaultConfigured)

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.isVaultConfigured)
        #expect(VaultStore.selectedVaultName == temporaryVaultURL.lastPathComponent)
    }

}
