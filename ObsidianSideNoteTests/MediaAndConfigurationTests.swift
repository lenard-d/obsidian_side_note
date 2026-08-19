import Testing
import Foundation
import AppKit
import SwiftUI
import Defaults
import KeyboardShortcuts
import WebKit
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @Test func linkPreviewDelayDefaultsToHalfASecondAndPersistsUserChanges() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let originalConfigURL = AppConfigStore.configURLOverride
        AppConfigStore.configURLOverride = configURL
        UserDefaults.standard.removeObject(forKey: LinkPreviewPreferences.hoverDelaySecondsKey)
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: LinkPreviewPreferences.hoverDelaySecondsKey)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        #expect(LinkPreviewPreferences.hoverDelaySeconds == 0.5)

        LinkPreviewPreferences.setHoverDelaySeconds(1.2)

        #expect(LinkPreviewPreferences.hoverDelaySeconds == 1.2)
        #expect(AppConfigStore.read()?.linkPreviewHoverDelaySeconds == 1.2)

        LinkPreviewPreferences.setHoverDelaySeconds(10)

        #expect(LinkPreviewPreferences.hoverDelaySeconds == 5)
        #expect(AppConfigStore.read()?.linkPreviewHoverDelaySeconds == 5)
    }

    @Test func malformedPersistentConfigIsRejectedWithDiagnostics() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        try Data("not-json".utf8).write(to: configURL)

        let originalConfigURL = AppConfigStore.configURLOverride
        let originalLogLevel = AppLogger.minimumLevel
        AppConfigStore.configURLOverride = configURL
        AppLogger.configure(minimumLevel: .off)
        AppLogger.clearRecentEntries()
        defer {
            AppConfigStore.configURLOverride = originalConfigURL
            AppLogger.configure(minimumLevel: originalLogLevel)
            AppLogger.clearRecentEntries()
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        #expect(AppConfigStore.read() == nil)
        #expect(AppLogger.recentEntries.contains { entry in
            entry.category == "app"
                && entry.level == .warn
                && entry.message.contains("unreadable persistent config")
        })
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

    @MainActor
    @Test func markdownEditorCommandDispatcherKeepsTheCurrentCoordinatorConnected() {
        final class Owner {}

        let dispatcher = MarkdownEditorCommandDispatcher()
        let staleOwner = Owner()
        let currentOwner = Owner()
        var receivedCommands: [MarkdownEditorCommand] = []

        dispatcher.connect(owner: staleOwner) { _ in }
        dispatcher.connect(owner: currentOwner) { receivedCommands.append($0) }
        dispatcher.disconnect(owner: staleOwner)
        dispatcher.send(.wrap("**"))

        #expect(receivedCommands == [.wrap("**")])

        dispatcher.disconnect(owner: currentOwner)
        dispatcher.send(.insertLink)
        #expect(receivedCommands == [.wrap("**")])
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
        #expect(try VaultStore.readNote(note) == "Template body")
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
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.useObsidianNewNoteFolderKey)
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.folderPathKey)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        VaultStore.saveVaultURL(vaultURL)
        ShortcutPreference.set("c", modifiers: [.command, .option, .control], for: .newNote)
        NewNotePreferences.setResumeIntervalMinutes(10)
        NewNotePreferences.setUseObsidianNewNoteFolder(false)
        NewNotePreferences.setFolderPath("Side Note Inbox")

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")
        UserDefaults.standard.removeObject(forKey: NewNotePreferences.useObsidianNewNoteFolderKey)
        UserDefaults.standard.removeObject(forKey: NewNotePreferences.folderPathKey)
        KeyboardShortcuts.reset(.createNewNote)
        Defaults.reset(.newNoteResumeIntervalMinutes)

        AppSettingsPersistenceCoordinator.restorePersistedSettingsIfNeeded()

        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == vaultURL.path)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == "Vault")
        #expect(NewNotePreferences.resumeIntervalMinutes == 10)
        #expect(!NewNotePreferences.useObsidianNewNoteFolder)
        #expect(NewNotePreferences.folderPath == "Side Note Inbox")
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
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.useObsidianNewNoteFolderKey)
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.folderPathKey)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        UserDefaults.standard.set(vaultURL.path, forKey: VaultStore.pathKey)
        UserDefaults.standard.set("Vault", forKey: "obsidianVault")
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        NewNotePreferences.setResumeIntervalMinutes(15)
        NewNotePreferences.setUseObsidianNewNoteFolder(false)
        NewNotePreferences.setFolderPath("Side Note Inbox")
        ShortcutPreference.set("n", modifiers: [.command, .option, .control], for: .newNote)

        AppSettingsPersistenceCoordinator.synchronizeCurrentSettings()

        let config = try #require(AppConfigStore.read())
        #expect(config.vaultPath == vaultURL.path)
        #expect(config.vaultName == "Vault")
        #expect(config.newNoteResumeIntervalMinutes == 15)
        #expect(config.useObsidianNewNoteFolder == false)
        #expect(config.newNoteFolderPath == "Side Note Inbox")
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

        AppSettingsPersistenceCoordinator.restorePersistedSettingsIfNeeded()

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

        AppSettingsPersistenceCoordinator.migrateUserDefaults(
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

        AppSettingsPersistenceCoordinator.synchronizeCurrentSettings()

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

        AppSettingsPersistenceCoordinator.synchronizeCurrentSettings()

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

        AppSettingsPersistenceCoordinator.restorePersistedSettingsIfNeeded()

        #expect(UserDefaults.standard.string(forKey: VaultStore.pathKey) == nil)
        #expect(UserDefaults.standard.string(forKey: "obsidianVault") == nil)

        AppSettingsPersistenceCoordinator.synchronizeCurrentSettings()

        let cleanedConfig = try #require(AppConfigStore.read())
        #expect(cleanedConfig.vaultPath == nil)
        #expect(cleanedConfig.vaultName == nil)
    }

    @Test func globalHotKeyMappingSupportsDefaultAndRecordedKeys() {
        #expect(GlobalHotKeyManager.keyCode(for: "d") == 2)
        #expect(GlobalHotKeyManager.keyCode(for: "n") == 45)
        #expect(GlobalHotKeyManager.keyCode(for: "v") == 9)
        #expect(GlobalHotKeyManager.keyCode(for: ",") == 43)
        #expect(GlobalHotKeyManager.keyCode(for: "space") == 49)
        #expect(GlobalHotKeyManager.key(forKeyCode: 49) == "space")
        #expect(GlobalHotKeyManager.keyCode(for: "C") == 8)
    }

    @Test func globalShortcutActionsExcludeLocalAppCommands() {
        #expect(ShortcutAction.globalActions == [.appendDaily, .newNote, .editVaultFile])
        #expect(!ShortcutAction.settings.isGlobal)
        #expect(ShortcutAction.settings.globalShortcutName == nil)
    }

    @Test func localSettingsShortcutDoesNotUseGlobalRecorderName() {
        #expect(!ShortcutAction.settings.isGlobal)
        #expect(ShortcutAction.settings.globalShortcutName == nil)
        #expect(ShortcutAction.settings.recorderShortcutName == nil)
    }

    @Test func settingsShortcutRestoresAsLocalAppShortcutOnly() {
        let settingsName = KeyboardShortcuts.Name("settings")
        let openSettingsName = KeyboardShortcuts.Name("openSettings")
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
        KeyboardShortcuts.setShortcut(nil, for: settingsName)
        KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
            KeyboardShortcuts.setShortcut(nil, for: settingsName)
            KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        }

        ShortcutPreference.restore(
            ShortcutDefinition(key: ",", modifiers: .command),
            for: .settings
        )

        let shortcut = ShortcutPreference.definition(for: .settings)
        #expect(shortcut.key == ",")
        #expect(shortcut.modifiers == .command)
        #expect(KeyboardShortcuts.getShortcut(for: settingsName) == nil)
        #expect(KeyboardShortcuts.getShortcut(for: openSettingsName) == nil)
    }

    @MainActor
    @Test func settingsShortcutChangesUpdateLocalPreferenceOnly() {
        let settingsName = KeyboardShortcuts.Name("settings")
        let openSettingsName = KeyboardShortcuts.Name("openSettings")
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
        KeyboardShortcuts.setShortcut(nil, for: settingsName)
        KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
            KeyboardShortcuts.setShortcut(nil, for: settingsName)
            KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        }

        ShortcutPreference.set("s", modifiers: [.command, .shift], for: .settings)

        let shortcut = ShortcutPreference.definition(for: .settings)
        #expect(shortcut.key == "s")
        #expect(shortcut.modifiers == [.command, .shift])
        #expect(KeyboardShortcuts.getShortcut(for: settingsName) == nil)
        #expect(KeyboardShortcuts.getShortcut(for: openSettingsName) == nil)
        #expect(ShortcutAction.settings.globalShortcutName == nil)
    }

    @MainActor
    @Test func localSettingsShortcutReadsLegacyLocalValueWithoutRecorderMigration() {
        let settingsName = KeyboardShortcuts.Name("settings")
        let openSettingsName = KeyboardShortcuts.Name("openSettings")
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
        KeyboardShortcuts.setShortcut(nil, for: settingsName)
        KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        defer {
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.preferenceKey)
            UserDefaults.standard.removeObject(forKey: ShortcutAction.settings.modifierPreferenceKey)
            KeyboardShortcuts.setShortcut(nil, for: settingsName)
            KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        }

        UserDefaults.standard.set("s", forKey: ShortcutAction.settings.preferenceKey)
        UserDefaults.standard.set(1 << 0 | 1 << 3, forKey: ShortcutAction.settings.modifierPreferenceKey)

        let shortcut = ShortcutPreference.definition(for: .settings)

        #expect(shortcut.key == "s")
        #expect(shortcut.modifiers == [.command, .shift])
        #expect(KeyboardShortcuts.getShortcut(for: settingsName) == nil)
        #expect(KeyboardShortcuts.getShortcut(for: openSettingsName) == nil)
    }

    @Test func obsoleteGlobalSettingsShortcutsAreCleared() {
        let settingsName = KeyboardShortcuts.Name("settings")
        let openSettingsName = KeyboardShortcuts.Name("openSettings")
        KeyboardShortcuts.setShortcut(
            ShortcutPreference.keyboardShortcut(key: ",", modifiers: .command),
            for: settingsName
        )
        KeyboardShortcuts.setShortcut(
            ShortcutPreference.keyboardShortcut(key: ",", modifiers: .command),
            for: openSettingsName
        )
        defer {
            KeyboardShortcuts.setShortcut(nil, for: settingsName)
            KeyboardShortcuts.setShortcut(nil, for: openSettingsName)
        }

        ShortcutPreference.cleanupObsoleteSettingsShortcutRegistration()

        #expect(KeyboardShortcuts.getShortcut(for: settingsName) == nil)
        #expect(KeyboardShortcuts.getShortcut(for: openSettingsName) == nil)
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

}
