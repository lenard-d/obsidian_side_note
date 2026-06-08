import SwiftUI
import AppKit

struct NoteEditorHeader: View {
    let mode: NoteMode
    let closeWindow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(mode.title)
                .font(.system(size: 13, weight: .semibold))

            WindowDragHandle()
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)

            Button(action: closeWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

struct VaultSearchPanel: View {
    @Binding var query: String
    @Binding var selectedNote: VaultNote?
    @Binding var highlightedIndex: Int
    var isSearchFocused: FocusState<Bool>.Binding
    let vaultName: String
    let filePath: String
    let results: [VaultNote]
    let showsSuggestions: Bool
    let openInObsidian: () -> Void
    let selectNote: (VaultNote) -> Void

    private var visibleResults: ArraySlice<VaultNote> {
        results.prefix(8)
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField
            suggestions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("Search by title or path", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused(isSearchFocused)

            Button(action: openInObsidian) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .disabled(vaultName.isEmpty || filePath.isEmpty)
            .help("Open file in Obsidian")
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if showsSuggestions {
            VStack(spacing: 0) {
                if results.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(visibleResults.enumerated()), id: \.element.id) { index, note in
                        suggestionButton(for: note, at: index)
                        if index < visibleResults.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var emptyState: some View {
        Text("No matching notes")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private func suggestionButton(for note: VaultNote, at index: Int) -> some View {
        Button {
            selectNote(note)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(note.relativePath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(index == highlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
    }

}

struct MissingVaultPrompt: View {
    var body: some View {
        Text("Choose your vault folder in Settings first.")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}
