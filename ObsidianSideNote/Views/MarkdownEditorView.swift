import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MarkdownEditorView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let insertMedia: (String) -> Void
    @State private var showPreview = false

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
            .onPasteCommand(of: [.image, .fileURL, .movie]) { providers in
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
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage,
                          let relativePath = VaultStore.saveAttachmentImage(image) else {
                        return
                    }

                    DispatchQueue.main.async {
                        insertMedia(relativePath)
                    }
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let sourceURL: URL?
                    if let url = item as? URL {
                        sourceURL = url
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        sourceURL = url
                    } else {
                        sourceURL = nil
                    }

                    guard let sourceURL,
                          isSupportedMedia(sourceURL),
                          let relativePath = VaultStore.copyAttachment(from: sourceURL) else {
                        return
                    }

                    DispatchQueue.main.async {
                        insertMedia(relativePath)
                    }
                }
                return
            }
        }
    }

    private func isSupportedMedia(_ url: URL) -> Bool {
        let supportedExtensions = ["apng", "avif", "gif", "jpeg", "jpg", "m4v", "mov", "mp4", "png", "svg", "webp"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
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
