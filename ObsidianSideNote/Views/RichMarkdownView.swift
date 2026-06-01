import AVKit
import Foundation
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

                case .wikiLink(let link):
                    WikiLinkView(link: link)
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
        case wikiLink(WikiLink)
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
            } else if let wikiLink = WikiLink(markdownLine: line) {
                flushMarkdown()
                blocks.append(MarkdownRenderBlock(kind: .wikiLink(wikiLink)))
            } else {
                markdownBuffer.append(Self.rewriteInlineWikiLinks(in: line))
            }
        }

        flushMarkdown()
        return blocks
    }

    private static func rewriteInlineWikiLinks(in line: String) -> String {
        let pattern = #"(?<!!)\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        var rewritten = ""
        var currentIndex = line.startIndex
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)

        regex.enumerateMatches(in: line, range: nsRange) { match, _, _ in
            guard let match,
                  let matchRange = Range(match.range, in: line),
                  let targetRange = Range(match.range(at: 1), in: line) else {
                return
            }

            rewritten += String(line[currentIndex..<matchRange.lowerBound])

            let target = String(line[targetRange])
            let alias: String
            if match.range(at: 2).location != NSNotFound,
               let aliasRange = Range(match.range(at: 2), in: line) {
                alias = String(line[aliasRange])
            } else {
                alias = URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
            }

            if let url = ObsidianURIBuilder.openFile(vaultName: VaultStore.selectedVaultName, filePath: target) {
                rewritten += "[\(alias)](\(url.absoluteString))"
            } else {
                rewritten += alias
            }

            currentIndex = matchRange.upperBound
        }

        rewritten += String(line[currentIndex..<line.endIndex])
        return rewritten
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
        if let wikiEmbed = WikiLink(markdownLine: trimmedLine), wikiEmbed.isEmbed {
            let parsedLink = wikiEmbed.target
            let fileExtension = URL(fileURLWithPath: parsedLink).pathExtension.lowercased()

            if Self.imageExtensions.contains(fileExtension) {
                title = wikiEmbed.displayText
                link = parsedLink
                type = .image
            } else if Self.videoExtensions.contains(fileExtension) {
                title = wikiEmbed.displayText
                link = parsedLink
                type = .video
            } else {
                return nil
            }

            return
        }

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

    private static let imageExtensions = ["apng", "avif", "gif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
    private static let videoExtensions = ["m4v", "mov", "mp4"]
}

struct WikiLink {
    let target: String
    let alias: String?
    let isEmbed: Bool

    var displayText: String {
        alias ?? URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
    }

    init?(markdownLine: String) {
        let trimmedLine = markdownLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmbed = trimmedLine.hasPrefix("![[")
        let prefix = isEmbed ? "![[" : "[["

        guard trimmedLine.hasPrefix(prefix), trimmedLine.hasSuffix("]]") else {
            return nil
        }

        let startIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: prefix.count)
        let endIndex = trimmedLine.index(trimmedLine.endIndex, offsetBy: -2)
        let body = String(trimmedLine[startIndex..<endIndex])
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let rawTarget = String(parts.first ?? "")
        let target = rawTarget.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawTarget

        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.target = target
        self.alias = parts.count > 1 ? String(parts[1]) : nil
        self.isEmbed = isEmbed
    }
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
        if let url = VaultStore.url(forWikiLink: media.link) {
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
        if let url = VaultStore.url(forWikiLink: media.link) {
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

private struct WikiLinkView: View {
    let link: WikiLink

    var body: some View {
        Button {
            open()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                Text(link.displayText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open linked note")
    }

    private func open() {
        if let url = VaultStore.url(forWikiLink: link.target) {
            NSWorkspace.shared.open(url)
        }
    }
}
