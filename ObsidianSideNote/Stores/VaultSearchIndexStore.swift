import Foundation

/// Shares one prepared index between search and note-link resolution. Disk scans run outside the lock.
nonisolated enum VaultSearchIndexStore {
    struct Index: Sendable {
        let vaultPath: String
        let createdAt: Date
        let notes: [VaultNote]
        let search: VaultNoteSearch
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Index?
    nonisolated(unsafe) private static var generation = 0

    static func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        generation += 1
    }

    static func index(in vaultURL: URL) -> Index {
        let vaultPath = vaultURL.standardizedFileURL.path
        lock.lock()
        let cachedIndex = cached
        let currentGeneration = generation
        lock.unlock()
        if let cachedIndex, cachedIndex.vaultPath == vaultPath,
           Date().timeIntervalSince(cachedIndex.createdAt) < 30 {
            return cachedIndex
        }

        let result = scan(vaultURL)
        lock.lock()
        if generation == currentGeneration { cached = result }
        lock.unlock()
        return result
    }

    private static func scan(_ vaultURL: URL) -> Index {
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer { if didAccess { vaultURL.stopAccessingSecurityScopedResource() } }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(at: vaultURL,
            includingPropertiesForKeys: Array(resourceKeys), options: [.skipsPackageDescendants])
        var notes: [VaultNote] = []
        var folders: [VaultNote] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathComponents.contains(".obsidian") || fileURL.pathComponents.contains(".trash") {
                enumerator?.skipDescendants()
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }
            let relativePath = VaultPathResolver.relativePath(for: fileURL, in: vaultURL)
            if values.isDirectory == true {
                folders.append(VaultNote(relativePath: relativePath, title: fileURL.lastPathComponent, url: fileURL))
            } else if values.isRegularFile == true, fileURL.pathExtension.lowercased() == "md" {
                notes.append(VaultNote(relativePath: relativePath, title: fileURL.deletingPathExtension().lastPathComponent, url: fileURL))
            }
        }
        notes.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return Index(vaultPath: vaultURL.standardizedFileURL.path, createdAt: Date(), notes: notes,
                     search: VaultNoteSearch(notes: notes, folders: folders))
    }
}
