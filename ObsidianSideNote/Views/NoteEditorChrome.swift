import SwiftUI
import AppKit

struct NoteEditorHeader: View {
    let mode: NoteMode
    let closeWindow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            DraggableWindowTitle(title: mode.title)
                .frame(minWidth: 1, idealWidth: 180, maxWidth: 220, minHeight: 16, alignment: .leading)

            WindowDragHandle()
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)

            WindowCloseButton(action: closeWindow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(WindowDragHandle())
    }
}

struct WindowCloseButton: NSViewRepresentable {
    let action: () -> Void
    static let hitTargetSize = NSSize(width: 32, height: 32)

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Close"
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.hitTargetSize.width),
            button.heightAnchor.constraint(equalToConstant: Self.hitTargetSize.height)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func close() {
            action()
        }
    }
}

struct VaultSearchPanel: View {
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding
    let vaultName: String
    let filePath: String
    let openInObsidian: () -> Void

    var body: some View {
        searchField
            .anchorPreference(key: VaultSearchFieldBoundsPreferenceKey.self, value: .bounds) { $0 }
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
}

struct VaultSearchSuggestionsPopup: View {
    let results: VaultSearchResults
    let isSearching: Bool
    let highlightedIndex: Int
    let selectFolder: (VaultNote) -> Void
    let selectNote: (VaultNote) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if results.rows.isEmpty {
                Text(isSearching ? "Searching…" : "No matching files or folders")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.rows.enumerated()), id: \.element.id) { index, row in
                                if let sectionIndex = results.sectionStarts.firstIndex(of: index) {
                                    if sectionIndex > 0 { Divider().padding(.vertical, 4) }
                                    sectionLabel(results.sections[sectionIndex])
                                }
                                suggestionButton(row, at: index)
                                    .id(row.id)
                            }
                        }
                        .disabled(isSearching)
                    }
                    .frame(maxHeight: 220)
                    .onAppear { scrollToSelection(proxy) }
                    .onChange(of: highlightedIndex) { _, _ in scrollToSelection(proxy) }
                    .onChange(of: results.rows.map(\.id)) { _, _ in scrollToSelection(proxy) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("vault-search-results")
        .accessibilityValue(isSearching ? "Searching" : "Ready")
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard results.rows.indices.contains(highlightedIndex) else { return }
        proxy.scrollTo(results.rows[highlightedIndex].id)
    }

    private func sectionLabel(_ section: VaultSearchSection) -> some View {
        HStack {
            Text(section.kind.rawValue)
            Spacer()
            Text(section.notes.count.formatted())
        }
        .font(.system(size: 10))
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func suggestionButton(_ row: VaultSearchResults.Row, at index: Int) -> some View {
        Button {
            if row.isFolder { selectFolder(row.note) } else { selectNote(row.note) }
        } label: {
            HStack(spacing: 6) {
                if row.isFolder { Image(systemName: "folder") }
                Text(row.note.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(index == highlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityLabel(row.isFolder ? "Folder, \(row.note.title)" : row.note.title)
        .accessibilityValue(index == highlightedIndex ? "Selected" : "")
        .accessibilityIdentifier("vault-search-row-\(row.id)")
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

struct VaultSearchFieldBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
