import AppKit
import Combine
import SwiftUI

final class ContentViewModel: ObservableObject {
    let mode: NoteMode

    @Published var noteText: String = ""
    @Published var noteTitle: String = ""
    @Published var vaultSearchQuery: String = ""
    @Published var vaultName: String = VaultStore.selectedVaultName
    @Published var vaultPath: String = UserDefaults.standard.string(forKey: VaultStore.pathKey) ?? ""
    @Published var searchResults: [VaultNote] = []
    @Published var selectedNote: VaultNote?
    @Published var createdNewNote: VaultNote?
    @Published var highlightedSearchIndex: Int = 0
    @Published var isLoadingNote: Bool = false
    @Published var saveErrorMessage: String?
    @Published var cursorEndRequestID: Int = 0

    private var searchKeyMonitor: Any?
    private var openNoteKeyMonitor: Any?
    private var pendingSelectedNoteAutosave: DispatchWorkItem?
    private var pendingNewNoteAutosave: DispatchWorkItem?
    private var clearSearchFocus: (() -> Void)?

    init(mode: NoteMode) {
        self.mode = mode
    }

    var shouldShowSearchSuggestions: Bool {
        mode == .editVaultFile
            && !vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedNote?.relativePath != vaultSearchQuery
    }

    var shouldShowMissingVaultPrompt: Bool {
        switch mode {
        case .appendDaily, .newNote, .editVaultFile:
            return vaultPath.isEmpty
        case .settings, .setup:
            return false
        }
    }

    func start(clearSearchFocus: @escaping () -> Void, focusEditor: @escaping () -> Void) {
        guard mode != .settings && mode != .setup else { return }
        self.clearSearchFocus = clearSearchFocus
        loadDraft()
        refreshSearchResults()
        loadDailyNoteIfNeeded()
        DispatchQueue.main.async(execute: focusEditor)
        installSearchKeyMonitor()
        installOpenNoteKeyMonitor()
    }

    func stop() {
        flushSelectedNoteAutosave()
        flushNewNoteAutosave()
        removeSearchKeyMonitor()
        removeOpenNoteKeyMonitor()
        clearSearchFocus = nil
    }

    func textDidChange() {
        saveDraft()
        saveErrorMessage = nil
        scheduleSelectedNoteAutosave()
        autosaveNewNote()
    }

    func titleDidChange() {
        saveDraft()
        scheduleNewNoteAutosave()
    }

    func searchQueryDidChange() {
        guard mode == .editVaultFile else { return }
        UserDefaults.standard.set(vaultSearchQuery, forKey: "draft.editVaultFile.search")
        refreshSearchResults()
    }

    func openVaultFile() {
        let filePath = selectedNote?.relativePath ?? noteTitle
        guard !vaultName.isEmpty, !filePath.isEmpty else { return }
        if let url = ObsidianURIBuilder.openFile(vaultName: vaultName, filePath: filePath) {
            NSWorkspace.shared.open(url)
        }
    }

    func selectNote(_ note: VaultNote) {
        flushSelectedNoteAutosave()
        isLoadingNote = true
        selectedNote = note
        noteTitle = note.relativePath
        noteText = VaultStore.read(note)
        vaultSearchQuery = note.relativePath
        clearSearchFocus?()
        isLoadingNote = false
    }

