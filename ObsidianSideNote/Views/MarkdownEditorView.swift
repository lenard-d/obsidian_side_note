import SwiftUI
import AppKit
import Combine

struct MarkdownEditorView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var focusRequestID: Int
    @Binding var cursorEndRequestID: Int
    let insertMedia: (String) -> Void
    @State private var isDropTargeted = false
    @StateObject private var commandDispatcher = MarkdownEditorCommandDispatcher()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editor
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
                    MarkdownButton(symbol: "bold", action: { sendCommand(.wrap("**")) }, tooltip: "Bold")
                    MarkdownButton(symbol: "italic", action: { sendCommand(.wrap("*")) }, tooltip: "Italic")
                    MarkdownButton(symbol: "highlighter", action: { sendCommand(.wrap("==")) }, tooltip: "Highlight")
                    MarkdownButton(symbol: "curlybraces", action: { sendCommand(.wrap("`")) }, tooltip: "Inline Code")

                    Divider()
                        .frame(height: 16)

                    MarkdownButton(symbol: "link", action: { sendCommand(.insertLink) }, tooltip: "Link")
                    MarkdownButton(symbol: "list.bullet", action: { sendCommand(.insertPrefix("- ")) }, tooltip: "Bullet List")
                    MarkdownButton(symbol: "list.number", action: { sendCommand(.insertPrefix("1. ")) }, tooltip: "Numbered List")
                    MarkdownButton(symbol: "checkmark.square", action: { sendCommand(.insertPrefix("- [ ] ")) }, tooltip: "Task List")
                }
                .padding(.vertical, 8)
            }
            .padding(.leading, 12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var editor: some View {
        RichMarkdownEditorView(
            text: $text,
            isFocused: $isFocused,
            focusRequestID: $focusRequestID,
            cursorEndRequestID: $cursorEndRequestID,
            commandDispatcher: commandDispatcher,
            insertMedia: insertMedia,
            didInsertMedia: {}
        )
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

    private func sendCommand(_ command: MarkdownEditorCommand) {
        commandDispatcher.send(command)
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
}

enum MarkdownEditorCommand: Equatable {
    case wrap(String)
    case insertLink
    case insertPrefix(String)
}

@MainActor
final class MarkdownEditorCommandDispatcher: ObservableObject {
    private weak var owner: AnyObject?
    private var handler: ((MarkdownEditorCommand) -> Void)?

    func connect(owner: AnyObject, _ handler: @escaping (MarkdownEditorCommand) -> Void) {
        self.owner = owner
        self.handler = handler
    }

    func disconnect(owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        handler = nil
    }

    func send(_ command: MarkdownEditorCommand) {
        handler?(command)
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
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .accessibilityLabel(tooltip)
        .accessibilityIdentifier("markdown-toolbar-\(symbol)")
        .help(tooltip)
    }
}
