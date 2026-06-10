import Foundation

enum MarkdownEditingEngine {
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let highlightRegex = try? NSRegularExpression(pattern: #"==([^=\n]+)=="#)
    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let headingMarkerRegex = try? NSRegularExpression(pattern: #"^\s*#{1,6}\s+"#)
    private static let taskMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+\[([ xX])\]\s+"#)
    private static let unorderedMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+"#)
    private static let orderedMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*)(\d+)([.)])\s+"#)

    struct Edit {
        let markdown: String
        let selectedRange: NSRange
    }

    enum LineMarker: Equatable {
        case task(indentation: String, bullet: String, isChecked: Bool, range: NSRange)
        case unordered(indentation: String, bullet: String, range: NSRange)
        case ordered(indentation: String, number: Int, delimiter: String, range: NSRange)

        var range: NSRange {
            switch self {
            case let .task(_, _, _, range),
                 let .unordered(_, _, range),
                 let .ordered(_, _, _, range):
                return range
            }
        }

        var indentation: String {
            switch self {
            case let .task(indentation, _, _, _),
                 let .unordered(indentation, _, _),
                 let .ordered(indentation, _, _, _):
                return indentation
            }
        }

        var continuation: String {
            switch self {
            case let .task(indentation, bullet, _, _):
                return "\(indentation)\(bullet) [ ] "
            case let .unordered(indentation, bullet, _):
                return "\(indentation)\(bullet) "
            case let .ordered(indentation, number, delimiter, _):
                return "\(indentation)\(number + 1)\(delimiter) "
            }
        }
    }

    static func marker(in line: String) -> LineMarker? {
        if let task = taskMarker(in: line) {
            return task
        }

        if let ordered = orderedMarker(in: line) {
            return ordered
        }

        return unorderedMarker(in: line)
    }

    static func isTaskListItem(_ line: String) -> Bool {
        taskMarker(in: line) != nil
    }

    static func isTaskMarkerAdjacentVisibleOffset(_ visibleOffset: Int, in sourceLine: String) -> Bool {
        guard case let .task(indentation, _, _, _) = marker(in: sourceLine) else { return false }
        let indentationLength = (indentation as NSString).length
        let lowerBound = indentationLength
        let upperBound = indentationLength + max(0, taskCheckboxPrefixLength - 1)
        return (lowerBound...upperBound).contains(visibleOffset)
    }

