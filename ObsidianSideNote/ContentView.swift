//
//  ContentView.swift
//  ObsidianSideNote
//
//  Created by Luke Smith on 11/27/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    let mode: NoteMode
    let closeWindow: () -> Void

    @State private var noteText: String = ""
    @State private var noteTitle: String = ""
    @State private var vaultSearchQuery: String = ""
    @State private var vaultName: String = VaultStore.selectedVaultName
    @State private var vaultPath: String = UserDefaults.standard.string(forKey: VaultStore.pathKey) ?? ""
    @State private var searchResults: [VaultNote] = []
    @State private var selectedNote: VaultNote?
    @State private var createdNewNote: VaultNote?
    @State private var highlightedSearchIndex: Int = 0
    @State private var searchKeyMonitor: Any?
    @State private var isLoadingNote: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var saveErrorMessage: String?
    @FocusState private var isTextEditorFocused: Bool
    @FocusState private var isVaultSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if mode == .settings {
                SettingsView(vaultName: $vaultName, vaultPath: $vaultPath, closeWindow: closeWindow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    header
                    MarkdownEditorView(
                        text: $noteText,
                        isFocused: $isTextEditorFocused,
                        insertMedia: insertMediaLink
                    )

                    if mode == .appendDaily {
                        SaveActionBar(
                            mode: mode,
                            isSaveDisabled: isSaveDisabled,
                            showSaveSuccess: showSaveSuccess,
                            saveErrorMessage: saveErrorMessage,
                            save: saveNote
                        )
                    }
                }
            }
        }
        .frame(minWidth: 350, minHeight: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if mode != .settings {
                loadDraft()
                refreshSearchResults()
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    isTextEditorFocused = true
                }
                installSearchKeyMonitor()
            }
        }
        .onDisappear {
            removeSearchKeyMonitor()
        }
        .onExitCommand {
            closeWindow()
        }
        .onChange(of: noteText) { oldValue, newValue in
            saveDraft()
            saveErrorMessage = nil
            autosaveSelectedNote()
            autosaveNewNote()
        }
        .onChange(of: noteTitle) { oldValue, newValue in
            saveDraft()
        }
        .onChange(of: vaultSearchQuery) { oldValue, newValue in
            if mode == .editVaultFile {
                UserDefaults.standard.set(newValue, forKey: "draft.editVaultFile.search")
                refreshSearchResults()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            NoteEditorHeader(mode: mode, closeWindow: closeWindow)

            if mode == .newNote {
                TextField("Title", text: $noteTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if mode == .editVaultFile {
                VaultSearchPanel(
                    query: $vaultSearchQuery,
                    selectedNote: $selectedNote,
                    highlightedIndex: $highlightedSearchIndex,
                    isSearchFocused: $isVaultSearchFocused,
                    vaultName: vaultName,
                    filePath: noteTitle,
                    results: searchResults,
                    showsSuggestions: shouldShowSearchSuggestions,
                    openInObsidian: openVaultFile,
                    selectNote: selectNote
                )
            }

            if shouldShowMissingVaultPrompt {
                MissingVaultPrompt()
            }

            Divider()
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var isSaveDisabled: Bool {
        switch mode {
        case .appendDaily:
            return vaultName.isEmpty || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .newNote, .editVaultFile, .settings:
            return true
        }
    }

    private var shouldShowSearchSuggestions: Bool {
        mode == .editVaultFile
            && isVaultSearchFocused
            && !vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedNote?.relativePath != vaultSearchQuery
    }

    private var shouldShowMissingVaultPrompt: Bool {
        switch mode {
        case .appendDaily:
            return vaultName.isEmpty
        case .newNote, .editVaultFile:
            return vaultPath.isEmpty
        case .settings:
            return false
        }
    }

    private func saveNote() {
        guard !vaultName.isEmpty else { return }
        saveErrorMessage = nil

        switch mode {
        case .appendDaily:
            appendToDailyNote()
        case .newNote, .editVaultFile, .settings:
            break
        }
    }

    private func appendToDailyNote() {
        let textToAppend = noteText

        if let createURL = ObsidianURIBuilder.ensureDaily(vaultName: vaultName) {
            NSWorkspace.shared.open(createURL)
        }

        // Let Obsidian's Daily Notes plugin create the file and apply its template before appending.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let appendURL = ObsidianURIBuilder.appendDaily(vaultName: vaultName, text: textToAppend) {
                NSWorkspace.shared.open(appendURL)
            }

            withAnimation(.spring(response: 0.3)) {
                showSaveSuccess = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                noteText = ""
                noteTitle = ""
                showSaveSuccess = false
                clearDraft()
                closeWindow()
            }
        }
    }

    private func openVaultFile() {
        let filePath = selectedNote?.relativePath ?? noteTitle
        guard !vaultName.isEmpty, !filePath.isEmpty else { return }
        if let url = ObsidianURIBuilder.openFile(vaultName: vaultName, filePath: filePath) {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadDraft() {
        noteText = UserDefaults.standard.string(forKey: mode.draftTextKey) ?? ""
        noteTitle = UserDefaults.standard.string(forKey: mode.draftTitleKey) ?? ""
        vaultSearchQuery = UserDefaults.standard.string(forKey: "draft.editVaultFile.search") ?? ""
        vaultName = VaultStore.selectedVaultName
        vaultPath = UserDefaults.standard.string(forKey: VaultStore.pathKey) ?? ""

        if mode == .newNote,
           let relativePath = UserDefaults.standard.string(forKey: NewNotePreferences.draftFilePathKey) {
            createdNewNote = VaultStore.note(relativePath: relativePath)
        }
    }

    private func saveDraft() {
        guard mode != .settings else { return }
        UserDefaults.standard.set(noteText, forKey: mode.draftTextKey)
        if !mode.draftTitleKey.isEmpty {
            UserDefaults.standard.set(noteTitle, forKey: mode.draftTitleKey)
        }
    }

    private func refreshSearchResults() {
        guard mode == .editVaultFile else { return }
        searchResults = VaultStore.markdownNotes(matching: vaultSearchQuery)
        highlightedSearchIndex = min(highlightedSearchIndex, max(searchResults.prefix(8).count - 1, 0))
        if let selectedNote, !searchResults.contains(selectedNote) {
            self.selectedNote = nil
        }
    }

    private func selectNote(_ note: VaultNote) {
        isLoadingNote = true
        selectedNote = note
        noteTitle = note.relativePath
        noteText = VaultStore.read(note)
        vaultSearchQuery = note.relativePath
        isVaultSearchFocused = false
        isLoadingNote = false
    }

    private func selectHighlightedSearchResult() {
        let visibleResults = Array(searchResults.prefix(8))
        guard !visibleResults.isEmpty else { return }
        let index = min(max(highlightedSearchIndex, 0), visibleResults.count - 1)
        selectNote(visibleResults[index])
    }

    private func installSearchKeyMonitor() {
        guard mode == .editVaultFile, searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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

    private func removeSearchKeyMonitor() {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
            self.searchKeyMonitor = nil
        }
    }

    private func autosaveSelectedNote() {
        guard mode == .editVaultFile, !isLoadingNote, let selectedNote else { return }
        VaultStore.write(noteText, to: selectedNote)
    }

    private func autosaveNewNote() {
        guard mode == .newNote else { return }
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            if let createdNewNote {
                VaultStore.write(noteText, to: createdNewNote)
            } else {
                UserDefaults.standard.removeObject(forKey: NewNotePreferences.draftFilePathKey)
            }
            return
        }

        if let createdNewNote {
            VaultStore.write(noteText, to: createdNewNote)
            return
        }

        guard let note = VaultStore.createOrUpdateNote(title: noteTitle, text: noteText, fallbackDate: dateString()) else {
            saveErrorMessage = "Could not create note in selected vault."
            return
        }

        createdNewNote = note
        UserDefaults.standard.set(note.relativePath, forKey: NewNotePreferences.draftFilePathKey)
    }

    private func insertMediaLink(_ relativePath: String) {
        let escapedPath = relativePath.replacingOccurrences(of: ")", with: "%29")
        let insertion = "![\(URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent)](\(escapedPath))"
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += insertion
        } else {
            noteText += "\n\(insertion)"
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: mode.draftTextKey)
        if !mode.draftTitleKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: mode.draftTitleKey)
        }
        if mode == .newNote {
            UserDefaults.standard.removeObject(forKey: NewNotePreferences.draftFilePathKey)
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: Date())
    }
}

#Preview {
    ContentView(mode: .newNote, closeWindow: {})
}
