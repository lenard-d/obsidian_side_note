import AppKit

enum MarkdownEditorCommandApplier {
    static func apply(_ command: MarkdownEditorCommand, in textView: NSTextView) {
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
        let selectedRange = textView.selectedRange()
        let nsString = textView.string as NSString
        let selectedText = selectedRange.length > 0 ? nsString.substring(with: selectedRange) : "text"
        let replacement = "\(wrapper)\(selectedText)\(wrapper)"

        textView.shouldChangeText(in: selectedRange, replacementString: replacement)
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
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        let selectedText = selectedRange.length > 0 ? text.substring(with: selectedRange) : replacement
        let finalReplacement = selectedRange.length > 0 && selectedPlaceholder != nil
            ? replacement.replacingOccurrences(of: selectedPlaceholder ?? "", with: selectedText)
            : selectedText

        textView.shouldChangeText(in: selectedRange, replacementString: finalReplacement)
        textView.replaceCharacters(in: selectedRange, with: finalReplacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selectedRange.location, length: finalReplacement.utf16.count))
    }

    static func insertLinePrefix(_ prefix: String, in textView: NSTextView) {
        let selectedRange = textView.selectedRange()
        let nsString = textView.string as NSString
        let lineRange = nsString.lineRange(for: selectedRange)
        let replacement = prefix + nsString.substring(with: lineRange)

        textView.shouldChangeText(in: lineRange, replacementString: replacement)
        textView.replaceCharacters(in: lineRange, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selectedRange.location + prefix.utf16.count, length: selectedRange.length))
    }
}
