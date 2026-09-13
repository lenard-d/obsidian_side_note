import AppKit
import Foundation

struct VaultStore {
    static let bookmarkKey = VaultSelectionStore.bookmarkKey
    static let pathKey = VaultSelectionStore.pathKey
    private static let notesIndexLock = NSLock()
    private static var notesIndexCache: NotesIndexCache?

    static var selectedVaultURL: URL? {
        VaultSelectionStore.selectedURL
    }

    static var selectedVaultName: String {
        VaultSelectionStore.selectedName
    }

    static var selectedVaultPath: String {
        VaultSelectionStore.selectedPath
    }

    static var isVaultConfigured: Bool {
        selectedVaultURL != nil
    }

    static var canAccessSelectedVault: Bool {
        VaultSelectionStore.canAccessSelectedVault
    }

    static func saveVaultURL(_ url: URL) {
        guard let result = VaultSelectionStore.save(url) else { return }
        AppConfigStore.saveVault(url: url, bookmarkData: result.bookmarkData)
        invalidateCaches()
        AppLogger.vault.info("Selected vault")
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

            let relativePath = VaultPathResolver.relativePath(for: fileURL, in: vaultURL)
            let title = fileURL.deletingPathExtension().lastPathComponent
            notes.append(VaultNote(relativePath: relativePath, title: title, url: fileURL))
        }

