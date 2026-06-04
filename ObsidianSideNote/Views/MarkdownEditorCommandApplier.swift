import AppKit
import STTextView

enum MarkdownEditorCommandApplier {
    static func apply(_ command: MarkdownEditorCommand, in textView: NSTextView) {
        apply(command, in: NSTextViewMarkdownEditingAdapter(textView: textView))
    }

    static func apply(_ command: MarkdownEditorCommand, in textView: MediaTextView) {
        apply(command, in: MediaTextViewMarkdownEditingAdapter(textView: textView))
    }

    private static func apply(_ command: MarkdownEditorCommand, in textView: MarkdownEditingTextView) {
        switch command {
        case let .wrap(wrapper):
            wrapSelection(in: textView, wrapper: wrapper)
        case .insertLink:
            replaceSelection(in: textView, with: "[link text](url)", selectedPlaceholder: "link text")
        case let .insertPrefix(prefix):
            insertLinePrefix(prefix, in: textView)
        }
    }

    static func wrapSelection(in textView: NSTextView, wrapper: String) {
        wrapSelection(in: NSTextViewMarkdownEditingAdapter(textView: textView), wrapper: wrapper)
    }

    static func wrapSelection(in textView: MediaTextView, wrapper: String) {
        wrapSelection(in: MediaTextViewMarkdownEditingAdapter(textView: textView), wrapper: wrapper)
    }

    private static func wrapSelection(in textView: MarkdownEditingTextView, wrapper: String) {
        let selectedRange = textView.selectedRange()
        let nsString = textView.string as NSString
        let selectedText = selectedRange.length > 0 ? nsString.substring(with: selectedRange) : "text"
        let replacement = "\(wrapper)\(selectedText)\(wrapper)"

        _ = textView.shouldChangeText(in: selectedRange, replacementString: replacement)
        textView.replaceCharacters(in: selectedRange, with: replacement)
        textView.didChangeText()

        if selectedRange.length == 0 {
            let cursorLocation = selectedRange.location + wrapper.utf16.count
            textView.setSelectedRange(NSRange(location: cursorLocation, length: selectedText.utf16.count))
        } else {
            textView.setSelectedRange(NSRange(location: selectedRange.location, length: replacement.utf16.count))
        }
    }

    static func replaceSelection(in textView: NSTextView, with replacement: String, selectedPlaceholder: String? = nil) {
        replaceSelection(in: NSTextViewMarkdownEditingAdapter(textView: textView), with: replacement, selectedPlaceholder: selectedPlaceholder)
    }

    private static func replaceSelection(in textView: MarkdownEditingTextView, with replacement: String, selectedPlaceholder: String? = nil) {
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        let selectedText = selectedRange.length > 0 ? text.substring(with: selectedRange) : replacement
        let finalReplacement = selectedRange.length > 0 && selectedPlaceholder != nil
            ? replacement.replacingOccurrences(of: selectedPlaceholder ?? "", with: selectedText)
            : selectedText

        _ = textView.shouldChangeText(in: selectedRange, replacementString: finalReplacement)
        textView.replaceCharacters(in: selectedRange, with: finalReplacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selectedRange.location, length: finalReplacement.utf16.count))
    }

    static func insertLinePrefix(_ prefix: String, in textView: NSTextView) {
        insertLinePrefix(prefix, in: NSTextViewMarkdownEditingAdapter(textView: textView))
    }

    private static func insertLinePrefix(_ prefix: String, in textView: MarkdownEditingTextView) {
        let selectedRange = textView.selectedRange()
        let nsString = textView.string as NSString
        let lineRange = nsString.lineRange(for: selectedRange)
        let replacement = prefix + nsString.substring(with: lineRange)

        _ = textView.shouldChangeText(in: lineRange, replacementString: replacement)
        textView.replaceCharacters(in: lineRange, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selectedRange.location + prefix.utf16.count, length: selectedRange.length))
    }
}

private protocol MarkdownEditingTextView {
    var string: String { get }

    func selectedRange() -> NSRange
    func shouldChangeText(in range: NSRange, replacementString: String) -> Bool
    func replaceCharacters(in range: NSRange, with string: String)
    func didChangeText()
    func setSelectedRange(_ range: NSRange)
}

private struct NSTextViewMarkdownEditingAdapter: MarkdownEditingTextView {
    let textView: NSTextView

    var string: String {
        textView.string
    }

    func selectedRange() -> NSRange {
        textView.selectedRange()
    }

    func shouldChangeText(in range: NSRange, replacementString: String) -> Bool {
        textView.shouldChangeText(in: range, replacementString: replacementString)
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        textView.replaceCharacters(in: range, with: string)
    }

    func didChangeText() {
        textView.didChangeText()
    }

    func setSelectedRange(_ range: NSRange) {
        textView.setSelectedRange(range)
    }
}

private struct MediaTextViewMarkdownEditingAdapter: MarkdownEditingTextView {
    let textView: MediaTextView

    var string: String {
        textView.string
    }

    func selectedRange() -> NSRange {
        textView.textSelection
    }

    func shouldChangeText(in range: NSRange, replacementString: String) -> Bool {
        true
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        textView.replaceCharacters(in: range, with: string)
    }

    func didChangeText() {
        // STTextView posts its change notification from replaceCharacters(in:with:).
    }

    func setSelectedRange(_ range: NSRange) {
        textView.setSelectedRange(range)
    }
}
