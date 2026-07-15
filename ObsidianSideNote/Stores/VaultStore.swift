import AppKit
import Foundation
import ImageIO
import OSLog

struct VaultStore {
    static let bookmarkKey = "obsidianVaultBookmark"
    static let pathKey = "obsidianVaultPath"
    private static let mediaURLCache = NSCache<NSString, NSURL>()
    private static let mediaCacheLock = NSLock()
    private static let notesIndexLock = NSLock()
    private static var missingMediaURLCache: Set<String> = []
    private static var notesIndexCache: NotesIndexCache?
    private static let mediaImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    static var selectedVaultURL: URL? {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if let storedURL = selectedVaultURLFromStoredPath(clearMissing: false),
                   !sameFileURL(url, storedURL) {
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return storedURL
                }

                guard directoryExists(at: url, usingSecurityScope: true) else {
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return selectedVaultURLFromStoredPath()
                }

                if isStale {
                    saveVaultURL(url)
                }
                return url
            }
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }

        return selectedVaultURLFromStoredPath()
    }

    private static func selectedVaultURLFromStoredPath(clearMissing: Bool = true) -> URL? {
        if let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard directoryExists(at: url) else {
                if clearMissing {
                    clearStoredVaultSelection()
                }
                return nil
            }
            return url
        }

        return nil
    }

    static var selectedVaultName: String {
        selectedVaultURL?.lastPathComponent ?? ""
    }

    static var selectedVaultPath: String {
        selectedVaultURL?.path ?? ""
    }

    static var isVaultConfigured: Bool {
        selectedVaultURL != nil
    }

    static var canAccessSelectedVault: Bool {
        guard let vaultURL = selectedVaultURL else { return false }
        return directoryExists(at: vaultURL, usingSecurityScope: true)
    }

    static func saveVaultURL(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard directoryExists(at: url) else { return }

        var savedBookmarkData: Data?
        if !isRunningUnderXCTest,
           let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            savedBookmarkData = bookmarkData
        }
        UserDefaults.standard.set(url.path, forKey: pathKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "obsidianVault")
        AppConfigStore.saveVault(url: url, bookmarkData: savedBookmarkData)
        invalidateCaches()
        AppLogger.vault.info("Selected vault \(url.path, privacy: .public)")
    }

    @discardableResult
    static func sanitizePersistedVaultSelection() -> URL? {
        selectedVaultURL
    }

    static func directoryExists(at url: URL, usingSecurityScope: Bool = false) -> Bool {
        let didAccess = usingSecurityScope && url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func clearStoredVaultSelection() {
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")
        invalidateCaches()
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

    static func markdownNotes(matching query: String = "", limit: Int? = nil) -> [VaultNote] {
        guard let vaultURL = selectedVaultURL else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let notes = indexedMarkdownNotes(in: vaultURL)

        guard !normalizedQuery.isEmpty else {
            if let limit, limit >= 0, notes.count > limit {
                return Array(notes.prefix(limit))
            }
            return notes
        }

        return VaultNoteSearch.rankedNotes(notes, matching: query, limit: limit)
    }

    static func rebuildMarkdownIndex() {
        invalidateNotesIndex()
        _ = markdownNotes()
    }

    private static func indexedMarkdownNotes(in vaultURL: URL) -> [VaultNote] {
        let vaultPath = vaultURL.standardizedFileURL.path
        if let cachedIndex = cachedNotesIndex(for: vaultPath),
           cachedIndex.vaultPath == vaultPath,
           Date().timeIntervalSince(cachedIndex.createdAt) < 30 {
            return cachedIndex.notes
        }

        let startTime = CFAbsoluteTimeGetCurrent()
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

            let relativePath = vaultRelativePath(for: fileURL, in: vaultURL)
            let title = fileURL.deletingPathExtension().lastPathComponent
            notes.append(VaultNote(relativePath: relativePath, title: title, url: fileURL))
        }

        let sortedNotes = notes.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        setCachedNotesIndex(NotesIndexCache(vaultPath: vaultPath, createdAt: Date(), notes: sortedNotes))
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        AppLogger.vault.info("Indexed \(sortedNotes.count) markdown notes in \(elapsed, privacy: .public)s")
        return sortedNotes
    }

    static func read(_ note: VaultNote) -> String {
        (try? readNote(note)) ?? ""
    }

    static func readNote(_ note: VaultNote) throws -> String {
        let vaultURL = selectedVaultURL
        let didAccess = vaultURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                vaultURL?.stopAccessingSecurityScopedResource()
            }
        }

        return try String(contentsOf: note.url, encoding: .utf8)
    }

    static func write(_ text: String, to note: VaultNote) throws {
        let vaultURL = selectedVaultURL
        let didAccess = vaultURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                vaultURL?.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try text.write(to: note.url, atomically: true, encoding: .utf8)
        } catch {
            AppLogger.vault.error("Could not write note \(note.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        if let vaultURL {
            invalidateNotesIndex()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
        }
    }

    static func createOrUpdateNote(title: String, text: String, fallbackDate: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let rawTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = safeFileName(rawTitle.isEmpty ? defaultQuickNoteTitle(fallbackDate: fallbackDate) : rawTitle)
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let noteDirectoryURL = newNoteDirectoryURL(in: vaultURL)
            try FileManager.default.createDirectory(at: noteDirectoryURL, withIntermediateDirectories: true)
            let fileURL = uniqueNoteURL(in: noteDirectoryURL, filename: filename)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            invalidateNotesIndex()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultNote(for: fileURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func rename(_ note: VaultNote, toTitle title: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let filename = safeFileName(title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !filename.isEmpty, filename != note.title else { return note }

        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = uniqueNoteURL(in: note.url.deletingLastPathComponent(), filename: filename, excluding: note.url)
        do {
            try FileManager.default.moveItem(at: note.url, to: destinationURL)
            invalidateNotesIndex()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultNote(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func note(relativePath: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for candidatePath in relativePathCandidates(for: relativePath) {
            guard let fileURL = inVaultURL(forRelativePath: candidatePath, in: vaultURL),
                  isExistingMarkdownFile(at: fileURL) else {
                continue
            }

            return vaultNote(for: fileURL, in: vaultURL)
        }

        let candidateKeys = Set(relativePathCandidates(for: relativePath).map { comparableRelativePath($0) })
        return indexedMarkdownNotes(in: vaultURL)
            .first { candidateKeys.contains(comparableRelativePath($0.relativePath)) }
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
            invalidateMediaCaches()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultRelativePath(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func saveAttachmentImage(_ image: NSImage, suggestedName: String = pastedImageBaseName()) -> String? {
        guard let vaultURL = selectedVaultURL,
              let pngData = pngData(from: image) else {
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
            invalidateMediaCaches()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultRelativePath(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func saveAttachmentData(_ data: Data, suggestedName: String, fileExtension: String) -> String? {
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
                baseName: suggestedName,
                fileExtension: fileExtension
            )
            try data.write(to: destinationURL, options: .atomic)
            invalidateMediaCaches()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return vaultRelativePath(for: destinationURL, in: vaultURL)
        } catch {
            return nil
        }
    }

    static func pastedImageBaseName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd HHmmss"
        return "Pasted image \(formatter.string(from: now))"
    }

    static func url(forMarkdownLink link: String) -> URL? {
        if let url = URL(string: link), url.scheme != nil {
            return url
        }

        guard let vaultURL = selectedVaultURL else { return nil }
        let cleanedPath = link.removingPercentEncoding ?? link
        guard let directURL = inVaultURL(forRelativePath: cleanedPath, in: vaultURL) else {
            return nil
        }
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

    static func image(forMediaLink link: String, maxPixelWidth: CGFloat = 1600) -> NSImage? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let url = mediaFileURL(for: link, in: vaultURL, allowVaultScan: true), url.isFileURL else {
            return nil
        }

        let cacheKey = mediaImageCacheKey(for: url, maxPixelWidth: maxPixelWidth)
        if let cachedImage = mediaImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let image = downsampledImage(at: url, maxPixelWidth: maxPixelWidth)
            ?? NSImage(contentsOf: url) else {
            return nil
        }

        mediaImageCache.setObject(image, forKey: cacheKey, cost: imageCost(image))
        AppLogger.media.info("Loaded media image \(url.lastPathComponent, privacy: .public)")
        return image
    }

    static func cachedImage(forMediaLink link: String, maxPixelWidth: CGFloat = 1600) -> NSImage? {
        guard let vaultURL = selectedVaultURL else { return nil }
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let url = mediaFileURL(for: link, in: vaultURL, allowVaultScan: false), url.isFileURL else {
            return nil
        }

        return mediaImageCache.object(forKey: mediaImageCacheKey(for: url, maxPixelWidth: maxPixelWidth))
    }

    static func withSelectedVaultAccess<T>(_ operation: () -> T) -> T {
        guard let vaultURL = selectedVaultURL else {
            return operation()
        }

        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        return operation()
    }

    static func dailyNoteForToday(now: Date = Date()) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return withSelectedVaultAccess {
            let relativePath = dailyNoteRelativePath(now: now, in: vaultURL)
            let note = vaultNote(relativePath: relativePath, in: vaultURL)
            guard FileManager.default.fileExists(atPath: note?.url.path ?? "") else { return nil }
            return note
        }
    }

    static func ensureDailyNoteForToday(now: Date = Date()) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return withSelectedVaultAccess {
            let relativePath = dailyNoteRelativePath(now: now, in: vaultURL)
            guard let note = vaultNote(relativePath: relativePath, in: vaultURL) else { return nil }
            let fileURL = note.url

            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                return note
            }

            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try dailyTemplateText(in: vaultURL).write(to: fileURL, atomically: true, encoding: .utf8)
                invalidateNotesIndex()
                NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
                return note
            } catch {
                return nil
            }
        }
    }

    private static func safeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    static func defaultQuickNoteTitle(fallbackDate: String) -> String {
        "QuickNote \(fallbackDate)"
    }

    private static func newNoteDirectoryURL(in vaultURL: URL) -> URL {
        if !NewNotePreferences.useObsidianNewNoteFolder {
            return inVaultURL(
                forRelativePath: NewNotePreferences.folderPath,
                in: vaultURL,
                isDirectory: true,
                allowEmpty: true
            ) ?? vaultURL
        }

        let settings = appSettings(in: vaultURL)
        guard settings.newFileLocation == "folder",
              let folderPath = settings.newFileFolderPath,
              !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return vaultURL
        }

        return inVaultURL(forRelativePath: folderPath, in: vaultURL, isDirectory: true, allowEmpty: true) ?? vaultURL
    }

    private static func pngData(from image: NSImage) -> Data? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = image.size
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func attachmentDirectoryURL(in vaultURL: URL) -> URL {
        guard let configuredPath = attachmentFolderPath(in: vaultURL), !configuredPath.isEmpty else {
            return vaultURL
        }

        return inVaultURL(forRelativePath: configuredPath, in: vaultURL, isDirectory: true, allowEmpty: true) ?? vaultURL
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

    private static func appSettings(in vaultURL: URL) -> ObsidianAppSettings {
        let configURL = vaultURL.appendingPathComponent(".obsidian/app.json")
        guard let data = try? Data(contentsOf: configURL),
              let settings = try? JSONDecoder().decode(ObsidianAppSettings.self, from: data) else {
            return ObsidianAppSettings()
        }

        return settings
    }

    private static func dailyNoteRelativePath(now: Date, in vaultURL: URL) -> String {
        let settings = dailyNoteSettings(in: vaultURL)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = swiftDateFormat(fromObsidianFormat: settings.format)

        let fileName = formatter.string(from: now)
        let folder = safeVaultRelativePath(settings.folder, allowEmpty: true) ?? ""
        let path = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        let markdownPath = path.hasSuffix(".md") ? path : "\(path).md"
        return safeVaultRelativePath(markdownPath) ?? defaultDailyNoteRelativePath(now: now)
    }

    private static func dailyTemplateText(in vaultURL: URL) -> String {
        let template = dailyNoteSettings(in: vaultURL).template
        guard !template.isEmpty else { return "" }

        let templatePath = URL(fileURLWithPath: template).pathExtension.isEmpty ? "\(template).md" : template
        guard let templateURL = inVaultURL(forRelativePath: templatePath, in: vaultURL) else { return "" }
        return (try? String(contentsOf: templateURL, encoding: .utf8)) ?? ""
    }

    private static func defaultDailyNoteRelativePath(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: now)).md"
    }

    private static func dailyNoteSettings(in vaultURL: URL) -> DailyNoteSettings {
        let configURL = vaultURL.appendingPathComponent(".obsidian/daily-notes.json")
        guard let data = try? Data(contentsOf: configURL),
              let settings = try? JSONDecoder().decode(DailyNoteSettings.self, from: data) else {
            return DailyNoteSettings()
        }

        return settings
    }

    private static func swiftDateFormat(fromObsidianFormat format: String) -> String {
        let replacements: [String: String] = [
            "YYYY": "yyyy",
            "YY": "yy",
            "MMMM": "MMMM",
            "MMM": "MMM",
            "MM": "MM",
            "M": "M",
            "DD": "dd",
            "D": "d",
            "dddd": "EEEE",
            "ddd": "EEE",
            "dd": "EE",
            "d": "e",
            "HH": "HH",
            "H": "H",
            "hh": "hh",
            "h": "h",
            "mm": "mm",
            "m": "m",
            "ss": "ss",
            "s": "s"
        ]
        let tokens = replacements.keys.sorted { $0.count > $1.count }
        var result = ""
        var index = format.startIndex

        while index < format.endIndex {
            if let token = tokens.first(where: { format[index...].hasPrefix($0) }) {
                result += replacements[token] ?? token
                index = format.index(index, offsetBy: token.count)
            } else {
                result.append(format[index])
                index = format.index(after: index)
            }
        }

        return result.isEmpty ? "yyyy-MM-dd" : result
    }

    private static func vaultRelativePath(for fileURL: URL, in vaultURL: URL) -> String {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(vaultPath.count + 1))
    }

    private static func vaultNote(for fileURL: URL, in vaultURL: URL) -> VaultNote {
        let relativePath = vaultRelativePath(for: fileURL, in: vaultURL)
        let title = fileURL.deletingPathExtension().lastPathComponent
        return VaultNote(relativePath: relativePath, title: title, url: fileURL)
    }

    private static func vaultNote(relativePath: String, in vaultURL: URL) -> VaultNote? {
        guard let fileURL = inVaultURL(forRelativePath: relativePath, in: vaultURL),
              let safeRelativePath = safeVaultRelativePath(relativePath) else {
            return nil
        }

        let title = fileURL.deletingPathExtension().lastPathComponent
        return VaultNote(relativePath: safeRelativePath, title: title, url: fileURL)
    }

    private static func isExistingMarkdownFile(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "md" else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func relativePathCandidates(for path: String) -> [String] {
        var candidates: [String] = []

        func appendCandidate(_ candidate: String) {
            guard let safePath = safeVaultRelativePath(candidate),
                  !candidates.contains(safePath) else {
                return
            }
            candidates.append(safePath)
        }

        let decodedPath = path.removingPercentEncoding ?? path
        for basePath in [decodedPath, repairingLiteralUnicodeEscapes(in: decodedPath)] {
            appendCandidate(basePath)
            appendCandidate(basePath.precomposedStringWithCanonicalMapping)
            appendCandidate(basePath.decomposedStringWithCanonicalMapping)
        }

        return candidates
    }

    private static func comparableRelativePath(_ path: String) -> String {
        path.decomposedStringWithCanonicalMapping.lowercased()
    }

    private static func repairingLiteralUnicodeEscapes(in text: String) -> String {
        var repaired = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let parsedScalar = parseUnicodeEscape(in: text, from: index) {
                repaired.append(String(parsedScalar.scalar))
                index = parsedScalar.nextIndex
                continue
            }

            repaired.append(text[index])
            index = text.index(after: index)
        }

        return repaired
    }

    private static func parseUnicodeEscape(in text: String, from index: String.Index) -> (scalar: UnicodeScalar, nextIndex: String.Index)? {
        let character = text[index]

        if character == "\\" {
            let uIndex = text.index(after: index)
            guard uIndex < text.endIndex else { return nil }

            switch text[uIndex] {
            case "u":
                return parseUnicodeScalar(in: text, from: text.index(after: uIndex), digitCount: 4)
            case "U":
                return parseUnicodeScalar(in: text, from: text.index(after: uIndex), digitCount: 8)
            default:
                return nil
            }
        }

        guard character == "u",
              let parsed = parseUnicodeScalar(in: text, from: text.index(after: index), digitCount: 4),
              (0x0300...0x036F).contains(parsed.scalar.value) else {
            return nil
        }

        return parsed
    }

    private static func parseUnicodeScalar(in text: String, from startIndex: String.Index, digitCount: Int) -> (scalar: UnicodeScalar, nextIndex: String.Index)? {
        var index = startIndex
        var hex = ""

        for _ in 0..<digitCount {
            guard index < text.endIndex, text[index].isHexDigit else { return nil }
            hex.append(text[index])
            index = text.index(after: index)
        }

        guard let value = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(value) else {
            return nil
        }

        return (scalar, index)
    }

    private static func inVaultURL(
        forRelativePath path: String,
        in vaultURL: URL,
        isDirectory: Bool = false,
        allowEmpty: Bool = false
    ) -> URL? {
        guard let relativePath = safeVaultRelativePath(path, allowEmpty: allowEmpty) else {
            return nil
        }

        guard !relativePath.isEmpty else {
            return vaultURL
        }

        let candidate = vaultURL
            .appendingPathComponent(relativePath, isDirectory: isDirectory)
            .standardizedFileURL
        return isURLInsideVault(candidate, vaultURL: vaultURL) ? candidate : nil
    }

    private static func safeVaultRelativePath(_ path: String, allowEmpty: Bool = false) -> String? {
        let normalized = path
            .removingPercentEncoding ?? path
        let trimmed = normalized
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.hasPrefix("/") else { return nil }

        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if component.isEmpty || component == "." {
                continue
            }

            guard component != ".." else {
                return nil
            }

            components.append(component)
        }

        let relativePath = components.joined(separator: "/")
        guard allowEmpty || !relativePath.isEmpty else {
            return nil
        }

        return relativePath
    }

    private static func isURLInsideVault(_ url: URL, vaultURL: URL) -> Bool {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == vaultPath || filePath.hasPrefix(vaultPath + "/")
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

    private static func mediaFileURL(for link: String, in vaultURL: URL, allowVaultScan: Bool) -> URL? {
        let cacheKeyString = "\(vaultURL.standardizedFileURL.path)|\(link)"
        let cacheKey = cacheKeyString as NSString

        mediaCacheLock.lock()
        let cachedURL = mediaURLCache.object(forKey: cacheKey)
        let isKnownMissing = missingMediaURLCache.contains(cacheKeyString)
        mediaCacheLock.unlock()

        if let cachedURL {
            return cachedURL as URL
        }
        if isKnownMissing {
            return nil
        }

        guard let url = resolvedMediaFileURL(for: link, in: vaultURL, allowVaultScan: allowVaultScan), url.isFileURL else {
            if allowVaultScan {
                mediaCacheLock.lock()
                missingMediaURLCache.insert(cacheKeyString)
                mediaCacheLock.unlock()
            }
            return nil
        }

        mediaCacheLock.lock()
        mediaURLCache.setObject(url as NSURL, forKey: cacheKey)
        mediaCacheLock.unlock()
        return url
    }

    private static func resolvedMediaFileURL(for link: String, in vaultURL: URL, allowVaultScan: Bool) -> URL? {
        if let url = URL(string: link), url.scheme != nil {
            return url
        }

        let rawTarget = wikiTarget(from: link)
        let decodedTarget = (rawTarget.removingPercentEncoding ?? rawTarget)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedTarget.isEmpty else { return nil }

        guard let directURL = inVaultURL(forRelativePath: decodedTarget, in: vaultURL) else {
            return nil
        }
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        guard allowVaultScan else {
            return nil
        }

        if let foundURL = findVaultFile(named: decodedTarget, in: vaultURL) {
            return foundURL
        }

        guard URL(fileURLWithPath: decodedTarget).pathExtension.isEmpty else {
            return nil
        }

        return findVaultFile(named: "\(decodedTarget).md", in: vaultURL)
    }

    private static func mediaImageCacheKey(for url: URL, maxPixelWidth: CGFloat) -> NSString {
        let modificationTime = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0)
        return "\(url.path)|\(Int(maxPixelWidth.rounded(.up)))|\(modificationTime)" as NSString
    }

    private static func downsampledImage(at url: URL, maxPixelWidth: CGFloat) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(80, Int(maxPixelWidth.rounded(.up)))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func imageCost(_ image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    private static func invalidateCaches() {
        invalidateNotesIndex()
        invalidateMediaCaches()
    }

    private static func invalidateNotesIndex() {
        notesIndexLock.lock()
        notesIndexCache = nil
        notesIndexLock.unlock()
    }

    private static func cachedNotesIndex(for vaultPath: String) -> NotesIndexCache? {
        notesIndexLock.lock()
        defer { notesIndexLock.unlock() }
        guard notesIndexCache?.vaultPath == vaultPath else {
            return nil
        }
        return notesIndexCache
    }

    private static func setCachedNotesIndex(_ index: NotesIndexCache) {
        notesIndexLock.lock()
        notesIndexCache = index
        notesIndexLock.unlock()
    }

    private static func invalidateMediaCaches() {
        mediaCacheLock.lock()
        mediaURLCache.removeAllObjects()
        missingMediaURLCache.removeAll()
        mediaCacheLock.unlock()
        mediaImageCache.removeAllObjects()
    }

    private struct NotesIndexCache {
        let vaultPath: String
        let createdAt: Date
        let notes: [VaultNote]
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

    private static func uniqueNoteURL(in directoryURL: URL, filename: String, excluding excludedURL: URL? = nil) -> URL {
        var candidate = directoryURL
            .appendingPathComponent(filename)
            .appendingPathExtension("md")
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path),
              candidate.standardizedFileURL != excludedURL?.standardizedFileURL {
            candidate = directoryURL
                .appendingPathComponent("\(filename) \(index)")
                .appendingPathExtension("md")
            index += 1
        }

        return candidate
    }
}

private struct ObsidianAppSettings: Decodable {
    var newFileLocation: String = ""
    var newFileFolderPath: String?

    enum CodingKeys: String, CodingKey {
        case newFileLocation
        case newFileFolderPath
    }

    init() {}
}

private struct DailyNoteSettings: Decodable {
    var folder: String = ""
    var template: String = ""
    var format: String = "YYYY-MM-DD"

    enum CodingKeys: String, CodingKey {
        case folder
        case template
        case format
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "YYYY-MM-DD"
    }
}
