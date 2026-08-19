import Foundation

enum MarkdownEditorResource {
    enum ResourceError: Error {
        case missingIndexHTML
        case missingEditorJavaScript
        case unreadableResource(URL)
    }

    static func bundledHTML(testing: Bool = false) throws -> String {
        let indexURL = try resourceURL(named: "index", extension: "html")
        let editorURL = try resourceURL(named: "editor", extension: "js")

        guard let indexHTML = try? String(contentsOf: indexURL, encoding: .utf8) else {
            throw ResourceError.unreadableResource(indexURL)
        }
        guard let editorJavaScript = try? String(contentsOf: editorURL, encoding: .utf8) else {
            throw ResourceError.unreadableResource(editorURL)
        }

        return inlineHTML(indexHTML: indexHTML, editorJavaScript: editorJavaScript, testing: testing)
    }

    static func inlineHTML(indexHTML: String, editorJavaScript: String, testing: Bool = false) -> String {
        let escapedJavaScript = editorJavaScript.replacingOccurrences(of: "</script", with: "<\\/script")
        let testFlag = testing ? "window.__OSN_EDITOR_TESTING__ = true;\n" : ""
        let inlineScript = "<script>\n\(testFlag)\(escapedJavaScript)\n</script>"
        let externalScript = #"<script src="editor.js"></script>"#

        if indexHTML.contains(externalScript) {
            return indexHTML.replacingOccurrences(of: externalScript, with: inlineScript)
        }

        return indexHTML.replacingOccurrences(of: "</body>", with: "\(inlineScript)\n  </body>")
    }

    private static func resourceURL(named name: String, extension fileExtension: String) throws -> URL {
        if let nestedURL = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "MarkdownEditor"
        ) {
            return nestedURL
        }

        if let flatURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return flatURL
        }

        throw fileExtension == "html" ? ResourceError.missingIndexHTML : ResourceError.missingEditorJavaScript
    }
}
