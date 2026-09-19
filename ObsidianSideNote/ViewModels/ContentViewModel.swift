import AppKit
import Combine
import OSLog
import SwiftUI

final class ContentViewModel: ObservableObject {
    let mode: NoteMode

    @Published var noteText: String = ""
    @Published var noteTitle: String = ""
    @Published var vaultSearchQuery: String = ""
    @Published var vaultName: String = VaultStore.selectedVaultName
    @Published var vaultPath: String = VaultStore.selectedVaultPath
    @Published var searchSuggestions: VaultSearchResults = .empty
    var searchResults: [VaultNote] { searchSuggestions.rows.filter { !$0.isFolder }.map(\.note) }
    var folderResults: [VaultNote] { searchSuggestions.rows.filter(\.isFolder).map(\.note) }
    var searchResultCount: Int { searchSuggestions.rows.count }
    var isSearchFocused = false
    @Published private(set) var isSearching = false
    private(set) var searchTask: Task<Void, Never>?
    private var searchWork: Task<VaultSearchResults, Never>?
    private var activateWhenSearchCompletes = false
    @Published private var searchSuggestionsDismissed = false
    @Published var selectedNote: VaultNote?
    @Published var createdNewNote: VaultNote?
    @Published var highlightedSearchIndex: Int = 0
    @Published var isLoadingNote: Bool = false
    @Published var saveErrorMessage: String?
    @Published var cursorEndRequestID: Int = 0

    private var searchKeyMonitor: Any?
    private var openNoteKeyMonitor: Any?
    private var pendingSelectedNoteAutosave: DispatchWorkItem?
    private var selectedNoteAutosaveToken: AutosaveCancellationToken?
    private var pendingNewNoteAutosave: DispatchWorkItem?
    private let notePersistenceQueue = DispatchQueue(label: "live.lukesmith.ObsidianSideNote.note-persistence", qos: .utility)
    private var clearSearchFocus: (() -> Void)?
    private var focusEditor: (() -> Void)?
    private let activeNoteFileMonitor = VaultNoteFileMonitor()
    private var lastSyncedActiveNoteText: String?
    private var latestQueuedNoteWrite: QueuedNoteWrite?
    private var textAutosaveSuppressionValue: String?
    private var eventWindowNumber: Int?

    init(mode: NoteMode) {
        self.mode = mode
    }

    var shouldShowSearchSuggestions: Bool {
        mode == .editVaultFile
            && !searchSuggestionsDismissed
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
        self.focusEditor = focusEditor
        loadDraft()
        refreshSearchResults()
        loadDailyNoteIfNeeded()
        startActiveNoteFileMonitorIfNeeded()
        DispatchQueue.main.async(execute: focusEditor)
        installSearchKeyMonitor()
        installOpenNoteKeyMonitor()
    }

    func setEventWindowNumber(_ windowNumber: Int) {
        eventWindowNumber = windowNumber
    }

    func stop() {
        searchTask?.cancel()
        searchWork?.cancel()
        flushSelectedNoteAutosave()
        flushNewNoteAutosave()
        if mode == .newNote {
            NewNotePreferences.touchSession()
        }
        activeNoteFileMonitor.stop()
        removeSearchKeyMonitor()
        removeOpenNoteKeyMonitor()
        clearSearchFocus = nil
        focusEditor = nil
    }

    func textDidChange() {
        saveDraft()
        saveErrorMessage = nil
        if let suppressedText = textAutosaveSuppressionValue {
            textAutosaveSuppressionValue = nil
            if suppressedText == noteText {
                return
            }
        }
        scheduleSelectedNoteAutosave()
        autosaveNewNote()
    }

    func titleDidChange() {
        saveDraft()
        scheduleNewNoteAutosave()
    }

    func searchQueryDidChange() {
        guard mode == .editVaultFile else { return }
        searchSuggestionsDismissed = false
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
        activeNoteFileMonitor.stop()
        isLoadingNote = true
        selectedNote = note
        noteTitle = note.relativePath
        loadText(from: note)
        vaultSearchQuery = note.relativePath
        clearSearchFocus?()
        isLoadingNote = false
        startActiveNoteFileMonitorIfNeeded()
    }

    @discardableResult
    func selectWikiLink(_ link: String) -> Bool {
        guard mode == .editVaultFile,
              let note = VaultStore.note(forWikiLink: link) else {
            return false
        }
        selectNote(note)
        return true
    }

