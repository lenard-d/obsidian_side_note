//
//  ObsidianSideNoteTests.swift
//  ObsidianSideNoteTests
//
//  Created by Luke  on 11/27/25.
//

import Testing
import Foundation
import AppKit
import SwiftUI
import Defaults
import KeyboardShortcuts
import STTextView
import WebKit
@testable import ObsidianSideNote

@Suite(.serialized)
struct ObsidianSideNoteTests {

    @Test func newNoteIsNotCreatedWithoutContent() throws {
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
        }

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
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.createOrUpdateNote(
            title: "",
            text: "Capture",
            fallbackDate: "2026-06-01 13-30"
        ))

        #expect(note.relativePath == "Inbox/QuickNote 2026-06-01 13-30.md")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent(note.relativePath).path))
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
        }

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
        }

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
        }

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
        #expect(VaultStore.read(note) == "Changed in Obsidian")

        viewModel.noteText += "\nSide Note continues from latest disk text"
        viewModel.textDidChange()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(VaultStore.read(note) == "Changed in Obsidian\nSide Note continues from latest disk text")
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
        #expect(VaultStore.read(note) == "External Obsidian edit wins")
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
        #expect(VaultStore.read(note) == "Created in Side Note")

        try await Task.sleep(nanoseconds: 100_000_000)
        try "Changed in Obsidian".write(to: note.url, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(2)
        while viewModel.noteText != "Changed in Obsidian" && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(viewModel.noteText == "Changed in Obsidian")

        viewModel.noteText += "\nSide Note continues from latest disk text"
        viewModel.textDidChange()

        #expect(VaultStore.read(note) == "Changed in Obsidian\nSide Note continues from latest disk text")
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

        #expect(VaultStore.read(note) == "After")
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

    @Test func embeddedMediaParsesImagesAndVideos() throws {
        let image = try #require(EmbeddedMedia(markdownLine: "![Sketch](https://example.com/sketch.png)"))
        let video = try #require(EmbeddedMedia(markdownLine: "![Clip](Attachments/demo.mp4)"))
        let wikiImage = try #require(EmbeddedMedia(markdownLine: "![[Pasted Image.png]]"))
        let wikiImageWithAlias = try #require(EmbeddedMedia(markdownLine: "![[assets/Pasted Image.png|Paste]]"))

        #expect(image.title == "Sketch")
        #expect(image.link == "https://example.com/sketch.png")
        #expect(video.title == "Clip")
        #expect(video.link == "Attachments/demo.mp4")
        #expect(wikiImage.title == "Pasted Image")
        #expect(wikiImage.link == "Pasted Image.png")
        #expect(wikiImageWithAlias.title == "Paste")
        #expect(wikiImageWithAlias.link == "assets/Pasted Image.png")
        #expect(EmbeddedMedia(markdownLine: "[Sketch](https://example.com/sketch.png)") == nil)
    }

    @Test func markdownRenderBlocksRewriteInlineWikiLinksToObsidianURIs() throws {
        let blocks = MarkdownRenderBlock.blocks(from: "See [[Projects/Side Note.md|Side Note]] today.")
        let block = try #require(blocks.first)

        guard case .markdown(let markdown) = block.kind else {
            Issue.record("Expected inline wiki link to remain inside a Markdown block")
            return
        }

        #expect(markdown.contains("[Side Note](obsidian://open?"))
        #expect(markdown.contains("file=Projects/Side%20Note.md"))
        #expect(!markdown.contains("[[Projects/Side Note.md|Side Note]]"))
    }

    @MainActor
    @Test func editorRendererStylesMarkdownHeadingsWithoutChangingSource() throws {
        let source = "# One\n### Three\n###### Six\n#NoSpace"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)

        let h1TextLocation = (rendered.string as NSString).range(of: "One").location
        let h1Font = try #require(rendered.attribute(.font, at: h1TextLocation, effectiveRange: nil) as? NSFont)
        let h3Location = (rendered.string as NSString).range(of: "Three").location
        let h3Font = try #require(rendered.attribute(.font, at: h3Location, effectiveRange: nil) as? NSFont)
        let h6Location = (rendered.string as NSString).range(of: "Six").location
        let h6Font = try #require(rendered.attribute(.font, at: h6Location, effectiveRange: nil) as? NSFont)
        let plainLocation = (rendered.string as NSString).range(of: "#NoSpace").location
        let plainFont = try #require(rendered.attribute(.font, at: plainLocation, effectiveRange: nil) as? NSFont)

        #expect(h1Font.pointSize > h3Font.pointSize)
        #expect(h3Font.pointSize > h6Font.pointSize)
        #expect(plainFont.pointSize == 16)
        #expect(rendered.string.contains("# "))
    }

    @MainActor
    @Test func mediaTextViewInitializesEditableTextSystem() {
        let textView = MediaTextView()

        #expect(textView.textStorage != nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.textContainer.widthTracksTextView)
        #expect(textView.isEditable)
        #expect(textView.isSelectable)
    }

    @MainActor
    @Test func mediaTextViewAcceptsTypingAfterEmptyRender() {
        let window = NSWindow()
        let textView = MediaTextView()
        textView.isEditable = true
        textView.isSelectable = true
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.setAttributedString(NSAttributedString(string: ""))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))

        #expect(textView.string == "a")
    }

    @MainActor
    @Test func mediaTextViewExpandsDocumentHeightForScrolling() {
        let textView = MediaTextView()
        textView.configureForVerticalScrolling(contentSize: NSSize(width: 320, height: 160))
        textView.string = (0..<80).map { "Line \($0)" }.joined(separator: "\n")
        textView.resizeToFitTextContent()

        #expect(textView.isVerticallyResizable)
        #expect(!textView.isHorizontallyResizable)
        #expect(textView.textContainer.heightTracksTextView == false)
        #expect(textView.frame.height > 160)
    }

    @MainActor
    @Test func mediaTextViewUsesDocumentTopPaddingWithoutBottomScrollInset() throws {
        let scrollView = MediaScrollView()
        let textView = MediaTextView()
        scrollView.documentView = textView

        scrollView.configureEditorTopPadding(8)
        textView.configureHorizontalEditorPadding(10)
        textView.configureForVerticalScrolling(contentSize: NSSize(width: 320, height: 160))
        textView.setAttributedString(MarkdownEditorTextRenderer.attributedString(from: "Body", mediaWidth: 280))

        let insets = scrollView.contentView.contentInsets

        #expect(textView.horizontalEditorPadding == 10)
        #expect(textView.textContainer.lineFragmentPadding == 10)
        #expect(insets.top == 8)
        #expect(insets.left == 0)
        #expect(insets.bottom == 0)
        #expect(insets.right == 0)
    }

    @MainActor
    @Test func mediaTextViewRoutesMarkdownCommandShortcutsThroughDelegate() throws {
        let textView = MediaTextView()
        let delegate = MediaTextViewProbe()
        textView.markdownCommandDelegate = delegate

        let boldEvent = try #require(commandKeyEvent("b"))
        let italicEvent = try #require(commandKeyEvent("i"))
        let highlightEvent = try #require(commandKeyEvent("h"))

        #expect(textView.performKeyEquivalent(with: boldEvent))
        #expect(textView.performKeyEquivalent(with: italicEvent))
        #expect(textView.performKeyEquivalent(with: highlightEvent))
        #expect(delegate.requestedWrappers == ["**", "*", "=="])
    }

    @MainActor
    @Test func mediaTextViewRecognizesOnlyTaskCheckboxGlyphAsToggleTarget() {
        let textView = MediaTextView()
        let rendered = MarkdownEditorTextRenderer.attributedString(from: "- [ ] Task", mediaWidth: 400)
        textView.setAttributedString(rendered)

        #expect(textView.taskCheckboxLocation(atVisibleLocation: 0) == nil)
        #expect(textView.taskCheckboxLocation(atVisibleLocation: 1) == nil)
        #expect(textView.taskCheckboxLocation(atVisibleLocation: 2) == 2)
        #expect(textView.taskCheckboxLocation(atVisibleLocation: 3) == 3)
        #expect(textView.taskCheckboxLocation(atVisibleLocation: 4) == 4)
        #expect(textView.taskCheckboxLocation(atVisibleLocation: 5) == nil)
    }

    @MainActor
    @Test func mediaTextViewInsertedNewlineIsPreservedInMarkdownSnapshot() {
        let textView = MediaTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.setAttributedString(MarkdownEditorTextRenderer.attributedString(from: "First", mediaWidth: 400))
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.insertNewline(nil)
        textView.insertText("Second", replacementRange: textView.selectedRange())

        let markdown = MarkdownEditorTextRenderer.markdownString(from: textView.attributedString())
        #expect(markdown == "First\nSecond")
    }

    @MainActor
    @Test func mediaTextViewRoutesListEditingCommandsThroughDelegate() {
        let textView = MediaTextView()
        let delegate = MediaTextViewProbe()
        textView.listEditingDelegate = delegate

        textView.insertNewline(nil)
        textView.insertTab(nil)
        textView.insertBacktab(nil)

        #expect(delegate.smartNewlineRequestCount == 1)
        #expect(delegate.indentRequestCount == 1)
        #expect(delegate.outdentRequestCount == 1)
    }

    @MainActor
    @Test func mediaTextViewPasteLetsMediaDelegateConsumePaste() {
        let textView = MediaTextView()
        let delegate = MediaTextViewProbe()
        delegate.shouldConsumePaste = true
        textView.mediaDelegate = delegate

        textView.paste(nil)

        #expect(delegate.pasteRequestCount == 1)
    }

    @MainActor
    @Test func markdownCommandApplierWrapsSelectedText() {
        let textView = NSTextView()
        textView.string = "make bold"
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        MarkdownEditorCommandApplier.apply(.wrap("**"), in: textView)

        #expect(textView.string == "make **bold**")
        #expect(textView.selectedRange() == NSRange(location: 5, length: 8))
    }

    @MainActor
    @Test func markdownCommandApplierWrapsSelectedTextInMediaTextView() {
        let textView = MediaTextView()
        textView.string = "make bold"
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        MarkdownEditorCommandApplier.apply(.wrap("**"), in: textView)

        #expect(textView.string == "make **bold**")
        #expect(textView.textSelection == NSRange(location: 5, length: 8))
    }

    @MainActor
    @Test func markdownCommandApplierInsertsLinkWithSelectedText() {
        let textView = NSTextView()
        textView.string = "open doc"
        textView.setSelectedRange(NSRange(location: 5, length: 3))

        MarkdownEditorCommandApplier.apply(.insertLink, in: textView)

        #expect(textView.string == "open [doc](url)")
        #expect(textView.selectedRange() == NSRange(location: 5, length: 10))
    }

    @MainActor
    @Test func markdownCommandApplierPrefixesCurrentLine() {
        let textView = NSTextView()
        textView.string = "first\nsecond"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        MarkdownEditorCommandApplier.apply(.insertPrefix("- "), in: textView)

        #expect(textView.string == "first\n- second")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))
    }

    @MainActor
    @Test func editorRendererStylesBasicInlineMarkdownWithoutChangingSource() throws {
        let source = "This is ==marked==, **bold**, *italic*, ~~plain~~, and `code`."
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)

        let markedRange = (rendered.string as NSString).range(of: "==marked==")
        let boldRange = (rendered.string as NSString).range(of: "**bold**")
        let italicRange = (rendered.string as NSString).range(of: "*italic*")
        let strikeRange = (rendered.string as NSString).range(of: "~~plain~~")
        let codeRange = (rendered.string as NSString).range(of: "`code`")

        #expect(rendered.attribute(.backgroundColor, at: markedRange.location, effectiveRange: nil) != nil)

        let boldFont = try #require(rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        let italicFont = try #require(rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        #expect(rendered.attribute(.strikethroughStyle, at: strikeRange.location, effectiveRange: nil) == nil)

        let codeFont = try #require(rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
        #expect(codeFont.isFixedPitch)
    }

    @MainActor
    @Test func editorRendererKeepsMarkdownSyntaxStableAcrossActiveLines() throws {
        let source = "==hidden==\n==shown=="
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400, activeLineIndex: 1)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
        let hiddenFont = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(hiddenFont.pointSize == 16)

        let activeLineLocation = (rendered.string as NSString).range(of: "==shown==").location
        #expect(rendered.attribute(.foregroundColor, at: activeLineLocation, effectiveRange: nil) as? NSColor != NSColor.clear)
    }

    @MainActor
    @Test func editorRendererDisplaysTaskListMarkersAsCheckboxesWithoutChangingSource() throws {
        let source = "- [ ] Open\n- [x] Done\n  - [X] Nested"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)

        let openCheckboxLocation = (rendered.string as NSString).range(of: "[ ]").location
        let checkedCheckboxLocation = (rendered.string as NSString).range(of: "[x]").location
        #expect(rendered.attribute(.markdownTaskCheckbox, at: openCheckboxLocation, effectiveRange: nil) != nil)
        #expect(rendered.attribute(.markdownTaskCheckbox, at: checkedCheckboxLocation, effectiveRange: nil) != nil)
        #expect(rendered.attribute(.foregroundColor, at: openCheckboxLocation, effectiveRange: nil) as? NSColor == NSColor.secondaryLabelColor)
        #expect(rendered.attribute(.foregroundColor, at: checkedCheckboxLocation, effectiveRange: nil) as? NSColor == NSColor.systemGreen)
    }

    @MainActor
    @Test func editorRendererKeepsTaskListMarkdownStableOnActiveLine() {
        let source = "- [ ] Hidden\n- [x] Shown"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400, activeLineIndex: 1)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
    }

    @MainActor
    @Test func editorRendererIgnoresTaskMarkerRevealForStableSourceEditing() {
        let source = "- [ ] Hidden\n- [x] Shown"
        let rendered = MarkdownEditorTextRenderer.attributedString(
            from: source,
            mediaWidth: 400,
            activeLineIndex: 1,
            activeTaskMarkerLineIndex: 1
        )

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
    }

    @Test func editorRendererTogglesTaskListItemsInMarkdownSource() throws {
        let source = "- [ ] Open\n- [x] Done\n  - [X] Nested"

        #expect(MarkdownEditorTextRenderer.toggledTaskListItem(in: source, lineIndex: 0) == "- [x] Open\n- [x] Done\n  - [X] Nested")
        #expect(MarkdownEditorTextRenderer.toggledTaskListItem(in: source, lineIndex: 1) == "- [ ] Open\n- [ ] Done\n  - [X] Nested")
        #expect(MarkdownEditorTextRenderer.toggledTaskListItem(in: source, lineIndex: 2) == "- [ ] Open\n- [x] Done\n  - [ ] Nested")
        #expect(MarkdownEditorTextRenderer.toggledTaskListItem(in: source, lineIndex: 99) == nil)
    }

    @Test func editorRendererMapsVisibleCursorOffsetBackToMarkdownSource() {
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "### Test") == 0)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "### Test") == 4)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "==mark==") == 0)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "==mark==") == 4)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "**bold**") == 4)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "- [ ] Task") == 0)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 1, in: "- [ ] Task") == 1)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 2, in: "- [ ] Task") == 2)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 6, in: "- [ ] Task") == 6)
    }

    @Test func editorRendererRecognizesOnlyAdjacentTaskMarkerCursorOffsets() {
        #expect(MarkdownEditorTextRenderer.isTaskMarkerAdjacentVisibleOffset(0, in: "- [ ] Task"))
        #expect(MarkdownEditorTextRenderer.isTaskMarkerAdjacentVisibleOffset(1, in: "- [ ] Task"))
        #expect(!MarkdownEditorTextRenderer.isTaskMarkerAdjacentVisibleOffset(2, in: "- [ ] Task"))
        #expect(!MarkdownEditorTextRenderer.isTaskMarkerAdjacentVisibleOffset(3, in: "- [ ] Task"))
        #expect(!MarkdownEditorTextRenderer.isTaskMarkerAdjacentVisibleOffset(4, in: "- [ ] Task"))
    }

    @Test func editorRendererMapsTaskSourceOffsetsBackToVisibleOffsets() {
        #expect(MarkdownEditorTextRenderer.visibleOffset(forSourceOffset: 0, in: "- [ ] Task") == 0)
        #expect(MarkdownEditorTextRenderer.visibleOffset(forSourceOffset: 5, in: "- [ ] Task") == 5)
        #expect(MarkdownEditorTextRenderer.visibleOffset(forSourceOffset: 6, in: "- [ ] Task") == 6)
        #expect(MarkdownEditorTextRenderer.visibleOffset(forSourceOffset: 7, in: "- [ ] Task") == 7)
        #expect(MarkdownEditorTextRenderer.visibleOffset(forSourceOffset: 10, in: "- [ ] Task") == 10)
    }

    @Test func markdownEditingEngineContinuesTaskListsOnReturn() throws {
        let source = "- [ ] Task"
        let edit = try #require(MarkdownEditingEngine.smartNewline(
            in: source,
            selectedRange: NSRange(location: (source as NSString).length, length: 0)
        ))

        #expect(edit.markdown == "- [ ] Task\n- [ ] ")
        #expect(edit.selectedRange == NSRange(location: (edit.markdown as NSString).length, length: 0))
    }

    @Test func markdownEditingEngineExitsEmptyTaskListWithoutMergingNextLine() throws {
        let source = "- [ ] \nNext"
        let edit = try #require(MarkdownEditingEngine.smartNewline(
            in: source,
            selectedRange: NSRange(location: 6, length: 0)
        ))

        #expect(edit.markdown == "\nNext")
        #expect(edit.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test func markdownEditingEngineContinuesOrderedListsWithNextNumber() throws {
        let source = "1. Item"
        let edit = try #require(MarkdownEditingEngine.smartNewline(
            in: source,
            selectedRange: NSRange(location: (source as NSString).length, length: 0)
        ))

        #expect(edit.markdown == "1. Item\n2. ")
        #expect(edit.selectedRange == NSRange(location: (edit.markdown as NSString).length, length: 0))
    }

    @Test func markdownEditingEngineIndentsAndOutdentsListLines() throws {
        let source = "- Item"
        let indented = try #require(MarkdownEditingEngine.indentLines(
            in: source,
            selectedRange: NSRange(location: (source as NSString).length, length: 0)
        ))
        let outdented = try #require(MarkdownEditingEngine.outdentLines(
            in: indented.markdown,
            selectedRange: indented.selectedRange
        ))

        #expect(indented.markdown == "  - Item")
        #expect(indented.selectedRange == NSRange(location: 8, length: 0))
        #expect(outdented.markdown == source)
        #expect(outdented.selectedRange == NSRange(location: (source as NSString).length, length: 0))
    }

    @MainActor
    @Test func editorRendererKeepsImageMarkdownAsEditableSource() throws {
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
        let relativePath = try #require(VaultStore.saveAttachmentImage(testImage()))
        _ = VaultStore.image(forMediaLink: relativePath, maxPixelWidth: 800)
        let source = "![Pasted](\(relativePath))"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400, activeLineIndex: 0)

        #expect(rendered.string == source)
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
    }

    @Test func editorRendererReportsUncachedImagesForAsyncPreload() {
        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")

        let source = "![Pasted](Attachments/pasted.png)\nText\n![[assets/other.jpg|Other]]"
        let links = MarkdownEditorTextRenderer.imageLinksNeedingPreload(from: source, mediaWidth: 400)

        #expect(links == ["Attachments/pasted.png", "assets/other.jpg"])
    }

    @Test func cachedMediaLookupDoesNotScanVaultBeforeBackgroundPreload() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = temporaryVaultURL.appendingPathComponent("Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try #require(pngData(from: testImage())).write(
            to: nestedURL.appendingPathComponent("Image.png"),
            options: .atomic
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)

        #expect(VaultStore.cachedImage(forMediaLink: "Image.png", maxPixelWidth: 800) == nil)
        #expect(VaultStore.image(forMediaLink: "Image.png", maxPixelWidth: 800) != nil)
        #expect(VaultStore.cachedImage(forMediaLink: "Image.png", maxPixelWidth: 800) != nil)
    }

    @Test func mediaImporterRecognizesSupportedImageAndVideoFiles() {
        #expect(MediaAttachmentImporter.isSupportedMedia(URL(fileURLWithPath: "/tmp/paste.png")))
        #expect(MediaAttachmentImporter.isSupportedMedia(URL(fileURLWithPath: "/tmp/drop.tiff")))
        #expect(MediaAttachmentImporter.isSupportedMedia(URL(fileURLWithPath: "/tmp/clip.mov")))
        #expect(!MediaAttachmentImporter.isSupportedMedia(URL(fileURLWithPath: "/tmp/readme.txt")))
    }

    @Test func mediaImporterSavesImageFromPasteboard() throws {
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
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([testImage()]))

        let relativePath = try #require(MediaAttachmentImporter.importFromPasteboard(pasteboard))
        let attachmentURL = temporaryVaultURL.appendingPathComponent(relativePath)

        #expect(!relativePath.contains("Attachments/"))
        #expect(attachmentURL.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: attachmentURL.path))
    }

    @Test func remoteMediaDownloaderReturnsBodyWithinLimit() throws {
        let body = Data([1, 2, 3, 4])
        RemoteMediaURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(body.count)"]
            )!
            return (response, [body])
        }
        defer { RemoteMediaURLProtocol.handler = nil }

        let result = try downloadRemoteMedia(maxBytes: 8)

        #expect(result.data == body)
        #expect((result.response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func remoteMediaDownloaderRejectsOversizedContentLength() throws {
        RemoteMediaURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "9"]
            )!
            return (response, [Data(repeating: 1, count: 9)])
        }
        defer { RemoteMediaURLProtocol.handler = nil }

        let result = try downloadRemoteMedia(maxBytes: 8)

        #expect(result.data == nil)
        #expect((result.response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func remoteMediaDownloaderRejectsChunksThatExceedLimit() throws {
        RemoteMediaURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, [Data(repeating: 1, count: 4), Data(repeating: 2, count: 5)])
        }
        defer { RemoteMediaURLProtocol.handler = nil }

        let result = try downloadRemoteMedia(maxBytes: 8)

        #expect(result.data == nil)
        #expect((result.response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func mediaImporterRejectsRemoteResponseWithNonMediaContentType() throws {
        let htmlResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/image.png")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        let pngResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/image.png")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        #expect(!MediaAttachmentImporter.isSupportedRemoteMediaResponse(htmlResponse, fileExtension: "png"))
        #expect(MediaAttachmentImporter.isSupportedRemoteMediaResponse(pngResponse, fileExtension: "png"))
    }

    @Test func pastedImageBaseNameUsesCompactTimestamp() {
        let date = Date(timeIntervalSince1970: 1_780_328_430)
        let name = VaultStore.pastedImageBaseName(now: date)

        #expect(name.contains(#/Pasted image \d{8} \d{6}/#))
    }

    @Test func mediaImporterUsesConfiguredObsidianAttachmentFolder() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let obsidianConfigURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidianConfigURL, withIntermediateDirectories: true)
        try #"{"attachmentFolderPath":"./assets"}"#.write(
            to: obsidianConfigURL.appendingPathComponent("app.json"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let relativePath = try #require(VaultStore.saveAttachmentImage(testImage()))

        #expect(relativePath.hasPrefix("assets/"))
        #expect(relativePath.contains(#/Pasted image \d{8} \d{6}\.png/#))
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent(relativePath).path))
    }

    @Test func mediaImporterRejectsUnsafeConfiguredAttachmentFolder() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let obsidianConfigURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        let outsideURL = temporaryVaultURL.deletingLastPathComponent().appendingPathComponent("OutsideAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidianConfigURL, withIntermediateDirectories: true)
        try #"{"attachmentFolderPath":"../OutsideAttachments"}"#.write(
            to: obsidianConfigURL.appendingPathComponent("app.json"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            try? FileManager.default.removeItem(at: outsideURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let relativePath = try #require(VaultStore.saveAttachmentImage(testImage(), suggestedName: "Paste"))

        #expect(relativePath == "Paste.png")
        #expect(FileManager.default.fileExists(atPath: temporaryVaultURL.appendingPathComponent("Paste.png").path))
        #expect(!FileManager.default.fileExists(atPath: outsideURL.appendingPathComponent("Paste.png").path))
    }

    @Test func vaultStoreLoadsImageDataForEmbeddedMedia() throws {
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
        let relativePath = try #require(VaultStore.saveAttachmentImage(testImage()))
        let image = try #require(VaultStore.image(forMediaLink: relativePath))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func vaultStoreCreatesDailyNoteFromObsidianSettingsAndTemplate() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let obsidianConfigURL = temporaryVaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        let templatesURL = temporaryVaultURL.appendingPathComponent("Templates", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidianConfigURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
        try #"{"folder":"Journal","template":"Templates/Daily","format":"YYYY-MM-DD"}"#.write(
            to: obsidianConfigURL.appendingPathComponent("daily-notes.json"),
            atomically: true,
            encoding: .utf8
        )
        try "Template body".write(
            to: templatesURL.appendingPathComponent("Daily.md"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        VaultStore.saveVaultURL(temporaryVaultURL)
        let note = try #require(VaultStore.ensureDailyNoteForToday(now: Date(timeIntervalSince1970: 1_780_328_430)))

        #expect(note.relativePath.hasPrefix("Journal/"))
        #expect(note.relativePath.hasSuffix(".md"))
        #expect(VaultStore.read(note) == "Template body")
    }

    @Test func appendDailyURIUsesSilentOfficialDailyEndpoint() throws {
        let url = try #require(ObsidianURIBuilder.appendDaily(vaultName: "Personal Vault", text: "Log entry"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.scheme == "obsidian")
        #expect(url.host == "daily")
        #expect(components.queryItems?.contains(URLQueryItem(name: "vault", value: "Personal Vault")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "content", value: "\n\nLog entry")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "append", value: nil)) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "silent", value: nil)) == true)
    }

    @Test func ensureDailyURIUsesTemplateAwareDailyEndpoint() throws {
        let url = try #require(ObsidianURIBuilder.ensureDaily(vaultName: "Personal Vault"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.scheme == "obsidian")
        #expect(url.host == "daily")
        #expect(components.queryItems?.contains(URLQueryItem(name: "vault", value: "Personal Vault")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "silent", value: nil)) == true)
        #expect(components.queryItems?.contains(where: { $0.name == "content" }) == false)
        #expect(components.queryItems?.contains(where: { $0.name == "append" }) == false)
    }

    @Test func openDailyURIUsesVisibleDailyEndpoint() throws {
        let url = try #require(ObsidianURIBuilder.openDaily(vaultName: "Personal Vault"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.scheme == "obsidian")
        #expect(url.host == "daily")
        #expect(components.queryItems?.contains(URLQueryItem(name: "vault", value: "Personal Vault")) == true)
        #expect(components.queryItems?.contains(where: { $0.name == "silent" }) == false)
    }

    @MainActor
    @Test func shortcutPreferencesStoreModifiersAndKey() {
        UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.modifierPreferenceKey)
        KeyboardShortcuts.reset(.createNewNote)

        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.modifierPreferenceKey)
            KeyboardShortcuts.reset(.createNewNote)
        }

        #expect(ShortcutPreference.definition(for: .newNote).modifiers == [.command, .option, .control])

        ShortcutPreference.set("c", modifiers: [.control, .option, .command], for: .newNote)
        let shortcut = ShortcutPreference.definition(for: .newNote)

        #expect(shortcut.key == "c")
        #expect(shortcut.modifiers.contains(.control))
        #expect(shortcut.modifiers.contains(.option))
        #expect(shortcut.modifiers.contains(.command))
        #expect(shortcut.displayValue == "⌃⌥⌘ C")
    }

    @MainActor
    @Test func persistentConfigRestoresVaultShortcutAndResumeInterval() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        KeyboardShortcuts.reset(.createNewNote)
        Defaults.reset(.newNoteResumeIntervalMinutes)
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            KeyboardShortcuts.reset(.createNewNote)
            Defaults.reset(.newNoteResumeIntervalMinutes)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        VaultStore.saveVaultURL(vaultURL)
        ShortcutPreference.set("c", modifiers: [.command, .option, .control], for: .newNote)
        NewNotePreferences.setResumeIntervalMinutes(10)

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")
        KeyboardShortcuts.reset(.createNewNote)
        Defaults.reset(.newNoteResumeIntervalMinutes)

        AppConfigStore.restorePersistedSettingsIfNeeded()

        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == vaultURL.path)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == "Vault")
        #expect(NewNotePreferences.resumeIntervalMinutes == 10)
        #expect(ShortcutPreference.definition(for: .newNote).key == "c")
        #expect(ShortcutPreference.definition(for: .newNote).modifiers == [.command, .option, .control])
    }

    @MainActor
    @Test func persistentConfigSynchronizesCurrentDefaultsToFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        KeyboardShortcuts.reset(.createNewNote)
        Defaults.reset(.newNoteResumeIntervalMinutes)
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            KeyboardShortcuts.reset(.createNewNote)
            Defaults.reset(.newNoteResumeIntervalMinutes)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "startAtLogin")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        UserDefaults.standard.set(vaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set("Vault", forKey: "obsidianVault")
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        NewNotePreferences.setResumeIntervalMinutes(15)
        ShortcutPreference.set("n", modifiers: [.command, .option, .control], for: .newNote)

        AppConfigStore.synchronizeCurrentSettings()

        let config = try #require(AppConfigStore.read())
        #expect(config.vaultPath == vaultURL.path)
        #expect(config.vaultName == "Vault")
        #expect(config.newNoteResumeIntervalMinutes == 15)
        #expect(config.startAtLogin == true)
        #expect(config.shortcuts[ShortcutAction.newNote.rawValue]?.key == "n")
        #expect(FileManager.default.fileExists(atPath: configURL.path))
    }

    @MainActor
    @Test func persistentConfigRestoresVaultPathWithoutBookmark() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var config = PersistentAppConfig()
        config.vaultPath = vaultURL.path
        config.vaultName = "Vault"
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")

        AppConfigStore.restorePersistedSettingsIfNeeded()

        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == vaultURL.path)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == "Vault")
        #expect(VaultStore.selectedVaultURL?.standardizedFileURL.path == vaultURL.standardizedFileURL.path)
    }

    @Test func legacySandboxDefaultsMigrationRestoresDraftFileSelection() throws {
        let suiteName = "ObsidianSideNoteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("Keep Existing", forKey: NoteMode.newNote.draftTitleKey)

        AppConfigStore.migrateUserDefaults(
            from: [
                "draft.editVaultFile.path": "Inbox/Existing.md",
                "draft.editVaultFile.search": "Inbox/Existing.md",
                NoteMode.newNote.draftTitleKey: "Legacy Title",
                VaultStore.pathKey: "/Users/example/Vault"
            ],
            to: defaults
        )

        #expect(defaults.string(forKey: "draft.editVaultFile.path") == "Inbox/Existing.md")
        #expect(defaults.string(forKey: "draft.editVaultFile.search") == "Inbox/Existing.md")
        #expect(defaults.string(forKey: VaultStore.pathKey) == "/Users/example/Vault")
        #expect(defaults.string(forKey: NoteMode.newNote.draftTitleKey) == "Keep Existing")
    }

    @MainActor
    @Test func persistentConfigSynchronizePreservesRestorableVaultWhenDefaultsAreEmpty() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let bookmarkData = try vaultURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: "startAtLogin")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var config = PersistentAppConfig()
        config.vaultPath = vaultURL.path
        config.vaultName = "Vault"
        config.vaultBookmarkBase64 = bookmarkData.base64EncodedString()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")

        AppConfigStore.synchronizeCurrentSettings()

        let synchronizedConfig = try #require(AppConfigStore.read())
        #expect(synchronizedConfig.vaultPath == vaultURL.path)
        #expect(synchronizedConfig.vaultName == "Vault")
        #expect(synchronizedConfig.vaultBookmarkBase64 == bookmarkData.base64EncodedString())
    }

    @Test func selectedVaultIgnoresBrokenBookmarkAndFallsBackToStoredPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staleBookmarkURL = temporaryDirectory.appendingPathComponent("Deleted-\(UUID().uuidString)", isDirectory: true)
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: staleBookmarkURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let staleBookmark = try staleBookmarkURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        defer {
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.removeItem(at: staleBookmarkURL)
        UserDefaults.standard.set(staleBookmark, forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.set(vaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set("Vault", forKey: "obsidianVault")

        #expect(VaultStore.selectedVaultURL?.standardizedFileURL.path == vaultURL.standardizedFileURL.path)
        #expect(UserDefaults.standard.data(forKey: VaultStore.bookmarkKey) == nil)
    }

    @Test func selectedVaultPrefersStoredPathOverDifferentValidBookmark() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bookmarkVaultURL = temporaryDirectory.appendingPathComponent("Bookmark-\(UUID().uuidString)", isDirectory: true)
        let storedVaultURL = temporaryDirectory.appendingPathComponent("StoredVault", isDirectory: true)
        try FileManager.default.createDirectory(at: bookmarkVaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storedVaultURL, withIntermediateDirectories: true)
        let bookmarkData = try bookmarkVaultURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        defer {
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        UserDefaults.standard.set(bookmarkData, forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.set(storedVaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set(storedVaultURL.lastPathComponent, forKey: "obsidianVault")

        #expect(VaultStore.selectedVaultURL?.standardizedFileURL.path == storedVaultURL.standardizedFileURL.path)
        #expect(UserDefaults.standard.data(forKey: VaultStore.bookmarkKey) == nil)
    }

    @Test func selectedVaultClearsMissingStoredPathAndName() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingVaultURL = temporaryDirectory.appendingPathComponent("Missing-\(UUID().uuidString)", isDirectory: true)

        defer {
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        UserDefaults.standard.set(missingVaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set(missingVaultURL.lastPathComponent, forKey: "obsidianVault")

        #expect(VaultStore.selectedVaultURL == nil)
        #expect(VaultStore.selectedVaultName == "")
        #expect(VaultStore.selectedVaultPath == "")
        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == nil)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == nil)
    }

    @MainActor
    @Test func persistentConfigDoesNotOverwriteVaultWithMissingPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let missingVaultURL = temporaryDirectory.appendingPathComponent("Missing-\(UUID().uuidString)", isDirectory: true)

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        UserDefaults.standard.set(missingVaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set(missingVaultURL.lastPathComponent, forKey: "obsidianVault")

        AppConfigStore.synchronizeCurrentSettings()

        let config = try #require(AppConfigStore.read())
        #expect(config.vaultPath == nil)
        #expect(config.vaultName == nil)
    }

    @MainActor
    @Test func persistentConfigDoesNotRestoreMissingVaultPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let missingVaultURL = temporaryDirectory.appendingPathComponent("Missing-\(UUID().uuidString)", isDirectory: true)

        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var config = PersistentAppConfig()
        config.vaultPath = missingVaultURL.path
        config.vaultName = missingVaultURL.lastPathComponent
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)

        AppConfigStore.restorePersistedSettingsIfNeeded()

        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == nil)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == nil)

        AppConfigStore.synchronizeCurrentSettings()

        let cleanedConfig = try #require(AppConfigStore.read())
        #expect(cleanedConfig.vaultPath == nil)
        #expect(cleanedConfig.vaultName == nil)
    }

    @Test func shortcutActionsRoundTripThroughGlobalHotKeyIDs() throws {
        for action in ShortcutAction.allCases {
            #expect(ShortcutAction(hotKeyID: action.hotKeyID) == action)
        }
    }

    @Test func globalHotKeyMappingSupportsDefaultAndRecordedKeys() {
        #expect(GlobalHotKeyManager.keyCode(for: "d") == 2)
        #expect(GlobalHotKeyManager.keyCode(for: "n") == 45)
        #expect(GlobalHotKeyManager.keyCode(for: "v") == 9)
        #expect(GlobalHotKeyManager.keyCode(for: ",") == 43)
        #expect(GlobalHotKeyManager.keyCode(for: "C") == 8)
    }

    @Test func globalShortcutActionsExcludeLocalAppCommands() {
        #expect(ShortcutAction.globalActions == [.appendDaily, .newNote, .editVaultFile])
        #expect(!ShortcutAction.settings.isGlobal)
        #expect(ShortcutAction.settings.globalShortcutName == nil)
    }

    @Test func settingsShortcutRestoresAsLocalAppShortcutOnly() {
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
        }

        ShortcutPreference.restore(
            ShortcutDefinition(key: ",", modifiers: .command),
            for: .settings
        )

        let shortcut = ShortcutPreference.definition(for: .settings)
        #expect(shortcut.key == ",")
        #expect(shortcut.modifiers == .command)
    }

    @Test func globalShortcutsUseRequestedDefaultKeys() {
        #expect(ShortcutAction.newNote.defaultKey == "n")
        #expect(ShortcutAction.appendDaily.defaultKey == "d")
        #expect(ShortcutAction.editVaultFile.defaultKey == "v")
    }

    @Test func globalShortcutActionsMapToToggleableNoteModes() {
        #expect(ShortcutAction.appendDaily.noteMode == .appendDaily)
        #expect(ShortcutAction.newNote.noteMode == .newNote)
        #expect(ShortcutAction.editVaultFile.noteMode == .editVaultFile)
        #expect(ShortcutAction.settings.noteMode == nil)
    }

    @Test func onlyNoteModesUseTheMarkdownEditor() {
        #expect(NoteMode.appendDaily.usesTextEditor)
        #expect(NoteMode.newNote.usesTextEditor)
        #expect(NoteMode.editVaultFile.usesTextEditor)
        #expect(!NoteMode.settings.usesTextEditor)
        #expect(!NoteMode.setup.usesTextEditor)
    }

    @Test func noteModesExposeInitialFocusTargets() {
        #expect(NoteMode.newNote.startsWithTitleFocus)
        #expect(!NoteMode.newNote.startsWithEditorFocus)
        #expect(!NoteMode.appendDaily.startsWithTitleFocus)
        #expect(NoteMode.appendDaily.startsWithEditorFocus)
        #expect(!NoteMode.editVaultFile.startsWithTitleFocus)
        #expect(NoteMode.editVaultFile.startsWithEditorFocus)
        #expect(!NoteMode.settings.startsWithTitleFocus)
        #expect(!NoteMode.settings.startsWithEditorFocus)
    }

    @Test func markdownEditorResourceInlinesJavaScriptForSandboxedWKWebView() {
        let html = MarkdownEditorResource.inlineHTML(
            indexHTML: """
            <html>
              <body>
                <main id="editor"></main>
                <script src="editor.js"></script>
              </body>
            </html>
            """,
            editorJavaScript: "window.editor = {}; console.log('</script>');"
        )

        #expect(!html.contains(#"<script src="editor.js"></script>"#))
        #expect(html.contains("window.editor = {};"))
        #expect(html.contains("<\\/script>"))
    }

    @MainActor
    @Test func markdownEditorBundledHTMLInitializesInWKWebViewAndRoundTripsMarkdown() async throws {
        let html = try MarkdownEditorResource.bundledHTML()
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let markdown = "# Inbox\n\n- [ ] visible content"
        try await webView.evaluateJavaScript("window.editor.setMarkdown(\(javaScriptStringLiteral(markdown)));")
        let result = try await webView.evaluateJavaScript("window.editor.getMarkdown();") as? String

        #expect(result == markdown)

        let blankAreaClickMovedCursorToDocumentEnd = try await webView.evaluateJavaScript(
            """
            (() => {
              window.editor.setSelection(0);
              const handled = window.editor.simulateBlankAreaMouseDownForTests();
              const after = window.editor.getSelection();
              return handled === true &&
                after.head === after.docLength &&
                after.anchor === after.docLength;
            })();
            """
        ) as? Bool

        #expect(blankAreaClickMovedCursorToDocumentEnd == true)

        let editorPresentationJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "# One\\n## Two\\n### Heading\\n\\n- [ ] Task\\n- [x] Done\\n- Plain";
              window.editor.setMarkdown(source);
              window.editor.setSelection(source.length);
              const inactiveText = window.editor.visibleTextForTests();
              const checkboxCount = window.editor.taskCheckboxCountForTests();
              const bulletCount = window.editor.bulletMarkerCountForTests();
              const colors = window.editor.textColorsForTests();
              const styles = window.editor.presentationStylesForTests();
              const checkboxToken = source.indexOf("[ ]");
              window.editor.setSelection(checkboxToken);
              const activeCheckboxText = window.editor.visibleTextForTests();
              window.editor.setSelection(source.indexOf("Task"));
              const checkboxSpacerText = window.editor.visibleTextForTests();
              const checkboxSpacerCount = window.editor.taskCheckboxCountForTests();
              const bulletToken = source.indexOf("- Plain");
              window.editor.setSelection(bulletToken + 1);
              const activeBulletText = window.editor.visibleTextForTests();
              window.editor.setSelection(bulletToken + 2);
              const bulletSpacerText = window.editor.visibleTextForTests();
              const bulletSpacerCount = window.editor.bulletMarkerCountForTests();
              window.editor.setSelection(source.indexOf("###") + 4);
              const activeHeadingText = window.editor.visibleTextForTests();
              window.editor.selectAllForTests();
              const selectAllText = window.editor.visibleTextForTests();
              window.editor.setSelection(source.length);
              const checkboxAlignment = window.editor.taskCheckboxAlignmentForTests();
              const checkboxToggle = window.editor.firstTaskCheckboxMetricsForTests();
              return JSON.stringify({
                inactiveText,
                activeCheckboxText,
                checkboxSpacerText,
                checkboxSpacerCount,
                activeBulletText,
                bulletSpacerText,
                bulletSpacerCount,
                activeHeadingText,
                selectAllText,
                checkboxCount,
                bulletCount,
                colors,
                styles,
                checkboxAlignment,
                checkboxToggle
              });
            })();
            """
        ) as? String)
        let editorPresentationData = try #require(editorPresentationJSON.data(using: .utf8))
        let editorPresentation = try #require(
            JSONSerialization.jsonObject(with: editorPresentationData) as? [String: Any]
        )
        let inactiveText = try #require(editorPresentation["inactiveText"] as? String)
        let activeCheckboxText = try #require(editorPresentation["activeCheckboxText"] as? String)
        let checkboxSpacerText = try #require(editorPresentation["checkboxSpacerText"] as? String)
        let checkboxSpacerCount = try #require(editorPresentation["checkboxSpacerCount"] as? Int)
        let activeBulletText = try #require(editorPresentation["activeBulletText"] as? String)
        let bulletSpacerText = try #require(editorPresentation["bulletSpacerText"] as? String)
        let bulletSpacerCount = try #require(editorPresentation["bulletSpacerCount"] as? Int)
        let activeHeadingText = try #require(editorPresentation["activeHeadingText"] as? String)
        let selectAllText = try #require(editorPresentation["selectAllText"] as? String)
        let checkboxCount = try #require(editorPresentation["checkboxCount"] as? Int)
        let bulletCount = try #require(editorPresentation["bulletCount"] as? Int)
        let colors = try #require(editorPresentation["colors"] as? [String])
        let styles = try #require(editorPresentation["styles"] as? [String: Any])
        let checkboxStyles = try #require(styles["checkbox"] as? [String: String])
        let bulletStyles = try #require(styles["bullet"] as? [String: String])
        let headingLines = try #require(styles["headingLines"] as? [[String: Any]])
        let checkboxAlignment = try #require(editorPresentation["checkboxAlignment"] as? [[String: Any]])
        let checkboxToggle = try #require(editorPresentation["checkboxToggle"] as? [String: Any])
        let toggleBefore = try #require(checkboxToggle["before"] as? [String: Int])
        let toggleAfter = try #require(checkboxToggle["after"] as? [String: Int])
        let toggledMarkdown = try #require(checkboxToggle["markdown"] as? String)
        let scrollerLineHeight = try #require(styles["scrollerLineHeight"] as? String)
        let headingFontSizes = headingLines.compactMap { line -> Double? in
            guard let fontSize = line["fontSize"] as? String else { return nil }
            return Double(fontSize.replacingOccurrences(of: "px", with: ""))
        }
        let headingFontWeights = headingLines.compactMap { line -> Double? in
            guard let fontWeight = line["fontWeight"] as? String else { return nil }
            return Double(fontWeight)
        }

        #expect(inactiveText.contains("Heading"))
        #expect(!inactiveText.contains("###"))
        #expect(!inactiveText.contains("- [ ]"))
        #expect(!inactiveText.contains("- Plain"))
        #expect(activeCheckboxText.contains("[ ] Task"))
        #expect(!checkboxSpacerText.contains("[ ]"))
        #expect(checkboxSpacerCount == 2)
        #expect(activeBulletText.contains("- Plain"))
        #expect(!bulletSpacerText.contains("- Plain"))
        #expect(bulletSpacerCount == 1)
        #expect(activeHeadingText.contains("### Heading"))
        #expect(selectAllText.contains("### Heading"))
        #expect(selectAllText.contains("- Plain"))
        #expect(checkboxCount == 2)
        #expect(bulletCount == 1)
        #expect(colors.allSatisfy { $0 == "rgb(255, 255, 255)" })
        #expect(checkboxStyles["borderColor"] == "rgb(255, 255, 255)")
        #expect(checkboxStyles["display"] == "inline-flex")
        #expect(checkboxStyles["alignItems"] == "center")
        #expect(checkboxStyles["justifyContent"] == "center")
        #expect(bulletStyles["text"] == "\u{2022}")
        #expect(bulletStyles["color"] == "rgb(255, 255, 255)")
        #expect(bulletStyles["display"] == "inline-flex")
        #expect(Double(scrollerLineHeight.replacingOccurrences(of: "px", with: "")) ?? 0 > 24)
        #expect(headingFontSizes.count == 3)
        #expect(headingFontSizes[0] > headingFontSizes[1])
        #expect(headingFontSizes[1] > headingFontSizes[2])
        #expect(headingFontSizes[2] > 18)
        #expect(headingFontWeights.count == 3)
        #expect(headingFontWeights[0] > headingFontWeights[1])
        #expect(headingFontWeights[1] > headingFontWeights[2])
        #expect(headingFontWeights[2] >= 700)
        let uncheckedCheckbox = try #require(checkboxAlignment.first { ($0["checked"] as? Bool) == false })
        let checkedCheckbox = try #require(checkboxAlignment.first { ($0["checked"] as? Bool) == true })
        let uncheckedWidth = try #require(uncheckedCheckbox["width"] as? Double)
        let checkedWidth = try #require(checkedCheckbox["width"] as? Double)
        let uncheckedHeight = try #require(uncheckedCheckbox["height"] as? Double)
        let checkedHeight = try #require(checkedCheckbox["height"] as? Double)
        let uncheckedCenterDelta = try #require(uncheckedCheckbox["centerDelta"] as? Double)
        let checkedCenterDelta = try #require(checkedCheckbox["centerDelta"] as? Double)
        let uncheckedTopWithinLine = try #require(uncheckedCheckbox["topWithinLine"] as? Double)
        let checkedTopWithinLine = try #require(checkedCheckbox["topWithinLine"] as? Double)
        #expect(abs(uncheckedWidth - checkedWidth) < 0.5)
        #expect(abs(uncheckedHeight - checkedHeight) < 0.5)
        #expect(abs(uncheckedCenterDelta - checkedCenterDelta) < 0.5)
        #expect(abs(uncheckedTopWithinLine - checkedTopWithinLine) < 0.5)
        #expect(toggleBefore == toggleAfter)
        #expect(toggledMarkdown == "# One\n## Two\n### Heading\n\n- [x] Task\n- [x] Done\n- Plain")
    }

    @MainActor
    @Test func markdownEditorHandlesListIndentationKeysInWebView() async throws {
        let html = try MarkdownEditorResource.bundledHTML()
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let indentationJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              window.editor.setMarkdown("- Item");
              window.editor.setSelection(6);
              const tabHandled = window.editor.dispatchKeyForTests("Tab");
              const afterTab = window.editor.getMarkdown();

              window.editor.setSelection(afterTab.length);
              const enterHandled = window.editor.dispatchKeyForTests("Enter");
              const afterEnter = window.editor.getMarkdown();

              window.editor.setMarkdown("  - Item");
              window.editor.setSelection("  - Item".length);
              const commandShiftTabHandled = window.editor.dispatchKeyForTests("Tab", {
                metaKey: true,
                shiftKey: true
              });
              const afterCommandShiftTab = window.editor.getMarkdown();

              window.editor.setMarkdown("    - ");
              window.editor.setSelection("    - ".length);
              const backspaceHandled = window.editor.dispatchKeyForTests("Backspace");
              const afterBackspace = window.editor.getMarkdown();

              return JSON.stringify({
                tabHandled,
                afterTab,
                enterHandled,
                afterEnter,
                commandShiftTabHandled,
                afterCommandShiftTab,
                backspaceHandled,
                afterBackspace
              });
            })();
            """
        ) as? String)
        let indentationData = try #require(indentationJSON.data(using: .utf8))
        let indentation = try #require(
            JSONSerialization.jsonObject(with: indentationData) as? [String: Any]
        )

        #expect(indentation["tabHandled"] as? Bool == true)
        #expect(indentation["afterTab"] as? String == "  - Item")
        #expect(indentation["enterHandled"] as? Bool == true)
        #expect(indentation["afterEnter"] as? String == "  - Item\n  - ")
        #expect(indentation["commandShiftTabHandled"] as? Bool == true)
        #expect(indentation["afterCommandShiftTab"] as? String == "- Item")
        #expect(indentation["backspaceHandled"] as? Bool == true)
        #expect(indentation["afterBackspace"] as? String == "  - ")
    }

    @MainActor
    @Test func titleFieldReturnCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        let fieldEditor = NSTextView()
        fieldEditor.string = "New Title"

        let handled = coordinator.control(
            textField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled)
        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func titleFieldReturnIgnoringFieldEditorCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        let fieldEditor = NSTextView()
        fieldEditor.string = "New Title"

        let handled = coordinator.control(
            textField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        )

        #expect(handled)
        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func titleFieldDirectReturnKeyCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = ReturnCommittingTextField()
        textField.stringValue = "New Title"

        coordinator.commitReturn(from: textField)

        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func titleFieldReturnCommitAlsoWorksThroughEndEditingNotification() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        textField.stringValue = "New Title"

        coordinator.controlTextDidEndEditing(
            Notification(
                name: NSText.didEndEditingNotification,
                object: textField,
                userInfo: ["NSTextMovement": NSReturnTextMovement]
            )
        )

        #expect(title == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func mediaTextViewDoesNotMoveWindowByBackgroundDrag() {
        let textView = MediaTextView()

        #expect(!textView.mouseDownCanMoveWindow)
    }

    @Test func shortcutPolicyRejectsCommandOnlyGlobalShortcuts() {
        #expect(ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: .command) != nil)
        #expect(ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: [.command, .option]) == nil)
        #expect(ShortcutPolicy.validationMessage(for: .settings, key: ",", modifiers: .command) == nil)
    }

    @Test func shortcutNormalizationKeepsSingleLowercaseKey() {
        #expect(ShortcutPreference.normalized(" N ") == "n")
        #expect(ShortcutPreference.normalized("", fallback: "d") == "d")
    }

    @Test func emptyModifierFlagsDoNotBecomeCommandShortcuts() {
        #expect(ShortcutPreference.menuModifierFlags(from: []) == [])
        #expect(ShortcutPreference.menuModifierFlags(from: .command) == .command)
        #expect(ShortcutPreference.menuModifierFlags(from: [.command, .option]) == [.command, .option])
    }

    @Test func shortcutPolicyRejectsEmptyGlobalShortcutModifiers() {
        let message = ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: [])

        #expect(message == "Global shortcuts need Control or Option so they do not steal normal app commands.")
    }

    @Test @MainActor func keyboardRoutingLetsFocusedTextInputReceivePlainLetters() {
        let window = NSWindow()
        let textView = NSTextView()
        textView.isEditable = true
        window.contentView = textView
        window.makeFirstResponder(textView)

        let plainEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )

        #expect(plainEvent != nil)
        #expect(KeyboardEventRouting.shouldHandleLocalShortcut(plainEvent!) == false)
    }

    @Test @MainActor func keyboardRoutingStillHandlesModifiedShortcutsInTextInput() {
        let window = NSWindow()
        let textView = NSTextView()
        textView.isEditable = true
        window.contentView = textView
        window.makeFirstResponder(textView)

        let commandEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )

        #expect(commandEvent != nil)
        #expect(KeyboardEventRouting.shouldHandleLocalShortcut(commandEvent!) == true)
    }

}

