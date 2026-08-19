import Foundation

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
        guard afterTitle.first == "(", afterTitle.last == ")" else {
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

private struct WikiLink {
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
        let target = rawTarget.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? rawTarget

        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.target = target
        alias = parts.count > 1 ? String(parts[1]) : nil
        self.isEmbed = isEmbed
    }
}
