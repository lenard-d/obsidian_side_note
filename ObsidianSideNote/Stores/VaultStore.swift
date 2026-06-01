import AppKit
import Foundation

struct VaultStore {
    static let bookmarkKey = "obsidianVaultBookmark"
    static let pathKey = "obsidianVaultPath"

    static var selectedVaultURL: URL? {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    saveVaultURL(url)
                }
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    static var selectedVaultName: String {
        selectedVaultURL?.lastPathComponent
            ?? UserDefaults.standard.string(forKey: "obsidianVault")
            ?? ""
    }

    static var isVaultConfigured: Bool {
        selectedVaultURL != nil
    }

    static func saveVaultURL(_ url: URL) {
        if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        }
        UserDefaults.standard.set(url.path, forKey: pathKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "obsidianVault")
    }

    static func chooseVaultFolder(message: String = "Choose your Obsidian vault folder.") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = message

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        saveVaultURL(url)
        return url
    }

    static func markdownNotes(matching query: String = "") -> [VaultNote] {
        guard let vaultURL = selectedVaultURL else { return [] }
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var notes: [VaultNote] = []

        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".obsidian") || fileURL.pathComponents.contains(".trash") {
                enumerator.skipDescendants()
                continue
            }

            guard fileURL.pathExtension.lowercased() == "md",
                  ((try? fileURL.resourceValues(forKeys: Set(resourceKeys)).isRegularFile) == true) else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let title = fileURL.deletingPathExtension().lastPathComponent
            let haystack = "\(title) \(relativePath)".lowercased()

            if normalizedQuery.isEmpty || haystack.contains(normalizedQuery) {
                notes.append(VaultNote(relativePath: relativePath, title: title, url: fileURL))
            }
        }

        return notes.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    static func read(_ note: VaultNote) -> String {
        let vaultURL = selectedVaultURL
        let didAccess = vaultURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                vaultURL?.stopAccessingSecurityScopedResource()
            }
        }

        return (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    static func write(_ text: String, to note: VaultNote) {
        let vaultURL = selectedVaultURL
        let didAccess = vaultURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                vaultURL?.stopAccessingSecurityScopedResource()
            }
        }

        try? text.write(to: note.url, atomically: true, encoding: .utf8)
        if let vaultURL {
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
        }
    }

    static func createOrUpdateNote(title: String, text: String, fallbackDate: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let rawTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = safeFileName(rawTitle.isEmpty ? "Quick Note \(fallbackDate)" : rawTitle)
        let fileURL = vaultURL.appendingPathComponent(filename).appendingPathExtension("md")
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
        } catch {
            return nil
        }

        return VaultNote(relativePath: fileURL.lastPathComponent, title: filename, url: fileURL)
    }

    static func note(relativePath: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL, !relativePath.isEmpty else { return nil }
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        let title = fileURL.deletingPathExtension().lastPathComponent
        return VaultNote(relativePath: relativePath, title: title, url: fileURL)
    }

    static func copyAttachment(from sourceURL: URL) -> String? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        let attachmentsURL = attachmentDirectoryURL(in: vaultURL)
        do {
            try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            let destinationURL = uniqueAttachmentURL(
                in: attachmentsURL,
                baseName: sourceURL.deletingPathExtension().lastPathComponent,
                fileExtension: sourceURL.pathExtension
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultRelativePath(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func saveAttachmentImage(_ image: NSImage, suggestedName: String = "Pasted Image") -> String? {
        guard let vaultURL = selectedVaultURL,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        let attachmentsURL = attachmentDirectoryURL(in: vaultURL)
        do {
            try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            let destinationURL = uniqueAttachmentURL(in: attachmentsURL, baseName: suggestedName, fileExtension: "png")
            try pngData.write(to: destinationURL, options: .atomic)
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultRelativePath(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func url(forMarkdownLink link: String) -> URL? {
        if let url = URL(string: link), url.scheme != nil {
            return url
        }

        guard let vaultURL = selectedVaultURL else { return nil }
        let cleanedPath = link.removingPercentEncoding ?? link
        let directURL = vaultURL.appendingPathComponent(cleanedPath)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        if let foundURL = findVaultFile(named: cleanedPath, in: vaultURL) {
            return foundURL
        }

        if cleanedPath.contains("/") || !URL(fileURLWithPath: cleanedPath).pathExtension.isEmpty {
            return directURL
        }

        return nil
    }

    static func url(forWikiLink link: String) -> URL? {
        let target = wikiTarget(from: link)
        if let url = url(forMarkdownLink: target) {
            return url
        }

        guard URL(fileURLWithPath: target).pathExtension.isEmpty else {
            return nil
        }

        return url(forMarkdownLink: "\(target).md")
    }

    private static func safeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    private static func attachmentDirectoryURL(in vaultURL: URL) -> URL {
        guard let configuredPath = attachmentFolderPath(in: vaultURL), !configuredPath.isEmpty else {
            return vaultURL
        }

        let normalizedPath = configuredPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !normalizedPath.isEmpty, normalizedPath != "." else {
            return vaultURL
        }

        return vaultURL.appendingPathComponent(normalizedPath, isDirectory: true)
    }

    private static func attachmentFolderPath(in vaultURL: URL) -> String? {
        let configURL = vaultURL.appendingPathComponent(".obsidian/app.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["attachmentFolderPath"] as? String else {
            return nil
        }

        return path
            .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\.$"#, with: "", options: .regularExpression)
    }

    private static func vaultRelativePath(for fileURL: URL, in vaultURL: URL) -> String {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(vaultPath.count + 1))
    }

    private static func wikiTarget(from link: String) -> String {
        let withoutAlias = link.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? link
        return withoutAlias.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutAlias
    }

    private static func findVaultFile(named target: String, in vaultURL: URL) -> URL? {
        let decodedTarget = target.removingPercentEncoding ?? target
        let targetFileName = URL(fileURLWithPath: decodedTarget).lastPathComponent.lowercased()
        guard !targetFileName.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: vaultURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
              ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".obsidian") || fileURL.pathComponents.contains(".trash") {
                enumerator.skipDescendants()
                continue
            }

            guard ((try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true),
                  fileURL.lastPathComponent.lowercased() == targetFileName else {
                continue
            }

            return fileURL
        }

        return nil
    }

    private static func uniqueAttachmentURL(in directoryURL: URL, baseName: String, fileExtension: String) -> URL {
        let safeBaseName = safeFileName(baseName)
        let normalizedExtension = fileExtension.isEmpty ? "dat" : fileExtension.lowercased()
        var candidate = directoryURL
            .appendingPathComponent(safeBaseName)
            .appendingPathExtension(normalizedExtension)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(safeBaseName) \(index)")
                .appendingPathExtension(normalizedExtension)
            index += 1
        }

        return candidate
    }
}
