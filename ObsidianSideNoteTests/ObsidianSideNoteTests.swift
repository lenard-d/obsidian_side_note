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

        #expect(resolvedURL.path == linkedURL.path)
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

    @Test func editorRendererStylesMarkdownHeadingsWithoutChangingSource() throws {
        let source = "# One\n### Three\n###### Six\n#NoSpace"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == "One\nThree\nSix\n#NoSpace")
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
        #expect(!rendered.string.contains("# "))
    }

    @MainActor
    @Test func mediaTextViewInitializesEditableTextSystem() {
        let textView = MediaTextView()

        #expect(textView.textStorage != nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.textContainer != nil)
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
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
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
        #expect(textView.textContainer?.heightTracksTextView == false)
        #expect(textView.frame.height > 160)
    }

    @Test func editorRendererStylesBasicInlineMarkdownWithoutChangingSource() throws {
        let source = "This is ==marked==, **bold**, *italic*, ~~plain~~, and `code`."
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == "This is marked, bold, italic, plain, and code.")
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)

        let markedRange = (rendered.string as NSString).range(of: "marked")
        let boldRange = (rendered.string as NSString).range(of: "bold")
        let italicRange = (rendered.string as NSString).range(of: "italic")
        let strikeRange = (rendered.string as NSString).range(of: "plain")
        let codeRange = (rendered.string as NSString).range(of: "code")

        #expect(rendered.attribute(.backgroundColor, at: markedRange.location, effectiveRange: nil) != nil)

        let boldFont = try #require(rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        let italicFont = try #require(rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        #expect(rendered.attribute(.strikethroughStyle, at: strikeRange.location, effectiveRange: nil) == nil)

        let codeFont = try #require(rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
        #expect(codeFont.isFixedPitch)
    }

    @Test func editorRendererRevealsInlineMarkdownSyntaxOnActiveLineOnly() throws {
        let source = "==hidden==\n==shown=="
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400, activeLineIndex: 1)

        #expect(rendered.string == "hidden\n==shown==")
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
        let hiddenFont = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(hiddenFont.pointSize == 16)

        let activeLineLocation = (rendered.string as NSString).range(of: "==shown==").location
        #expect(rendered.attribute(.foregroundColor, at: activeLineLocation, effectiveRange: nil) as? NSColor != NSColor.clear)
    }

    @Test func editorRendererDisplaysTaskListMarkersAsCheckboxesWithoutChangingSource() throws {
        let source = "- [ ] Open\n- [x] Done\n  - [X] Nested"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400)

        #expect(rendered.string == "\u{2610} Open\n\u{2611} Done\n  \u{2611} Nested")
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)

        let openCheckboxLocation = (rendered.string as NSString).range(of: "\u{2610}").location
        let checkedCheckboxLocation = (rendered.string as NSString).range(of: "\u{2611}").location
        #expect(rendered.attribute(.foregroundColor, at: openCheckboxLocation, effectiveRange: nil) as? NSColor == NSColor.secondaryLabelColor)
        #expect(rendered.attribute(.foregroundColor, at: checkedCheckboxLocation, effectiveRange: nil) as? NSColor == NSColor.systemGreen)
    }

    @Test func editorRendererRevealsTaskListMarkdownSyntaxOnActiveLineOnly() {
        let source = "- [ ] Hidden\n- [x] Shown"
        let rendered = MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: 400, activeLineIndex: 1)

        #expect(rendered.string == "\u{2610} Hidden\n- [x] Shown")
        #expect(MarkdownEditorTextRenderer.markdownString(from: rendered) == source)
    }

    @Test func editorRendererMapsVisibleCursorOffsetBackToMarkdownSource() {
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "### Test") == 4)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "### Test") == 8)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "==mark==") == 2)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "==mark==") == 6)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 4, in: "**bold**") == 6)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 0, in: "- [ ] Task") == 6)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 2, in: "- [ ] Task") == 6)
        #expect(MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: 6, in: "- [ ] Task") == 10)
    }

    @Test func editorRendererKeepsActiveImagePreviewOutOfMarkdownSource() throws {
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

        #expect(rendered.string.contains("\n"))
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
