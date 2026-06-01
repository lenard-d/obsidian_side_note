import AVKit
import MarkdownUI
import SwiftUI

struct RichMarkdownView: View {
    let text: String

    private var blocks: [MarkdownRenderBlock] {
        MarkdownRenderBlock.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.kind {
                case .markdown(let markdown):
                    Markdown(markdown)
                        .markdownTextStyle(\.text) {
                            FontSize(16)
                            ForegroundColor(.primary)
                        }
                        .markdownTextStyle(\.code) {
                            FontFamilyVariant(.monospaced)
                            FontSize(14)
                            BackgroundColor(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding()
                                .markdownTextStyle {
                                    FontFamilyVariant(.monospaced)
                                    FontSize(14)
                                }
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                .cornerRadius(8)
                        }
                        .markdownBlockStyle(\.taskListMarker) { configuration in
                            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundColor(configuration.isCompleted ? .green : .secondary)
                        }

                case .media(let media):
                    EmbeddedMediaView(media: media)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct MarkdownRenderBlock: Identifiable {
    enum Kind {
        case markdown(String)
        case media(EmbeddedMedia)
    }

    let id = UUID()
    let kind: Kind

    static func blocks(from text: String) -> [MarkdownRenderBlock] {
        var blocks: [MarkdownRenderBlock] = []
        var markdownBuffer: [String] = []

        func flushMarkdown() {
            let markdown = markdownBuffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !markdown.isEmpty {
                blocks.append(MarkdownRenderBlock(kind: .markdown(markdown)))
            }
            markdownBuffer.removeAll()
        }

        for line in text.components(separatedBy: .newlines) {
            if let media = EmbeddedMedia(markdownLine: line) {
                flushMarkdown()
                blocks.append(MarkdownRenderBlock(kind: .media(media)))
            } else {
                markdownBuffer.append(line)
            }
        }

        flushMarkdown()
        return blocks
    }
}

struct EmbeddedMedia {
    enum MediaType {
        case image
        case video
    }

    let title: String
    let link: String
    let type: MediaType

    init?(markdownLine: String) {
        let trimmedLine = markdownLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("!["),
              let titleEnd = trimmedLine.firstIndex(of: "]"),
              titleEnd < trimmedLine.endIndex else {
            return nil
        }

        let afterTitle = trimmedLine[trimmedLine.index(after: titleEnd)...]
        guard afterTitle.first == "(",
              afterTitle.last == ")" else {
            return nil
        }

        let titleStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: 2)
        let parsedTitle = String(trimmedLine[titleStart..<titleEnd])
        let linkStart = afterTitle.index(after: afterTitle.startIndex)
        let linkEnd = afterTitle.index(before: afterTitle.endIndex)
        let parsedLink = String(afterTitle[linkStart..<linkEnd])
        let fileExtension = URL(fileURLWithPath: parsedLink).pathExtension.lowercased()

        if Self.imageExtensions.contains(fileExtension) {
            title = parsedTitle
            link = parsedLink
            type = .image
        } else if Self.videoExtensions.contains(fileExtension) {
            title = parsedTitle
            link = parsedLink
            type = .video
        } else {
            return nil
        }
    }

    private static let imageExtensions = ["apng", "avif", "gif", "jpeg", "jpg", "png", "svg", "webp"]
    private static let videoExtensions = ["m4v", "mov", "mp4"]
}

private struct EmbeddedMediaView: View {
    let media: EmbeddedMedia

    var body: some View {
        switch media.type {
        case .image:
            embeddedImage
        case .video:
            embeddedVideo
        }
    }

    @ViewBuilder
    private var embeddedImage: some View {
        if let url = VaultStore.url(forMarkdownLink: media.link) {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        mediaFallback
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    @unknown default:
                        mediaFallback
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            mediaFallback
        }
    }

    @ViewBuilder
    private var embeddedVideo: some View {
        if let url = VaultStore.url(forMarkdownLink: media.link) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            mediaFallback
        }
    }

    private var mediaFallback: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(media.title.isEmpty ? media.link : media.title)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