private func testImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 12, height: 12))
    image.lockFocus()
    NSColor.systemPurple.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
    image.unlockFocus()
    return image
}

private func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

private func javaScriptStringLiteral(_ string: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [string])
    guard var literal = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
        return "\"\""
    }

    literal.removeFirst()
    literal.removeLast()
    return literal
}

private final class MarkdownEditorReadyMessageHandler: NSObject, WKScriptMessageHandler {
    var isReady = false
    var errorMessage: String?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        if type == "ready" {
            isReady = true
        } else if type == "error" {
            errorMessage = body["message"] as? String ?? "Unknown editor error"
        }
    }
}

private func downloadRemoteMedia(maxBytes: Int) throws -> (data: Data?, response: URLResponse?) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemoteMediaURLProtocol.self]

    let downloader = RemoteMediaDownloader(maxBytes: maxBytes, configuration: configuration)
    let semaphore = DispatchSemaphore(value: 0)
    let url = URL(string: "https://example.com/media.png")!
    var result: (Data?, URLResponse?)?

    downloader.download(URLRequest(url: url)) { data, response in
        result = (data, response)
        semaphore.signal()
    }

    #expect(semaphore.wait(timeout: .now() + 2) == .success)
    let unwrappedResult = try #require(result)
    return (unwrappedResult.0, unwrappedResult.1)
}