    func insertMediaLink(_ relativePath: String) {
        let insertion = "![[\(relativePath)]]"
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += insertion
        } else {
            noteText += "\n\(insertion)"
        }
    }

    private func openCurrentNoteInObsidian() {
        switch mode {
        case .appendDaily:
            guard !vaultName.isEmpty, let url = ObsidianURIBuilder.openDaily(vaultName: vaultName) else { return }
            NSWorkspace.shared.open(url)
        case .newNote:
            autosaveNewNote()
            guard let createdNewNote,
                  !vaultName.isEmpty,
                  let url = ObsidianURIBuilder.openFile(vaultName: vaultName, filePath: createdNewNote.relativePath) else { return }
            NSWorkspace.shared.open(url)
        case .editVaultFile:
            openVaultFile()
        case .settings, .setup:
            break
        }
    }

    private func loadDraft() {
        guard mode != .appendDaily else {
            vaultName = VaultStore.selectedVaultName
            vaultPath = UserDefaults.standard.string(forKey: VaultStore.pathKey) ?? ""
            return
        }

        noteText = UserDefaults.standard.string(forKey: mode.draftTextKey) ?? ""
        noteTitle = UserDefaults.standard.string(forKey: mode.draftTitleKey) ?? ""
        if mode == .newNote, noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteTitle = VaultStore.defaultQuickNoteTitle(fallbackDate: dateString())
        }
        vaultSearchQuery = UserDefaults.standard.string(forKey: "draft.editVaultFile.search") ?? ""
        vaultName = VaultStore.selectedVaultName
        vaultPath = UserDefaults.standard.string(forKey: VaultStore.pathKey) ?? ""

        if mode == .newNote,
           let relativePath = UserDefaults.standard.string(forKey: NewNotePreferences.draftFilePathKey) {
            createdNewNote = VaultStore.note(relativePath: relativePath)
        }
    }

    private func loadDailyNoteIfNeeded() {
        guard mode == .appendDaily else { return }

        loadDailyNoteFromVault()
    }

    private func loadDailyNoteFromVault() {
        guard mode == .appendDaily else { return }
        guard let note = VaultStore.ensureDailyNoteForToday() else {
            saveErrorMessage = "Could not open today's daily note."
            return
        }

        isLoadingNote = true
        selectedNote = note
        noteTitle = note.relativePath
        noteText = VaultStore.read(note)
        cursorEndRequestID += 1
        isLoadingNote = false
    }

    private func saveDraft() {
        guard mode != .settings && mode != .setup else { return }
        UserDefaults.standard.set(noteText, forKey: mode.draftTextKey)
        if !mode.draftTitleKey.isEmpty {
            UserDefaults.standard.set(noteTitle, forKey: mode.draftTitleKey)
        }
    }

    private func refreshSearchResults() {
        guard mode == .editVaultFile else { return }
        let trimmedQuery = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            highlightedSearchIndex = 0
            return
        }

        searchResults = VaultStore.markdownNotes(matching: vaultSearchQuery)
        highlightedSearchIndex = min(highlightedSearchIndex, max(searchResults.prefix(8).count - 1, 0))
        if let selectedNote, !searchResults.contains(selectedNote) {
            self.selectedNote = nil
        }
    }

    private func selectHighlightedSearchResult() {
        let visibleResults = Array(searchResults.prefix(8))
        guard !visibleResults.isEmpty else { return }
        let index = min(max(highlightedSearchIndex, 0), visibleResults.count - 1)
        selectNote(visibleResults[index])
    }

    private func installSearchKeyMonitor() {
        guard mode == .editVaultFile, searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard shouldShowSearchSuggestions else {
                return event
            }

            let visibleCount = searchResults.prefix(8).count
            guard visibleCount > 0 else {
                return event
            }

            switch event.keyCode {
            case 125:
                highlightedSearchIndex = min(highlightedSearchIndex + 1, visibleCount - 1)
                return nil
            case 126:
                highlightedSearchIndex = max(highlightedSearchIndex - 1, 0)
                return nil
            case 36, 48:
                selectHighlightedSearchResult()
                return nil
            default:
                return event
            }
        }
    }

    private func installOpenNoteKeyMonitor() {
        guard openNoteKeyMonitor == nil else { return }
        openNoteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  NSApp.isActive,
                  ShortcutPreference.normalized(event.charactersIgnoringModifiers ?? "") == "o",
                  ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command else {
                return event
            }

            openCurrentNoteInObsidian()
            return nil
        }
    }

    private func removeSearchKeyMonitor() {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
            self.searchKeyMonitor = nil
        }
    }

    private func removeOpenNoteKeyMonitor() {
        if let openNoteKeyMonitor {
            NSEvent.removeMonitor(openNoteKeyMonitor)
            self.openNoteKeyMonitor = nil
        }
    }

    private func scheduleSelectedNoteAutosave() {
        guard (mode == .editVaultFile || mode == .appendDaily), !isLoadingNote, let selectedNote else { return }
        pendingSelectedNoteAutosave?.cancel()
        let textSnapshot = noteText
        let noteSnapshot = selectedNote
        let workItem = DispatchWorkItem { [weak self] in
            do {
                try VaultStore.write(textSnapshot, to: noteSnapshot)
            } catch {
                DispatchQueue.main.async {
                    self?.saveErrorMessage = "Could not save note: \(error.localizedDescription)"
                }
            }
        }
        pendingSelectedNoteAutosave = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func flushSelectedNoteAutosave() {
        guard (mode == .editVaultFile || mode == .appendDaily), !isLoadingNote, let selectedNote else { return }
        pendingSelectedNoteAutosave?.cancel()
        pendingSelectedNoteAutosave = nil
        writeSelectedNote(noteText, to: selectedNote)
    }

    private func scheduleNewNoteAutosave() {
        guard mode == .newNote else { return }
        pendingNewNoteAutosave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.autosaveNewNote()
        }
        pendingNewNoteAutosave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func flushNewNoteAutosave() {
        guard mode == .newNote else { return }
        pendingNewNoteAutosave?.cancel()
        pendingNewNoteAutosave = nil
        autosaveNewNote()
    }

    private func autosaveNewNote() {
        guard mode == .newNote else { return }
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            if let createdNewNote {
                writeSelectedNote(noteText, to: createdNewNote)
            } else {
                UserDefaults.standard.removeObject(forKey: NewNotePreferences.draftFilePathKey)
            }
            return
        }

        if let createdNewNote {
            if noteTitle.trimmingCharacters(in: .whitespacesAndNewlines) != createdNewNote.title,
               let renamedNote = VaultStore.rename(createdNewNote, toTitle: noteTitle) {
                self.createdNewNote = renamedNote
                UserDefaults.standard.set(renamedNote.relativePath, forKey: NewNotePreferences.draftFilePathKey)
                writeSelectedNote(noteText, to: renamedNote)
                return
            }
            writeSelectedNote(noteText, to: createdNewNote)
            return
        }

        guard let note = VaultStore.createOrUpdateNote(title: noteTitle, text: noteText, fallbackDate: dateString()) else {
            saveErrorMessage = "Could not create note in selected vault."
            return
        }

        createdNewNote = note
        UserDefaults.standard.set(note.relativePath, forKey: NewNotePreferences.draftFilePathKey)
    }

    private func writeSelectedNote(_ text: String, to note: VaultNote) {
        do {
            try VaultStore.write(text, to: note)
        } catch {
            saveErrorMessage = "Could not save note: \(error.localizedDescription)"
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: Date())
    }
}
