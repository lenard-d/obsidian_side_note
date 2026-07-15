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
    let results: [VaultNote]
    let highlightedIndex: Int
    let selectNote: (VaultNote) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                                suggestionButton(for: note, at: index)
                                    .id(note.id)
                                if index < results.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: highlightedIndex) { _, newIndex in
                        guard results.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(results[newIndex].id, anchor: .center)
                        }
                    }
                    .onChange(of: results.map(\.id)) { _, _ in
                        guard results.indices.contains(highlightedIndex) else { return }
                        proxy.scrollTo(results[highlightedIndex].id, anchor: .center)
                    }
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

struct VaultSearchFieldBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
