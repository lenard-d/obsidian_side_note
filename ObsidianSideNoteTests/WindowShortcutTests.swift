import AppKit
import Foundation
import KeyboardShortcuts
import Testing
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @MainActor
    @Test(arguments: [ShortcutAction.appendDaily, .newNote, .editVaultFile])
    func noteShortcutHidesAndRestoresTheSameWindow(action: ShortcutAction) throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let delegate = AppDelegate()
        delegate.performShortcutAction(action)
        let first = try #require(delegate.window)
        defer { first.close() }
        let content = first.contentView

        delegate.performShortcutAction(action)
        #expect(!first.isVisible)
        delegate.performShortcutAction(action)

        #expect(delegate.window === first)
        #expect(first.isVisible)
        #expect(first.contentView === content)
    }

    @MainActor
    @Test(arguments: [ShortcutAction.appendDaily, .newNote, .editVaultFile])
    func shiftShortcutCreatesAnIndependentWindow(action: ShortcutAction) throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let delegate = AppDelegate()
        delegate.performShortcutAction(action)
        let first = try #require(delegate.window)
        defer { first.close() }

        delegate.performShortcutAction(action, inNewWindow: true)
        let second = try #require(delegate.window)
        defer { second.close() }

        #expect(second !== first)
        #expect(first.isVisible && second.isVisible)
        #expect(delegate.mode(for: second) == action.noteMode)
    }

    @MainActor
    @Test func noteShortcutTargetsTheMostRecentlyUsedWindowOfItsMode() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let delegate = AppDelegate()
        delegate.performShortcutAction(.editVaultFile)
        let first = try #require(delegate.window)
        defer { first.close() }
        delegate.performShortcutAction(.editVaultFile, inNewWindow: true)
        let second = try #require(delegate.window)
        defer { second.close() }

        delegate.showWindow(first)
        delegate.openSettings()
        let settings = try #require(delegate.window)
        defer { settings.close() }
        delegate.performShortcutAction(.editVaultFile)

        #expect(!first.isVisible)
        #expect(second.isVisible)
        #expect(settings.isVisible)
        delegate.performShortcutAction(.editVaultFile)
        #expect(delegate.window === first)

        first.close()
        delegate.performShortcutAction(.editVaultFile)
        #expect(!second.isVisible)
    }

    @MainActor
    @Test func newNoteTogglePreservesTheDraftPastTheResumeInterval() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let delegate = AppDelegate()
        delegate.performShortcutAction(.newNote)
        let first = try #require(delegate.window)
        defer { first.close() }
        UserDefaults.standard.set("Keep this draft", forKey: NoteMode.newNote.draftTextKey)
        UserDefaults.standard.set(Date.distantPast, forKey: NewNotePreferences.sessionStartedAtKey)

        delegate.performShortcutAction(.newNote)
        delegate.performShortcutAction(.newNote)

        #expect(delegate.window === first)
        #expect(UserDefaults.standard.string(forKey: NoteMode.newNote.draftTextKey) == "Keep this draft")
    }

    @MainActor
    @Test func shiftGlobalShortcutFollowsAChangedSpaceShortcut() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let manager = GlobalHotKeyManager { _, _ in }
        let name = try #require(ShortcutAction.newNote.newWindowShortcutName)
        ShortcutPreference.set("space", modifiers: [.command, .option, .control], for: .newNote)
        manager.registerAll()
        #expect(KeyboardShortcuts.getShortcut(for: name) == ShortcutPreference.keyboardShortcut(
            key: "space", modifiers: [.command, .option, .control, .shift]
        ))

        ShortcutPreference.set("n", modifiers: [.control, .option], for: .newNote)
        manager.registerAll()
        #expect(KeyboardShortcuts.getShortcut(for: name) == ShortcutPreference.keyboardShortcut(
            key: "n", modifiers: [.control, .option, .shift]
        ))
    }

    @MainActor
    @Test func localSpaceShortcutUsesTheSameToggleAndNewWindowBehavior() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        ShortcutPreference.set("space", modifiers: [.command, .option, .control], for: .newNote)
        let delegate = AppDelegate()
        delegate.performShortcutAction(.newNote)
        let first = try #require(delegate.window)
        defer { first.close() }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option, .control],
            timestamp: 0, windowNumber: first.windowNumber, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        #expect(first.performKeyEquivalent(with: event))
        #expect(!first.isVisible)
        #expect(first.performKeyEquivalent(with: event))
        #expect(first.isVisible)

        let shiftedEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option, .control, .shift],
            timestamp: 0, windowNumber: first.windowNumber, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        #expect(first.performKeyEquivalent(with: shiftedEvent))
        let second = try #require(delegate.window)
        defer { second.close() }
        #expect(second !== first)
        #expect(first.isVisible && second.isVisible)
    }

    @MainActor
    @Test func shortcutPolicyReservesShiftForNewWindows() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        ShortcutPreference.set("v", modifiers: [.command, .option, .control], for: .editVaultFile)

        #expect(ShortcutPolicy.validationMessage(
            for: .newNote, key: "space", modifiers: [.command, .option, .control, .shift]
        ) == "Shift is reserved for opening a new window.")
        #expect(ShortcutPolicy.validationMessage(
            for: .settings, key: "v", modifiers: [.command, .option, .control, .shift]
        ) == "Already used by Edit Vault File.")
    }

    @MainActor
    @Test(arguments: [NoteMode.newNote, .editVaultFile])
    func trashingAnotherNotePreservesTheLatestNewNoteDraft(mode: NoteMode) throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        NewNotePreferences.clearDraft()
        let older = ContentViewModel(mode: .newNote)
        older.noteTitle = "Older"
        older.noteText = "Older body"
        older.textDidChange()
        let oldNote = try #require(older.createdNewNote)
        let latest = ContentViewModel(mode: .newNote)
        latest.noteTitle = "Latest"
        latest.noteText = "Latest body"
        latest.textDidChange()
        let latestNote = try #require(latest.createdNewNote)
        defer { latest.stop() }

        let target: ContentViewModel
        if mode == .newNote {
            target = older
        } else {
            target = ContentViewModel(mode: .editVaultFile)
            target.selectNote(oldNote)
        }
        #expect(target.trashCurrentNote())
        target.stop()
        target.textDidChange()
        target.titleDidChange()

        #expect(UserDefaults.standard.string(forKey: NewNotePreferences.draftFilePathKey) == latestNote.relativePath)
        #expect(UserDefaults.standard.string(forKey: NoteMode.newNote.draftTitleKey) == "Latest")
        #expect(UserDefaults.standard.string(forKey: NoteMode.newNote.draftTextKey) == "Latest body")
        #expect(try VaultStore.readNote(latestNote) == "Latest body")
    }

    @MainActor
    @Test(arguments: [ShortcutDefinition(key: "n", modifiers: [.control, .option, .shift]),
                      ShortcutDefinition(key: "v", modifiers: [.command, .control, .option])])
    func rejectedRecorderChangesRestoreTheAcceptedShortcut(attempt: ShortcutDefinition) throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        ShortcutPreference.set("v", modifiers: [.command, .control, .option], for: .editVaultFile)
        let accepted = ShortcutDefinition(key: "space", modifiers: [.command, .control, .option])
        ShortcutPreference.set(accepted.key, modifiers: accepted.modifiers, for: .newNote)
        let name = try #require(ShortcutAction.newNote.globalShortcutName)
        // Match the recorder's write-before-validation callback order.
        KeyboardShortcuts.setShortcut(ShortcutPreference.keyboardShortcut(key: attempt.key, modifiers: attempt.modifiers), for: name)

        #expect(ShortcutPreference.acceptRecordedShortcut(attempt, previous: accepted, for: .newNote) != nil)
        #expect(ShortcutPreference.definition(for: .newNote) == accepted)
    }

    @MainActor
    @Test func restoringDailyNoteAfterMidnightKeepsYesterdayAndLoadsToday() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let model = ContentViewModel(mode: .appendDaily)
        defer { model.stop() }
        model.setEventWindowNumber(42)
        let yesterday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23))!
        let today = Calendar.current.date(byAdding: .day, value: 1, to: yesterday)!
        model.refreshDailyNote(now: yesterday)
        let oldNote = try #require(model.selectedNote)
        model.noteText = "Yesterday's work"
        model.textDidChange()

        model.windowDidBecomeKey(42, now: today)
        let newNote = try #require(model.selectedNote)

        #expect(oldNote.url != newNote.url)
        #expect(try VaultStore.readNote(oldNote) == "Yesterday's work")
        #expect(model.noteText == (try VaultStore.readNote(newNote)))
    }

    @MainActor
    @Test(arguments: [NoteMode.appendDaily, .editVaultFile])
    func closingAnotherWindowDoesNotRecreateATrashedNote(mode: NoteMode) throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let note = try #require(VaultStore.ensureDailyNoteForToday())
        let deleting = ContentViewModel(mode: mode)
        let other = ContentViewModel(mode: mode)
        deleting.selectNote(note)
        other.selectNote(note)
        other.noteText = "Pending content from another window"
        other.textDidChange()

        #expect(deleting.trashCurrentNote())
        other.stop()
        other.textDidChange()
        deleting.stop()

        #expect(!FileManager.default.fileExists(atPath: note.url.path))
        #expect(other.saveErrorMessage?.contains("Trash") == true)
    }

    @MainActor
    @Test func dailyNoteRecoversAfterVaultSetup() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let vault = try #require(VaultStore.selectedVaultURL)
        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        let model = ContentViewModel(mode: .appendDaily)
        defer { model.stop() }
        model.refreshDailyNote()
        #expect(model.saveErrorMessage != nil)
        VaultStore.saveVaultURL(vault)

        model.refreshDailyNote()

        #expect(model.selectedNote != nil)
        #expect(model.saveErrorMessage == nil)
    }

    @MainActor
    @Test func trashedDailyNoteCanLoadTheNextDayWithoutRestoringTheDeletedFile() throws {
        let fixture = try WindowShortcutFixture()
        defer { fixture.restore() }
        let yesterday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23))!
        let today = Calendar.current.date(byAdding: .day, value: 1, to: yesterday)!
        let deleting = ContentViewModel(mode: .appendDaily)
        let other = ContentViewModel(mode: .appendDaily)
        defer { deleting.stop(); other.stop() }
        deleting.refreshDailyNote(now: yesterday)
        other.refreshDailyNote(now: yesterday)
        let trashed = try #require(deleting.selectedNote)
        #expect(deleting.trashCurrentNote())
        other.refreshDailyNote(now: yesterday)
        #expect(!FileManager.default.fileExists(atPath: trashed.url.path))

        other.refreshDailyNote(now: today)

        #expect(other.selectedNote?.url != trashed.url)
        #expect(other.saveErrorMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: trashed.url.path))
    }
}

@MainActor
private final class WindowShortcutFixture {
    private let domain = "live.lukesmith.ObsidianSideNote"
    private let savedDefaults: [String: Any]?
    private let savedConfigURL: URL?
    private let vaultURL: URL

    init() throws {
        savedDefaults = UserDefaults.standard.persistentDomain(forName: domain)
        savedConfigURL = AppConfigStore.configURLOverride
        vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        AppConfigStore.configURLOverride = vaultURL.appendingPathComponent("config.json")
        VaultStore.saveVaultURL(vaultURL)
    }

    func restore() {
        AppConfigStore.configURLOverride = savedConfigURL
        if let savedDefaults { UserDefaults.standard.setPersistentDomain(savedDefaults, forName: domain) }
        else { UserDefaults.standard.removePersistentDomain(forName: domain) }
        try? FileManager.default.removeItem(at: vaultURL)
    }
}