    static func sourceOffset(forVisibleOffset visibleOffset: Int, in sourceLine: String) -> Int {
        if case let .task(indentation, _, _, range) = marker(in: sourceLine) {
            let indentationLength = (indentation as NSString).length
            if visibleOffset <= indentationLength {
                return visibleOffset
            }
            if visibleOffset == indentationLength + 1 {
                return max(range.location, range.upperBound - 1)
            }
            return range.upperBound + max(0, visibleOffset - indentationLength - taskCheckboxPrefixLength)
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

    static func visibleOffset(forSourceOffset sourceOffset: Int, in sourceLine: String) -> Int {
        if case let .task(indentation, _, _, range) = marker(in: sourceLine) {
            let indentationLength = (indentation as NSString).length
            if sourceOffset <= indentationLength {
                return sourceOffset
            }
            guard sourceOffset >= range.upperBound else {
                return indentationLength + max(0, taskCheckboxPrefixLength - 1)
            }
            return indentationLength + taskCheckboxPrefixLength + max(0, sourceOffset - range.upperBound)
        }

        return sourceOffset
    }

    static func toggledTaskListItem(in source: String, lineIndex: Int) -> String? {
        var lines = source.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              case let .task(_, _, isChecked, range) = marker(in: lines[lineIndex]) else {
            return nil
        }

        let nsLine = lines[lineIndex] as NSString
        let markerText = nsLine.substring(with: range)
        let toggledMarker = markerText.replacingCheckboxMarker(with: isChecked ? "[ ]" : "[x]")
        lines[lineIndex] = nsLine.replacingCharacters(in: range, with: toggledMarker)
        return lines.joined(separator: "\n")
    }

    static func smartNewline(in source: String, selectedRange: NSRange) -> Edit? {
        guard selectedRange.length == 0 else { return nil }
        let lineIndex = lineIndex(in: source, at: selectedRange.location)
        let line = line(at: lineIndex, in: source)
        guard let marker = marker(in: line) else { return nil }

        let lineStart = lineStartLocation(in: source, lineIndex: lineIndex)
        let cursorOffset = max(0, selectedRange.location - lineStart)
        let markerRange = marker.range
        let content = (line as NSString).substring(from: min(markerRange.upperBound, (line as NSString).length))

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let replacement = marker.indentation
            let markerSourceRange = NSRange(
                location: lineStart + markerRange.location,
                length: markerRange.length
            )
            let markdown = (source as NSString).replacingCharacters(in: markerSourceRange, with: replacement)
            return Edit(
                markdown: markdown,
                selectedRange: NSRange(location: lineStart + (replacement as NSString).length, length: 0)
            )
        }

        let insertLocation = lineStart + cursorOffset
        let insertion = "\n\(marker.continuation)"
        let markdown = (source as NSString).replacingCharacters(in: selectedRange, with: insertion)
        return Edit(
            markdown: markdown,
            selectedRange: NSRange(location: insertLocation + (insertion as NSString).length, length: 0)
        )
    }

    static func indentLines(in source: String, selectedRange: NSRange) -> Edit? {
        editSelectedLines(in: source, selectedRange: selectedRange) { line in
            guard marker(in: line) != nil else { return line }
            return "  \(line)"
        }
    }

    static func outdentLines(in source: String, selectedRange: NSRange) -> Edit? {
        editSelectedLines(in: source, selectedRange: selectedRange) { line in
            guard marker(in: line) != nil else { return line }
            if line.hasPrefix("  ") {
                return String(line.dropFirst(2))
            }
            return line
        }
    }

    static func lineIndex(in string: String, at location: Int) -> Int {
        let clampedLocation = min(max(location, 0), (string as NSString).length)
        let prefix = (string as NSString).substring(to: clampedLocation)
        return prefix.reduce(0) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    static func lineStartLocation(in string: String, lineIndex: Int) -> Int {
        guard lineIndex > 0 else { return 0 }
        var currentLine = 0
        var utf16Location = 0

        for character in string {
            if currentLine == lineIndex {
                return utf16Location
            }
            utf16Location += character.utf16.count
            if character == "\n" {
                currentLine += 1
            }
        }

        return utf16Location
    }

    static func line(at lineIndex: Int, in string: String) -> String {
        let lines = string.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex) else { return "" }
        return lines[lineIndex]
    }

    private struct HiddenSyntaxRange {
        let range: NSRange
        let skipAtBoundary: Bool
    }

    private static var taskCheckboxPrefixLength: Int {
        ("\u{2610} " as NSString).length
    }

    private static func taskMarker(in line: String) -> LineMarker? {
        guard let match = firstMatch(taskMarkerRegex, in: line) else { return nil }
        let nsLine = line as NSString
        let indentation = nsLine.substring(with: match.range(at: 1))
        let bullet = nsLine.substring(with: match.range(at: 2))
        let checked = nsLine.substring(with: match.range(at: 3)).lowercased() == "x"
        return .task(indentation: indentation, bullet: bullet, isChecked: checked, range: match.range)
    }

    private static func unorderedMarker(in line: String) -> LineMarker? {
        guard let match = firstMatch(unorderedMarkerRegex, in: line) else { return nil }
        let nsLine = line as NSString
        return .unordered(
            indentation: nsLine.substring(with: match.range(at: 1)),
            bullet: nsLine.substring(with: match.range(at: 2)),
            range: match.range
        )
    }

    private static func orderedMarker(in line: String) -> LineMarker? {
        guard let match = firstMatch(orderedMarkerRegex, in: line) else { return nil }
        let nsLine = line as NSString
        return .ordered(
            indentation: nsLine.substring(with: match.range(at: 1)),
            number: Int(nsLine.substring(with: match.range(at: 2))) ?? 1,
            delimiter: nsLine.substring(with: match.range(at: 3)),
            range: match.range
        )
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in line: String) -> NSTextCheckingResult? {
        guard let regex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range)
    }

    private static func hiddenSyntaxRanges(in line: String) -> [HiddenSyntaxRange] {
        var ranges: [HiddenSyntaxRange] = []

        if let headingMarkerRange = firstMatch(headingMarkerRegex, in: line)?.range {
            ranges.append(HiddenSyntaxRange(range: headingMarkerRange, skipAtBoundary: true))
        }

        if case let .task(_, _, _, range) = marker(in: line) {
            ranges.append(HiddenSyntaxRange(range: range, skipAtBoundary: true))
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

    private static func lineRange(in string: String, lineIndex: Int) -> NSRange {
        let nsString = string as NSString
        let lineStart = lineStartLocation(in: string, lineIndex: lineIndex)
        return nsString.lineRange(for: NSRange(location: lineStart, length: 0))
    }

    private static func editSelectedLines(
        in source: String,
        selectedRange: NSRange,
        transform: (String) -> String
    ) -> Edit? {
        let nsSource = source as NSString
        let selectedLineRange = nsSource.lineRange(for: selectedRange)
        let selectedText = nsSource.substring(with: selectedLineRange)
        let hasTrailingNewline = selectedText.hasSuffix("\n")
        var lines = selectedText.components(separatedBy: "\n")
        if hasTrailingNewline {
            lines.removeLast()
        }

        var didChange = false
        var selectionLocationDelta = 0
        var selectionLengthDelta = 0
        var currentLocation = selectedLineRange.location
        let transformedLines = lines.map { line -> String in
            let transformed = transform(line)
            if transformed != line {
                didChange = true
                let delta = (transformed as NSString).length - (line as NSString).length
                if currentLocation < selectedRange.location {
                    selectionLocationDelta += delta
                } else if currentLocation < selectedRange.upperBound {
                    selectionLengthDelta += delta
                }
            }
            currentLocation += (line as NSString).length + 1
            return transformed
        }

        guard didChange else { return nil }
        let replacement = transformedLines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        let markdown = nsSource.replacingCharacters(in: selectedLineRange, with: replacement)
        return Edit(
            markdown: markdown,
            selectedRange: NSRange(
                location: max(0, selectedRange.location + selectionLocationDelta),
                length: max(0, selectedRange.length + selectionLengthDelta)
            )
        )
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
