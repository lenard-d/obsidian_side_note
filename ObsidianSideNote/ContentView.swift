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

    @StateObject private var viewModel: ContentViewModel
    @State private var titleFocusRequestID = 0
    @State private var editorFocusRequestID = 0
    @FocusState private var isTextEditorFocused: Bool
    @FocusState private var isVaultSearchFocused: Bool

    init(mode: NoteMode, closeWindow: @escaping () -> Void) {
        self.mode = mode
        self.closeWindow = closeWindow
        _viewModel = StateObject(wrappedValue: ContentViewModel(mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .settings {
                SettingsView(vaultName: $viewModel.vaultName, vaultPath: $viewModel.vaultPath, closeWindow: closeWindow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .setup {
                SetupView(vaultName: $viewModel.vaultName, vaultPath: $viewModel.vaultPath, closeWindow: closeWindow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        header
                            .zIndex(1)
                        MarkdownEditorView(
                            text: $viewModel.noteText,
                            isFocused: $isTextEditorFocused,
                            focusRequestID: $editorFocusRequestID,
                            cursorEndRequestID: $viewModel.cursorEndRequestID,
                            insertMedia: viewModel.insertMediaLink
                        )
                        .zIndex(0)
                    }
                }
                .overlayPreferenceValue(VaultSearchFieldBoundsPreferenceKey.self) { anchor in
                    searchSuggestionsOverlay(anchor: anchor)
                }
            }
        }
        .frame(minWidth: 175, minHeight: 263)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if mode != .settings && mode != .setup {
                viewModel.start(clearSearchFocus: {
                    isVaultSearchFocused = false
                }, focusEditor: {
                    focusInitialInput()
                })
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .onExitCommand {
            closeWindow()
        }
        .onChange(of: viewModel.noteText) { oldValue, newValue in
            viewModel.textDidChange()
        }
        .onChange(of: viewModel.noteTitle) { oldValue, newValue in
            viewModel.titleDidChange()
        }
        .onChange(of: viewModel.vaultSearchQuery) { oldValue, newValue in
            viewModel.searchQueryDidChange()
        }
    }

    @ViewBuilder
    private func searchSuggestionsOverlay(anchor: Anchor<CGRect>?) -> some View {
        if mode == .editVaultFile,
           viewModel.shouldShowSearchSuggestions,
           isVaultSearchFocused,
           let anchor {
            GeometryReader { proxy in
                let fieldBounds = proxy[anchor]
                VaultSearchSuggestionsPopup(
                    results: viewModel.searchResults,
                    highlightedIndex: viewModel.highlightedSearchIndex,
                    selectNote: viewModel.selectNote
                )
                .frame(width: fieldBounds.width)
                .offset(x: fieldBounds.minX, y: fieldBounds.maxY + 4)
                .zIndex(20)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            NoteEditorHeader(mode: mode, closeWindow: closeWindow)

            if mode == .newNote {
                SelectAllOnFocusTextField(
                    placeholder: "Title",
                    text: $viewModel.noteTitle,
                    focusRequestID: titleFocusRequestID,
                    onCommit: focusEditor
                )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if mode == .editVaultFile {
                VaultSearchPanel(
                    query: $viewModel.vaultSearchQuery,
                    isSearchFocused: $isVaultSearchFocused,
                    vaultName: viewModel.vaultName,
                    filePath: viewModel.noteTitle,
                    openInObsidian: viewModel.openVaultFile
                )
            }

            if viewModel.shouldShowMissingVaultPrompt {
                MissingVaultPrompt()
            }

            if let saveErrorMessage = viewModel.saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func focusInitialInput() {
        if mode.startsWithTitleFocus {
            titleFocusRequestID += 1
        } else if mode.startsWithEditorFocus {
            focusEditor()
        }
    }

    private func focusEditor(in window: NSWindow? = nil) {
        isTextEditorFocused = true
        editorFocusRequestID += 1
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .editorShouldFocus, object: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            NotificationCenter.default.post(name: .editorShouldFocus, object: window)
        }
    }
}

#Preview {
    ContentView(mode: .newNote, closeWindow: {})
}