    @discardableResult
    func selectMarkdownLink(_ link: String) -> Bool {
        guard mode == .editVaultFile,
              let note = VaultStore.note(forMarkdownLink: link) else {
            return false
        }
        selectNote(note)
        return true
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
            vaultPath = VaultStore.selectedVaultPath
            return
        }

        noteText = UserDefaults.standard.string(forKey: mode.draftTextKey) ?? ""
        noteTitle = UserDefaults.standard.string(forKey: mode.draftTitleKey) ?? ""
        if mode == .newNote, noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteTitle = VaultStore.defaultQuickNoteTitle(fallbackDate: dateString())
        }
        vaultSearchQuery = UserDefaults.standard.string(forKey: "draft.editVaultFile.search") ?? ""
        vaultName = VaultStore.selectedVaultName
        vaultPath = VaultStore.selectedVaultPath
        restoreSelectedVaultFileDraftIfNeeded()

        if mode == .newNote,
           let relativePath = UserDefaults.standard.string(forKey: NewNotePreferences.draftFilePathKey) {
            createdNewNote = VaultStore.note(relativePath: relativePath)
            if let createdNewNote {
                loadText(from: createdNewNote)
            }
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
        loadText(from: note)
        cursorEndRequestID += 1
        isLoadingNote = false
        startActiveNoteFileMonitorIfNeeded()
    }

    private func restoreSelectedVaultFileDraftIfNeeded() {
        guard mode == .editVaultFile else { return }

        let storedPath = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPath = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = !storedPath.isEmpty ? storedPath : queryPath
        guard let note = VaultStore.note(relativePath: relativePath) else { return }

        selectedNote = note
        noteTitle = note.relativePath
        vaultSearchQuery = note.relativePath
        UserDefaults.standard.set(note.relativePath, forKey: mode.draftTitleKey)
        UserDefaults.standard.set(note.relativePath, forKey: "draft.editVaultFile.search")
        loadText(from: note)
    }

    private func loadText(from note: VaultNote) {
        do {
            let loadedText = try VaultStore.readNote(note)
            noteText = loadedText
            lastSyncedActiveNoteText = loadedText
            saveErrorMessage = nil
        } catch {
            noteText = ""
            lastSyncedActiveNoteText = nil
            saveErrorMessage = "Could not load note: \(error.localizedDescription)"
            AppLogger.vault.error("Could not read note: \(AppLogger.errorSummary(error))")
        }
    }

    private func saveDraft() {
        guard mode != .settings && mode != .setup else { return }
        UserDefaults.standard.set(noteText, forKey: mode.draftTextKey)
        if !mode.draftTitleKey.isEmpty {
            UserDefaults.standard.set(noteTitle, forKey: mode.draftTitleKey)
        }
        if mode == .newNote {
            NewNotePreferences.touchSession()
        }
    }

    func searchFocusDidChange(_ focused: Bool) {
        isSearchFocused = focused
        guard focused else { return }
        VaultSearchIndexStore.invalidate()
        searchSuggestionsDismissed = false
        refreshSearchResults()
    }

    private func refreshSearchResults() {
        guard mode == .editVaultFile else { return }
        searchTask?.cancel()
        searchWork?.cancel()
        let query = vaultSearchQuery
        activateWhenSearchCompletes = false
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let vaultURL = VaultStore.selectedVaultURL else {
            searchSuggestions = .empty
            highlightedSearchIndex = 0
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            let work = Task.detached(priority: .userInitiated) {
                let index = VaultSearchIndexStore.index(in: vaultURL)
                guard !Task.isCancelled else { return VaultSearchResults.empty }
                return index.search.suggestions(matching: query)
            }
            self?.searchWork = work
            let results = await work.value
            guard !Task.isCancelled, let self, vaultSearchQuery == query,
                  VaultStore.selectedVaultURL == vaultURL else { return }
            searchSuggestions = results
            highlightedSearchIndex = results.preferredIndex
            isSearching = false
            if activateWhenSearchCompletes {
                activateWhenSearchCompletes = false
                if isSearchFocused && shouldShowSearchSuggestions { selectHighlightedSearchResult() }
            }
        }
    }

    func selectFolder(_ folder: VaultNote) {
        vaultSearchQuery = folder.relativePath + "/"
        searchQueryDidChange()
    }

    func selectHighlightedSearchResult() {
        guard !isSearching, searchSuggestions.rows.indices.contains(highlightedSearchIndex) else { return }
        let row = searchSuggestions.rows[highlightedSearchIndex]
        if row.isFolder {
            selectFolder(row.note)
        } else {
            selectNote(row.note)
            focusEditor?()
        }
    }

    func moveSearchSelectionDown(toNextSection: Bool) {
        if toNextSection {
            highlightedSearchIndex = searchSuggestions.nextSection(after: highlightedSearchIndex)
        } else {
            highlightedSearchIndex = min(highlightedSearchIndex + 1, max(searchResultCount - 1, 0))
        }
    }

    func handleSearchKey(_ event: NSEvent) -> Bool {
        guard isSearchFocused, shouldShowSearchSuggestions, eventBelongsToWindow(event) else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty || modifiers == .command else { return false }
        switch event.keyCode {
        case 53 where modifiers.isEmpty:
            searchSuggestionsDismissed = true
            activateWhenSearchCompletes = false
        case 125:
            moveSearchSelectionDown(toNextSection: modifiers == .command)
        case 126:
            highlightedSearchIndex = modifiers == .command
                ? searchSuggestions.previousSection(before: highlightedSearchIndex)
                : max(highlightedSearchIndex - 1, 0)
        case 36, 76, 48:
            guard modifiers.isEmpty else { return false }
            if isSearching {
                activateWhenSearchCompletes = true
                return true
            }
            guard searchResultCount > 0 else { return false }
            selectHighlightedSearchResult()
        default:
            return false
        }
        return true
    }

    private func installSearchKeyMonitor() {
        guard mode == .editVaultFile, searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleSearchKey(event) == true ? nil : event
        }
    }

    private func installOpenNoteKeyMonitor() {
        guard openNoteKeyMonitor == nil else { return }
        openNoteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  NSApp.isActive,
                  eventBelongsToWindow(event),
                  ShortcutPreference.normalized(event.charactersIgnoringModifiers ?? "") == "o",
                  ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command else {
                return event
            }

            openCurrentNoteInObsidian()
            return nil
        }
    }

    func eventBelongsToWindow(_ event: NSEvent) -> Bool {
        guard let eventWindowNumber else { return false }
        if event.windowNumber != 0 {
            return event.windowNumber == eventWindowNumber
        }
        return NSApp.keyWindow?.windowNumber == eventWindowNumber
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

    private var activeAutosavedNote: VaultNote? {
        switch mode {
        case .appendDaily, .editVaultFile:
            return selectedNote
        case .newNote:
            return createdNewNote
        case .settings, .setup:
            return nil
        }
    }

    private func startActiveNoteFileMonitorIfNeeded() {
        guard let activeAutosavedNote else {
            activeNoteFileMonitor.stop()
            return
        }

        activeNoteFileMonitor.start(url: activeAutosavedNote.url) { [weak self] in
            self?.syncActiveNoteFromDiskIfNeeded()
        }
    }

    func syncActiveNoteFromDiskIfNeeded() {
        guard let activeAutosavedNote else { return }

        do {
            // Serialize reads with background autosaves so an external change can
            // never be followed by an already-running stale write.
            let diskSnapshot = try notePersistenceQueue.sync {
                let text = try VaultStore.readNote(activeAutosavedNote)
                let notePath = activeAutosavedNote.url.standardizedFileURL.path
                let matchesLocalWrite = latestQueuedNoteWrite == QueuedNoteWrite(notePath: notePath, text: text)
                if latestQueuedNoteWrite?.notePath == notePath {
                    latestQueuedNoteWrite = nil
                }
                return (text: text, matchesLocalWrite: matchesLocalWrite)
            }
            let diskText = diskSnapshot.text
            if diskSnapshot.matchesLocalWrite {
                lastSyncedActiveNoteText = diskText
                saveErrorMessage = nil
                return
            }
            guard diskText != lastSyncedActiveNoteText else {
                saveErrorMessage = nil
                return
            }

            pendingSelectedNoteAutosave?.cancel()
            pendingSelectedNoteAutosave = nil
            selectedNoteAutosaveToken?.cancel()
            selectedNoteAutosaveToken = nil
            pendingNewNoteAutosave?.cancel()
            pendingNewNoteAutosave = nil
            lastSyncedActiveNoteText = diskText
            saveErrorMessage = nil

            guard diskText != noteText else { return }
            textAutosaveSuppressionValue = diskText
            noteText = diskText
            saveDraft()
        } catch {
            saveErrorMessage = "Could not reload note: \(error.localizedDescription)"
            AppLogger.vault.error("Could not reload note: \(AppLogger.errorSummary(error))")
        }
    }

    private func scheduleSelectedNoteAutosave() {
        guard (mode == .editVaultFile || mode == .appendDaily), !isLoadingNote, let selectedNote else { return }
        pendingSelectedNoteAutosave?.cancel()
        selectedNoteAutosaveToken?.cancel()
        let textSnapshot = noteText
        let noteSnapshot = selectedNote
        let cancellationToken = AutosaveCancellationToken()
        let workItem = DispatchWorkItem { [weak self] in
            guard !cancellationToken.isCancelled, let self else { return }
            do {
                try VaultStore.write(textSnapshot, to: noteSnapshot)
                self.latestQueuedNoteWrite = QueuedNoteWrite(
                    notePath: noteSnapshot.url.standardizedFileURL.path,
                    text: textSnapshot
                )
                DispatchQueue.main.async {
                    guard !cancellationToken.isCancelled else { return }
                    self.markActiveNotePersisted(textSnapshot, to: noteSnapshot)
                }
            } catch {
                DispatchQueue.main.async {
                    self.saveErrorMessage = "Could not save note: \(error.localizedDescription)"
                }
                AppLogger.vault.error("Could not autosave note: \(AppLogger.errorSummary(error))")
            }
        }
        pendingSelectedNoteAutosave = workItem
        selectedNoteAutosaveToken = cancellationToken
        notePersistenceQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func flushSelectedNoteAutosave() {
        guard (mode == .editVaultFile || mode == .appendDaily), !isLoadingNote, let selectedNote else { return }
        pendingSelectedNoteAutosave?.cancel()
        pendingSelectedNoteAutosave = nil
        selectedNoteAutosaveToken?.cancel()
        selectedNoteAutosaveToken = nil
        let textSnapshot = noteText
        do {
            try notePersistenceQueue.sync {
                try VaultStore.write(textSnapshot, to: selectedNote)
                latestQueuedNoteWrite = QueuedNoteWrite(
                    notePath: selectedNote.url.standardizedFileURL.path,
                    text: textSnapshot
                )
            }
            markActiveNotePersisted(textSnapshot, to: selectedNote)
        } catch {
            saveErrorMessage = "Could not save note: \(error.localizedDescription)"
            AppLogger.vault.error("Could not flush note: \(AppLogger.errorSummary(error))")
        }
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
                writeActiveNote(noteText, to: createdNewNote)
            } else {
                UserDefaults.standard.removeObject(forKey: NewNotePreferences.draftFilePathKey)
            }
            return
        }

        if let createdNewNote {
            UserDefaults.standard.set(createdNewNote.relativePath, forKey: NewNotePreferences.draftFilePathKey)
            if noteTitle.trimmingCharacters(in: .whitespacesAndNewlines) != createdNewNote.title,
               let renamedNote = VaultStore.rename(createdNewNote, toTitle: noteTitle) {
                self.createdNewNote = renamedNote
                UserDefaults.standard.set(renamedNote.relativePath, forKey: NewNotePreferences.draftFilePathKey)
                writeActiveNote(noteText, to: renamedNote)
                startActiveNoteFileMonitorIfNeeded()
                return
            }
            writeActiveNote(noteText, to: createdNewNote)
            return
        }

        guard let note = VaultStore.createOrUpdateNote(title: noteTitle, text: noteText, fallbackDate: dateString()) else {
            saveErrorMessage = "Could not create note in selected vault."
            return
        }

        createdNewNote = note
        UserDefaults.standard.set(note.relativePath, forKey: NewNotePreferences.draftFilePathKey)
        markActiveNotePersisted(noteText, to: note)
        startActiveNoteFileMonitorIfNeeded()
    }

    private func writeActiveNote(_ text: String, to note: VaultNote) {
        do {
            try VaultStore.write(text, to: note)
            markActiveNotePersisted(text, to: note)
        } catch {
            saveErrorMessage = "Could not save note: \(error.localizedDescription)"
            AppLogger.vault.error("Could not save note: \(AppLogger.errorSummary(error))")
        }
    }

    private func markActiveNotePersisted(_ text: String, to note: VaultNote) {
        guard activeAutosavedNote?.url.standardizedFileURL.path == note.url.standardizedFileURL.path else { return }
        lastSyncedActiveNoteText = text
        saveErrorMessage = nil
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: Date())
    }
}

private struct QueuedNoteWrite: Equatable {
    let notePath: String
    let text: String
}

private final class AutosaveCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}
