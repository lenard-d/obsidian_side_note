import AppKit

enum MarkdownEditorTextRenderer {
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let highlightRegex = try? NSRegularExpression(pattern: #"==([^=\n]+)=="#)
    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let taskMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[[ xX]\]\s+)"#)

    @MainActor
    static func attributedString(from source: String, mediaWidth: CGFloat, activeLineIndex: Int? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = source.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let isActiveLine = index == activeLineIndex

            if let media = EmbeddedMedia(markdownLine: line),
               media.type == .image,
               let image = cachedImage(for: media.link, maxWidth: mediaWidth) {
                let attachment = MarkdownMediaTextAttachment(markdown: line, image: image)
                if isActiveLine {
                    result.append(attributedLine(line, revealSyntax: true))
                    result.append(NSAttributedString(string: "\n", attributes: previewOnlyAttributes))
                    attachment.isPreviewOnly = true
                }
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(attributedLine(line, revealSyntax: isActiveLine))
            }

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            }
        }

        return result
    }

    static func imageLinksNeedingPreload(from source: String, mediaWidth: CGFloat) -> [String] {
        var links: [String] = []
        let pixelWidth = mediaWidth * 2

        for line in source.components(separatedBy: .newlines) {
            guard let media = EmbeddedMedia(markdownLine: line), media.type == .image else {
                continue
            }

            if VaultStore.cachedImage(forMediaLink: media.link, maxPixelWidth: pixelWidth) == nil {
                links.append(media.link)
            }
        }

        return links
    }

    static func markdownString(from attributedString: NSAttributedString) -> String {
        var markdown = ""
        var restoredSourceLines: Set<ObjectIdentifier> = []
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attributes, range, _ in
            if attributes[.markdownPreviewOnly] != nil {
                return
            }

            if let sourceLine = attributes[.markdownSourceLine] as? MarkdownSourceLine {
                let id = ObjectIdentifier(sourceLine)
                guard !restoredSourceLines.contains(id) else { return }
                restoredSourceLines.insert(id)
                markdown += sourceLine.markdown
            } else if let attachment = attributes[.attachment] as? MarkdownMediaTextAttachment {
                if attachment.isPreviewOnly {
                    return
                }
                markdown += attachment.markdown
            } else {
                markdown += (attributedString.string as NSString).substring(with: range)
            }
        }
        return markdown
    }

    static func sourceOffset(forVisibleOffset visibleOffset: Int, in sourceLine: String) -> Int {
        if let taskMarkerRange = taskMarkerRange(in: sourceLine) {
            let markerEnd = taskMarkerRange.upperBound
            return markerEnd + max(0, visibleOffset - taskCheckboxPrefixLength)
        }

        let nsLine = sourceLine as NSString
        let hiddenRanges = hiddenSyntaxRanges(in: sourceLine)
        var visibleUTF16Offset = 0
        var sourceUTF16Offset = 0

        while sourceUTF16Offset < nsLine.length {
            if let hiddenRange = hiddenRanges.first(where: { $0.range.location == sourceUTF16Offset }) {
                if hiddenRange.skipAtBoundary || visibleUTF16Offset < visibleOffset {
                    sourceUTF16Offset = hiddenRange.range.upperBound
                    continue
                }
                return sourceUTF16Offset
            }

            guard visibleUTF16Offset < visibleOffset else {
                return sourceUTF16Offset
            }

            sourceUTF16Offset += 1
            visibleUTF16Offset += 1
        }

        return sourceUTF16Offset
    }

    static func toggledTaskListItem(in source: String, lineIndex: Int) -> String? {
        var lines = source.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              let taskMarkerRange = taskMarkerRange(in: lines[lineIndex]) else {
            return nil
        }

        let nsLine = lines[lineIndex] as NSString
        let marker = nsLine.substring(with: taskMarkerRange)
        let toggledMarker = taskMarkerIsChecked(marker)
            ? marker.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression)
            : marker.replacingOccurrences(of: #"\[ \]"#, with: "[x]", options: .regularExpression)
        lines[lineIndex] = nsLine.replacingCharacters(in: taskMarkerRange, with: toggledMarker)
        return lines.joined(separator: "\n")
    }

    private struct HiddenSyntaxRange {
        let range: NSRange
        let skipAtBoundary: Bool
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
    }

    private static var previewOnlyAttributes: [NSAttributedString.Key: Any] {
        typingAttributes.merging([.markdownPreviewOnly: true]) { current, _ in current }
    }

    private static func attributedLine(_ line: String, revealSyntax: Bool) -> NSAttributedString {
        if !revealSyntax, let hiddenLine = hiddenSyntaxLine(from: line) {
            return hiddenLine
        }

        let attributedLine = NSMutableAttributedString(string: line, attributes: blockAttributes(for: line))
        applyInlineStyles(to: attributedLine, in: line, revealSyntax: revealSyntax)
        return attributedLine
    }

    private static func hiddenSyntaxLine(from line: String) -> NSAttributedString? {
        guard let renderedLine = renderedLineByRemovingSyntax(from: line),
              renderedLine != line else {
            return nil
        }

        let sourceLine = MarkdownSourceLine(markdown: line)
        let attributedLine = NSMutableAttributedString(
            string: renderedLine,
            attributes: blockAttributes(for: line).merging([.markdownSourceLine: sourceLine]) { current, _ in current }
        )
        applyHiddenInlineStyles(to: attributedLine, sourceLine: line, renderedLine: renderedLine)
        return attributedLine
    }

    private static func renderedLineByRemovingSyntax(from line: String) -> String? {
        if let headingMarkerRange = headingMarkerRange(in: line) {
            let nsLine = line as NSString
            return nsLine.replacingCharacters(in: headingMarkerRange, with: "")
        }

        if let taskMarkerRange = taskMarkerRange(in: line) {
            let nsLine = line as NSString
            let marker = nsLine.substring(with: taskMarkerRange)
            let indentation = leadingWhitespace(in: marker)
            let checkbox = taskMarkerIsChecked(marker) ? "\u{2611}" : "\u{2610}"
            return indentation + checkbox + " " + nsLine.substring(from: taskMarkerRange.upperBound)
        }

        var renderedLine = line
        renderedLine = renderedLine.replacingOccurrences(of: #"==([^=\n]+)=="#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"~~([^~\n]+)~~"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
        return renderedLine
    }

    private static func applyHiddenInlineStyles(
        to attributedLine: NSMutableAttributedString,
        sourceLine: String,
        renderedLine: String
    ) {
        if let taskMarkerRange = taskMarkerRange(in: sourceLine) {
            let marker = (sourceLine as NSString).substring(with: taskMarkerRange)
            let indentationLength = (leadingWhitespace(in: marker) as NSString).length
            let checkboxRange = NSRange(location: indentationLength, length: 1)
            if checkboxRange.upperBound <= attributedLine.length {
                attributedLine.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                        .foregroundColor: taskMarkerIsChecked(marker) ? NSColor.systemGreen : NSColor.secondaryLabelColor,
                        .markdownTaskCheckbox: true
                    ],
                    range: checkboxRange
                )
            }
        }

        var searchLocation = 0

        applyVisibleCapture(regex: inlineCodeRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            let fontSize = font(at: range.location, in: attributedLine)?.pointSize ?? 16
            attributedLine.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(13, fontSize - 1), weight: .regular),
                    .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.75)
                ],
                range: range
            )
        }

        searchLocation = 0
        applyVisibleCapture(regex: highlightRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            attributedLine.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
        }

        searchLocation = 0
        applyVisibleCapture(regex: boldRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            applyFontTrait(.boldFontMask, to: attributedLine, range: range)
        }

        searchLocation = 0
        applyVisibleCapture(regex: italicRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            applyFontTrait(.italicFontMask, to: attributedLine, range: range)
        }
    }

    private static func applyVisibleCapture(
        regex: NSRegularExpression?,
        sourceLine: String,
        renderedLine: String,
        searchLocation: inout Int,
        body: (NSRange) -> Void
    ) {
        guard let regex else { return }
        let sourceRange = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)
        let renderedNSString = renderedLine as NSString

        for match in regex.matches(in: sourceLine, range: sourceRange) {
            guard match.numberOfRanges > 1 else { continue }
            let visibleText = (sourceLine as NSString).substring(with: match.range(at: 1))
            let remainingRange = NSRange(
                location: min(searchLocation, renderedNSString.length),
                length: max(0, renderedNSString.length - min(searchLocation, renderedNSString.length))
            )
            let renderedRange = renderedNSString.range(of: visibleText, options: [], range: remainingRange)
            guard renderedRange.location != NSNotFound else { continue }
            body(renderedRange)
            searchLocation = renderedRange.upperBound
        }
    }

    private static func hiddenSyntaxRanges(in line: String) -> [HiddenSyntaxRange] {
        var ranges: [HiddenSyntaxRange] = []

        if let headingMarkerRange = headingMarkerRange(in: line) {
            ranges.append(HiddenSyntaxRange(range: headingMarkerRange, skipAtBoundary: true))
        }

        if let taskMarkerRange = taskMarkerRange(in: line) {
            ranges.append(HiddenSyntaxRange(range: taskMarkerRange, skipAtBoundary: true))
        }

        ranges.append(contentsOf: hiddenDelimiterRanges(regex: highlightRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: boldRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: strikethroughRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: inlineCodeRegex, markerLength: 1, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: italicRegex, markerLength: 1, in: line))

        return ranges.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func hiddenDelimiterRanges(
        regex: NSRegularExpression?,
        markerLength: Int,
        in line: String
    ) -> [HiddenSyntaxRange] {
        guard let regex else { return [] }
        let sourceRange = NSRange(line.startIndex..<line.endIndex, in: line)

        return regex.matches(in: line, range: sourceRange).flatMap { match -> [HiddenSyntaxRange] in
            guard match.range.length >= markerLength * 2 else { return [] }
            return [
                HiddenSyntaxRange(
                    range: NSRange(location: match.range.location, length: markerLength),
                    skipAtBoundary: true
                ),
                HiddenSyntaxRange(
                    range: NSRange(location: match.range.upperBound - markerLength, length: markerLength),
                    skipAtBoundary: false
                )
            ]
        }
    }

    private static func blockAttributes(for line: String) -> [NSAttributedString.Key: Any] {
        if let level = headingLevel(in: line) {
            return headingAttributes(level: level)
        }

        if line.trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
            return [
                .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 16), toHaveTrait: .italicFontMask),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        }

        return typingAttributes
    }

    private static var taskCheckboxPrefixLength: Int {
        ("\u{2610} " as NSString).length
    }

    private static func taskMarkerRange(in line: String) -> NSRange? {
        guard let taskMarkerRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = taskMarkerRegex.firstMatch(in: line, range: range) else { return nil }
        return match.range(at: 1)
    }

    private static func taskMarkerIsChecked(_ marker: String) -> Bool {
        marker.range(of: #"\[[xX]\]"#, options: .regularExpression) != nil
    }

    private static func leadingWhitespace(in string: String) -> String {
        String(string.prefix { $0 == " " || $0 == "\t" })
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let sizes: [Int: CGFloat] = [
            1: 26,
            2: 23,
            3: 20,
            4: 18,
            5: 17,
            6: 16
        ]

        return [
            .font: NSFont.systemFont(ofSize: sizes[level] ?? 16, weight: .semibold),
            .foregroundColor: NSColor.textColor
        ]
    }

    private static func applyInlineStyles(to attributedLine: NSMutableAttributedString, in line: String, revealSyntax: Bool) {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        apply(regex: inlineCodeRegex, to: attributedLine, in: line) { _, range in
            let fontSize = font(at: range.location, in: attributedLine)?.pointSize ?? 16
            attributedLine.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(13, fontSize - 1), weight: .regular),
                    .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.75)
                ],
                range: range
            )
        }

        apply(regex: highlightRegex, to: attributedLine, in: line) { _, range in
            attributedLine.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
        }

        apply(regex: boldRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.boldFontMask, to: attributedLine, range: range)
        }

        apply(regex: italicRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.italicFontMask, to: attributedLine, range: range)
        }

        guard fullRange.length == attributedLine.length else { return }
    }

    private static func apply(
        regex: NSRegularExpression?,
        to attributedLine: NSMutableAttributedString,
        in line: String,
        body: (NSTextCheckingResult, NSRange) -> Void
    ) {
        guard let regex else { return }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in regex.matches(in: line, range: range) {
            body(match, match.range)
        }
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to attributedLine: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let currentFont = font(at: range.location, in: attributedLine) else { return }
        let convertedFont = NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
        attributedLine.addAttribute(.font, value: convertedFont, range: range)
    }

    private static func font(at location: Int, in attributedLine: NSAttributedString) -> NSFont? {
        guard attributedLine.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), attributedLine.length - 1)
        return attributedLine.attribute(.font, at: safeLocation, effectiveRange: nil) as? NSFont
    }

    private static func headingMarkerRange(in line: String) -> NSRange? {
        let nsLine = line as NSString
        var markerStart = 0
        let hash = Character("#").utf16.first ?? 0
        let space = Character(" ").utf16.first ?? 0

        while markerStart < nsLine.length {
            let scalar = UnicodeScalar(Int(nsLine.character(at: markerStart)))
            guard let scalar, CharacterSet.whitespaces.contains(scalar) else { break }
            markerStart += 1
        }

        var level = 0
        while markerStart + level < nsLine.length,
              nsLine.character(at: markerStart + level) == hash {
            level += 1
        }

        guard (1...6).contains(level),
              markerStart + level < nsLine.length,
              nsLine.character(at: markerStart + level) == space else {
            return nil
        }

        return NSRange(location: markerStart, length: level + 1)
    }

    private static func headingLevel(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0

        for character in trimmed {
            if character == "#" {
                level += 1
                continue
            }

            guard character == " ", (1...6).contains(level) else {
                return nil
            }

            return level
        }

        return nil
    }

    private static func cachedImage(for link: String, maxWidth: CGFloat) -> NSImage? {
        VaultStore.cachedImage(forMediaLink: link, maxPixelWidth: maxWidth * 2)
    }
}

private final class MarkdownMediaTextAttachment: NSTextAttachment {
    let markdown: String
    var isPreviewOnly = false

    init(markdown: String, image: NSImage) {
        self.markdown = markdown
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: image)
    }

    required init?(coder: NSCoder) {
        markdown = ""
        super.init(coder: coder)
    }
}

private final class MarkdownSourceLine {
    let markdown: String

    init(markdown: String) {
        self.markdown = markdown
    }
}

extension NSAttributedString.Key {
    static let markdownPreviewOnly = NSAttributedString.Key("markdownPreviewOnly")
    static let markdownSourceLine = NSAttributedString.Key("markdownSourceLine")
    static let markdownTaskCheckbox = NSAttributedString.Key("markdownTaskCheckbox")
}
