//
//  ObsidianSideNoteTests.swift
//  ObsidianSideNoteTests
//
//  Created by Luke  on 11/27/25.
//

import Testing
import Foundation
import AppKit
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
        VaultStore.write("After", to: note)

        #expect(VaultStore.read(note) == "After")
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

    @Test func embeddedMediaParsesImagesAndVideos() throws {
        let image = try #require(EmbeddedMedia(markdownLine: "![Sketch](https://example.com/sketch.png)"))
        let video = try #require(EmbeddedMedia(markdownLine: "![Clip](Attachments/demo.mp4)"))

        #expect(image.title == "Sketch")
        #expect(image.link == "https://example.com/sketch.png")
        #expect(video.title == "Clip")
        #expect(video.link == "Attachments/demo.mp4")
        #expect(EmbeddedMedia(markdownLine: "[Sketch](https://example.com/sketch.png)") == nil)
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

    @Test func shortcutPreferencesStoreModifiersAndKey() {
        UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.modifierPreferenceKey)

        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.newNote.modifierPreferenceKey)
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
    }

    @Test func globalShortcutsUseRequestedDefaultKeys() {
        #expect(ShortcutAction.newNote.defaultKey == "n")
        #expect(ShortcutAction.appendDaily.defaultKey == "d")
        #expect(ShortcutAction.editVaultFile.defaultKey == "v")
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

}