        let sortedNotes = notes.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        setCachedNotesIndex(NotesIndexCache(vaultPath: vaultPath, createdAt: Date(), notes: sortedNotes))
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        AppLogger.vault.info("Indexed \(sortedNotes.count) markdown notes in \(elapsed)s")
        return sortedNotes
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
            AppLogger.vault.error("Could not write note: \(AppLogger.errorSummary(error))")
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
            return VaultPathResolver.note(for: fileURL, in: vaultURL)
        } catch {
            AppLogger.vault.error("Could not create note: \(AppLogger.errorSummary(error))")
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
            return VaultPathResolver.note(for: destinationURL, in: vaultURL)
        } catch {
            AppLogger.vault.error("Could not rename note: \(AppLogger.errorSummary(error))")
            return nil
        }
    }

    static func note(relativePath: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for candidatePath in VaultPathResolver.candidates(for: relativePath) {
            guard let fileURL = VaultPathResolver.url(forRelativePath: candidatePath, in: vaultURL),
                  isExistingMarkdownFile(at: fileURL) else {
                continue
            }

            return VaultPathResolver.note(for: fileURL, in: vaultURL)
        }

        let candidateKeys = Set(VaultPathResolver.candidates(for: relativePath).map { VaultPathResolver.comparableRelativePath($0) })
        return indexedMarkdownNotes(in: vaultURL)
            .first { candidateKeys.contains(VaultPathResolver.comparableRelativePath($0.relativePath)) }
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
            VaultMediaStore.invalidate()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return VaultPathResolver.relativePath(for: destinationURL, in: vaultURL)
        } catch {
            AppLogger.media.error("Could not copy attachment: \(AppLogger.errorSummary(error))")
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
            VaultMediaStore.invalidate()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return VaultPathResolver.relativePath(for: destinationURL, in: vaultURL)
        } catch {
            AppLogger.media.error("Could not save pasted image: \(AppLogger.errorSummary(error))")
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
            VaultMediaStore.invalidate()
            NSWorkspace.shared.noteFileSystemChanged(vaultURL.path)
            return VaultPathResolver.relativePath(for: destinationURL, in: vaultURL)
        } catch {
            AppLogger.media.error("Could not save attachment data: \(AppLogger.errorSummary(error))")
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
        guard let vaultURL = selectedVaultURL else { return nil }
        return VaultMediaStore.url(forMarkdownLink: link, in: vaultURL)
    }

    static func url(forWikiLink link: String) -> URL? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return VaultMediaStore.url(forWikiLink: link, in: vaultURL)
    }

    static func note(forWikiLink link: String) -> VaultNote? {
        guard let vaultURL = selectedVaultURL,
              let fileURL = VaultMediaStore.url(forWikiLink: link, in: vaultURL),
              fileURL.pathExtension.lowercased() == "md",
              isExistingMarkdownFile(at: fileURL) else {
            return nil
        }
        return VaultPathResolver.note(for: fileURL, in: vaultURL)
    }

    static func note(forMarkdownLink link: String) -> VaultNote? {
        let withoutFragment = link.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? link
        let target = withoutFragment.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? withoutFragment

        guard let vaultURL = selectedVaultURL,
              let fileURL = VaultMediaStore.url(forMarkdownLink: target, in: vaultURL),
              fileURL.pathExtension.lowercased() == "md",
              isExistingMarkdownFile(at: fileURL) else {
            return nil
        }
        return VaultPathResolver.note(for: fileURL, in: vaultURL)
    }

    static func image(forMediaLink link: String, maxPixelWidth: CGFloat = 1600) -> NSImage? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return VaultMediaStore.image(for: link, in: vaultURL, maxPixelWidth: maxPixelWidth)
    }

    static func cachedImage(forMediaLink link: String, maxPixelWidth: CGFloat = 1600) -> NSImage? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return VaultMediaStore.cachedImage(for: link, in: vaultURL, maxPixelWidth: maxPixelWidth)
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

    static func ensureDailyNoteForToday(now: Date = Date()) -> VaultNote? {
        guard let vaultURL = selectedVaultURL else { return nil }
        return withSelectedVaultAccess {
            let relativePath = dailyNoteRelativePath(now: now, in: vaultURL)
            guard let note = VaultPathResolver.note(relativePath: relativePath, in: vaultURL) else { return nil }
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
                AppLogger.vault.error("Could not create daily note: \(AppLogger.errorSummary(error))")
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
            return VaultPathResolver.url(
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

        return VaultPathResolver.url(forRelativePath: folderPath, in: vaultURL, isDirectory: true, allowEmpty: true) ?? vaultURL
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

        return VaultPathResolver.url(forRelativePath: configuredPath, in: vaultURL, isDirectory: true, allowEmpty: true) ?? vaultURL
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
        let canonicalFileName = ObsidianDailyNoteDateFormatter.string(
            from: now,
            format: settings.format,
            localeIdentifier: settings.localeIdentifier
        )
        let canonicalPath = dailyNotePath(fileName: canonicalFileName, folder: settings.folder)
            ?? defaultDailyNoteRelativePath(now: now)

        for candidatePath in dailyNoteCompatibilityPaths(
            now: now,
            settings: settings,
            canonicalPath: canonicalPath
        ) where FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent(candidatePath).path
        ) {
            return candidatePath
        }

        return canonicalPath
    }

    private static func dailyTemplateText(in vaultURL: URL) -> String {
        let template = dailyNoteSettings(in: vaultURL).template
        guard !template.isEmpty else { return "" }

        let templatePath = URL(fileURLWithPath: template).pathExtension.isEmpty ? "\(template).md" : template
        guard let templateURL = VaultPathResolver.url(forRelativePath: templatePath, in: vaultURL) else { return "" }
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
        let periodicConfigURL = vaultURL.appendingPathComponent(".obsidian/plugins/periodic-notes/data.json")
        if communityPluginIsEnabled("periodic-notes", in: vaultURL),
           let data = try? Data(contentsOf: periodicConfigURL),
           let periodicSettings = try? JSONDecoder().decode(PeriodicNotesSettings.self, from: data),
           let settings = periodicSettings.activeDailyNoteSettings {
            return settings
        }

        let configURL = vaultURL.appendingPathComponent(".obsidian/daily-notes.json")
        guard let data = try? Data(contentsOf: configURL),
              let settings = try? JSONDecoder().decode(DailyNoteSettings.self, from: data) else {
            return DailyNoteSettings()
        }

        return settings
    }

    private static func communityPluginIsEnabled(_ pluginID: String, in vaultURL: URL) -> Bool {
        let configURL = vaultURL.appendingPathComponent(".obsidian/community-plugins.json")
        guard let data = try? Data(contentsOf: configURL),
              let pluginIDs = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }
        return pluginIDs.contains(pluginID)
    }

    private static func dailyNotePath(fileName: String, folder: String) -> String? {
        let safeFolder = VaultPathResolver.safeRelativePath(folder, allowEmpty: true) ?? ""
        let path = safeFolder.isEmpty ? fileName : "\(safeFolder)/\(fileName)"
        let markdownPath = path.hasSuffix(".md") ? path : "\(path).md"
        return VaultPathResolver.safeRelativePath(markdownPath)
    }

    private static func dailyNoteCompatibilityPaths(
        now: Date,
        settings: DailyNoteSettings,
        canonicalPath: String
    ) -> [String] {
        var paths = [canonicalPath]
        let localeIdentifiers = [
            settings.localeIdentifier,
            systemLocaleIdentifier(),
            Locale.current.identifier,
            "de",
            "en"
        ]

        for localeIdentifier in localeIdentifiers where !localeIdentifier.isEmpty {
            let momentFileName = ObsidianDailyNoteDateFormatter.string(
                from: now,
                format: settings.format,
                localeIdentifier: localeIdentifier
            )
            if let momentPath = dailyNotePath(fileName: momentFileName, folder: settings.folder) {
                paths.append(momentPath)
            }

            let legacyFileName = LegacyDailyNoteDateFormatter.string(
                from: now,
                format: settings.format,
                localeIdentifier: localeIdentifier
            )
            if let legacyPath = dailyNotePath(fileName: legacyFileName, folder: settings.folder) {
                paths.append(legacyPath)
            }
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private static func systemLocaleIdentifier() -> String {
        if let appleLocale = UserDefaults.standard.string(forKey: "AppleLocale"), !appleLocale.isEmpty {
            return appleLocale
        }
        return Locale.current.identifier
    }

    private static func isExistingMarkdownFile(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "md" else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func invalidateCaches() {
        invalidateNotesIndex()
        VaultMediaStore.invalidate()
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
    var localeIdentifier: String = "system-default"

    enum CodingKeys: String, CodingKey {
        case folder
        case template
        case format
    }

    init() {}

    init(folder: String, template: String, format: String, localeIdentifier: String) {
        self.folder = folder
        self.template = template
        self.format = format
        self.localeIdentifier = localeIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "YYYY-MM-DD"
    }
}

private struct PeriodicNotesSettings: Decodable {
    var activeCalendarSet: String?
    var calendarSets: [PeriodicCalendarSet] = []
    var localeOverride: String = "system-default"
    var daily: PeriodicDaySettings?

    var activeDailyNoteSettings: DailyNoteSettings? {
        let calendarSet = calendarSets.first { $0.id == activeCalendarSet } ?? calendarSets.first
        if let day = calendarSet?.day, day.enabled == true {
            return day.dailyNoteSettings(localeIdentifier: localeOverride)
        }
        if let daily, daily.enabled == true {
            return daily.dailyNoteSettings(localeIdentifier: localeOverride)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case activeCalendarSet
        case calendarSets
        case localeOverride
        case daily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeCalendarSet = try container.decodeIfPresent(String.self, forKey: .activeCalendarSet)
        calendarSets = try container.decodeIfPresent([PeriodicCalendarSet].self, forKey: .calendarSets) ?? []
        localeOverride = try container.decodeIfPresent(String.self, forKey: .localeOverride) ?? "system-default"
        daily = try container.decodeIfPresent(PeriodicDaySettings.self, forKey: .daily)
    }
}

private struct PeriodicCalendarSet: Decodable {
    var id: String
    var day: PeriodicDaySettings?
}

private struct PeriodicDaySettings: Decodable {
    var enabled: Bool?
    var format: String?
    var folder: String?
    var templatePath: String?
    var template: String?

    func dailyNoteSettings(localeIdentifier: String) -> DailyNoteSettings {
        DailyNoteSettings(
            folder: folder ?? "",
            template: templatePath ?? template ?? "",
            format: format?.isEmpty == false ? format ?? "YYYY-MM-DD" : "YYYY-MM-DD",
            localeIdentifier: localeIdentifier
        )
    }
}

private enum DailyNoteLocaleResolver {
    static func locale(identifier: String) -> Locale {
        guard !identifier.isEmpty, identifier != "system-default" else {
            if let appleLocale = UserDefaults.standard.string(forKey: "AppleLocale"), !appleLocale.isEmpty {
                return Locale(identifier: appleLocale)
            }
            return .current
        }
        return Locale(identifier: identifier)
    }
}

private enum ObsidianDailyNoteDateFormatter {
    private static let tokenPatterns: [String: String] = [
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
        "HH": "HH",
        "H": "H",
        "hh": "hh",
        "h": "h",
        "mm": "mm",
        "m": "m",
        "ss": "ss",
        "s": "s"
    ]
    private static let tokens = (Array(tokenPatterns.keys) + ["dd", "d"])
        .sorted { $0.count > $1.count }

    static func string(from date: Date, format: String, localeIdentifier: String) -> String {
        let momentFormat = format.isEmpty ? "YYYY-MM-DD" : format
        let locale = DailyNoteLocaleResolver.locale(identifier: localeIdentifier)
        var output = ""
        var index = momentFormat.startIndex

        while index < momentFormat.endIndex {
            if momentFormat[index] == "[",
               let closingBracket = momentFormat[index...].firstIndex(of: "]") {
                let literalStart = momentFormat.index(after: index)
                output += momentFormat[literalStart..<closingBracket]
                index = momentFormat.index(after: closingBracket)
                continue
            }

            if momentFormat[index] == "\\" {
                let nextIndex = momentFormat.index(after: index)
                if nextIndex < momentFormat.endIndex {
                    output.append(momentFormat[nextIndex])
                    index = momentFormat.index(after: nextIndex)
                    continue
                }
            }

            if let token = tokens.first(where: { momentFormat[index...].hasPrefix($0) }) {
                output += render(token: token, date: date, locale: locale)
                index = momentFormat.index(index, offsetBy: token.count)
            } else {
                output.append(momentFormat[index])
                index = momentFormat.index(after: index)
            }
        }

        return output
    }

    private static func render(token: String, date: Date, locale: Locale) -> String {
        switch token {
        case "dd":
            return weekdayMinimumSymbol(for: date, locale: locale)
        case "d":
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            calendar.timeZone = .current
            return String(calendar.component(.weekday, from: date) - 1)
        default:
            guard let pattern = tokenPatterns[token] else { return token }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = .current
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
    }

    private static func weekdayMinimumSymbol(for date: Date, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = .current
        let weekdayIndex = calendar.component(.weekday, from: date) - 1

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        let shortSymbols = formatter.shortWeekdaySymbols ?? calendar.shortWeekdaySymbols
        guard shortSymbols.indices.contains(weekdayIndex) else { return "" }

        let symbol = shortSymbols[weekdayIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return String(symbol.prefix(2))
    }
}

private enum LegacyDailyNoteDateFormatter {
    private static let replacements: [String: String] = [
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

    static func string(from date: Date, format: String, localeIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = DailyNoteLocaleResolver.locale(identifier: localeIdentifier)
        formatter.timeZone = .current
        formatter.dateFormat = swiftFormat(from: format)
        return formatter.string(from: date)
    }

    private static func swiftFormat(from format: String) -> String {
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
}
