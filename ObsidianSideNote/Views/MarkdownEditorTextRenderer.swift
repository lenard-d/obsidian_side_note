import AppKit

enum MarkdownEditorTextRenderer {
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let highlightRegex = try? NSRegularExpression(pattern: #"==([^=\n]+)=="#)
    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let taskMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[[ xX]\]\s+)"#)

    @MainActor
    static func attributedString(
        from source: String,
        mediaWidth: CGFloat,
        activeLineIndex: Int? = nil,
        activeTaskMarkerLineIndex: Int? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = source.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            result.append(attributedLine(line))

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
        attributedString.string
    }

    static func sourceOffset(forVisibleOffset visibleOffset: Int, in sourceLine: String) -> Int {
        visibleOffset
    }

    static func visibleOffset(forSourceOffset sourceOffset: Int, in sourceLine: String) -> Int {
        sourceOffset
    }

    static func isTaskListItem(_ line: String) -> Bool {
        MarkdownEditingEngine.isTaskListItem(line)
    }

    static func isTaskMarkerAdjacentVisibleOffset(_ visibleOffset: Int, in sourceLine: String) -> Bool {
        MarkdownEditingEngine.isTaskMarkerAdjacentVisibleOffset(visibleOffset, in: sourceLine)
    }

    static func toggledTaskListItem(in source: String, lineIndex: Int) -> String? {
        MarkdownEditingEngine.toggledTaskListItem(in: source, lineIndex: lineIndex)
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
    }

    private static func attributedLine(_ line: String) -> NSAttributedString {
        let attributedLine = NSMutableAttributedString(string: line, attributes: blockAttributes(for: line))
        applyTaskCheckboxStyle(to: attributedLine, in: line)
        applyInlineStyles(to: attributedLine, in: line)
        return attributedLine
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

    private static func taskMarkerRange(in line: String) -> NSRange? {
        guard let taskMarkerRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = taskMarkerRegex.firstMatch(in: line, range: range) else { return nil }
        return match.range(at: 1)
    }

    private static func taskCheckboxRange(in line: String) -> NSRange? {
        guard let markerRange = taskMarkerRange(in: line) else { return nil }
        let marker = (line as NSString).substring(with: markerRange)
        let checkboxRange = (marker as NSString).range(of: #"\[[ xX]\]"#, options: .regularExpression)
        guard checkboxRange.location != NSNotFound else { return nil }
        return NSRange(location: markerRange.location + checkboxRange.location, length: checkboxRange.length)
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

    private static func applyTaskCheckboxStyle(to attributedLine: NSMutableAttributedString, in line: String) {
        guard let checkboxRange = taskCheckboxRange(in: line),
              checkboxRange.upperBound <= attributedLine.length else {
            return
        }

        let checkbox = (line as NSString).substring(with: checkboxRange)
        let isChecked = checkbox.range(of: "x", options: .caseInsensitive) != nil
        attributedLine.addAttributes(
            [
                .foregroundColor: isChecked ? NSColor.systemGreen : NSColor.secondaryLabelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium),
                .markdownTaskCheckbox: true
            ],
            range: checkboxRange
        )
    }

    private static func applyInlineStyles(to attributedLine: NSMutableAttributedString, in line: String) {
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
}

private extension String {
    func replacingCheckboxMarker(with replacement: String) -> String {
        let checkboxRange = range(of: "[ ]")
            ?? range(of: "[x]")
            ?? range(of: "[X]")
        guard let checkboxRange else {
            return self
        }

        var updated = self
        updated.replaceSubrange(checkboxRange, with: replacement)
        return updated
    }
}

extension NSAttributedString.Key {
    static let markdownTaskCheckbox = NSAttributedString.Key("markdownTaskCheckbox")
}