private final class RemoteMediaURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, chunks) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private func commandKeyEvent(_ key: String) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: key,
        charactersIgnoringModifiers: key,
        isARepeat: false,
        keyCode: 0
    )
}

@MainActor
private final class MediaTextViewProbe: MediaTextViewDelegate, MarkdownCommandTextViewDelegate, TaskListTextViewDelegate, MarkdownListEditingTextViewDelegate {
    var shouldConsumePaste = false
    var pasteRequestCount = 0
    var requestedWrappers: [String] = []
    var taskToggleLocations: [Int] = []
    var smartNewlineRequestCount = 0
    var indentRequestCount = 0
    var outdentRequestCount = 0

    func mediaTextViewDidRequestPasteMedia(_ textView: MediaTextView) -> Bool {
        pasteRequestCount += 1
        return shouldConsumePaste
    }

    func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool {
        false
    }

    func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String) {
        requestedWrappers.append(wrapper)
    }

    func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int) {
        taskToggleLocations.append(location)
    }

    func mediaTextViewDidRequestSmartNewline(_ textView: MediaTextView) -> Bool {
        smartNewlineRequestCount += 1
        return true
    }

    func mediaTextViewDidRequestIndent(_ textView: MediaTextView) -> Bool {
        indentRequestCount += 1
        return true
    }

    func mediaTextViewDidRequestOutdent(_ textView: MediaTextView) -> Bool {
        outdentRequestCount += 1
        return true
    }
}
