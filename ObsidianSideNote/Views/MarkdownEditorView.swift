import SwiftUI
import AppKit

struct MarkdownEditorView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let insertMedia: (String) -> Void
    @State private var showPreview = false
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if showPreview {
                preview
            } else {
                editor
            }
        }
        .onAppear {
            installPasteMonitor()
        }
        .onDisappear {
            removePasteMonitor()
        }
        .onDrop(
            of: MediaAttachmentImporter.supportedDropTypes,
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MarkdownButton(symbol: "bold", action: { wrapSelection("**") }, tooltip: "Bold")
                    MarkdownButton(symbol: "italic", action: { wrapSelection("*") }, tooltip: "Italic")
                    MarkdownButton(symbol: "strikethrough", action: { wrapSelection("~~") }, tooltip: "Strikethrough")

                    Divider()
                        .frame(height: 16)

                    MarkdownButton(symbol: "link", action: insertLink, tooltip: "Link")
                    MarkdownButton(symbol: "list.bullet", action: { insertPrefix("- ") }, tooltip: "Bullet List")
                    MarkdownButton(symbol: "list.number", action: { insertPrefix("1. ") }, tooltip: "Numbered List")
                    MarkdownButton(symbol: "checkmark.square", action: { insertPrefix("- [ ] ") }, tooltip: "Task List")
                }
                .padding(.vertical, 8)
            }
            .padding(.leading, 12)

            Spacer()

            Toggle(isOn: $showPreview) {
                Image(systemName: showPreview ? "pencil" : "eye")
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .help(showPreview ? "Edit" : "Preview")
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var preview: some View {
        ScrollView {
            RichMarkdownView(text: text)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.3))
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 16))
            .focused($isFocused)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .onDrop(
                of: MediaAttachmentImporter.supportedDropTypes,
                isTargeted: $isDropTargeted,
                perform: handleDrop
            )
            .onPasteCommand(of: MediaAttachmentImporter.supportedDropTypes) { providers in
                handlePaste(providers)
            }
    }

    private func wrapSelection(_ wrapper: String) {
        text += "\(wrapper)text\(wrapper)"
    }

    private func insertLink() {
        text += "[link text](url)"
    }

    private func insertPrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n\(prefix)"
        }
    }

    private func handlePaste(_ providers: [NSItemProvider]) {
        MediaAttachmentImporter.importFirst(from: providers) { relativePath in
            guard let relativePath else { return }
            DispatchQueue.main.async {
                insertMedia(relativePath)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        handlePaste(providers)
        return true
    }

    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isFocused,
                  event.charactersIgnoringModifiers?.lowercased() == "v",
                  ShortcutPreference.menuModifierFlags(from: event.modifierFlags) == .command,
                  let relativePath = MediaAttachmentImporter.importFromPasteboard() else {
                return event
            }

            insertMedia(relativePath)
            return nil
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }
}

private struct MarkdownButton: View {
    let symbol: String
    let action: () -> Void
    let tooltip: String

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
