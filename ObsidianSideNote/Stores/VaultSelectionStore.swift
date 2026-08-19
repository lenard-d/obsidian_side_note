import Foundation

/// Lowest-level persistence boundary for the selected vault. It deliberately
/// knows nothing about AppConfigStore, preventing the former store cycle.
enum VaultSelectionStore {
    static let bookmarkKey = "obsidianVaultBookmark"
    static let pathKey = "obsidianVaultPath"

    struct SaveResult {
        let bookmarkData: Data?
    }

    static var selectedURL: URL? {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if let storedURL = selectedURLFromStoredPath(clearMissing: false),
                   !sameFileURL(url, storedURL) {
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return storedURL
                }

                guard directoryExists(at: url, usingSecurityScope: true) else {
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return selectedURLFromStoredPath()
                }

                if isStale {
                    _ = save(url)
                }
                return url
            }
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }

        return selectedURLFromStoredPath()
    }

    static var selectedName: String {
        selectedURL?.lastPathComponent ?? ""
    }

    static var selectedPath: String {
        selectedURL?.path ?? ""
    }

    static var canAccessSelectedVault: Bool {
        guard let vaultURL = selectedURL else { return false }
        return directoryExists(at: vaultURL, usingSecurityScope: true)
    }

    static func save(_ url: URL) -> SaveResult? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard directoryExists(at: url) else { return nil }

        var savedBookmarkData: Data?
        if !isRunningUnderXCTest,
           let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ) {
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            savedBookmarkData = bookmarkData
        }
        UserDefaults.standard.set(url.path, forKey: pathKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "obsidianVault")
        return SaveResult(bookmarkData: savedBookmarkData)
    }

    @discardableResult
    static func sanitizePersistedSelection() -> URL? {
        selectedURL
    }

    static func directoryExists(at url: URL, usingSecurityScope: Bool = false) -> Bool {
        let didAccess = usingSecurityScope && url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func selectedURLFromStoredPath(clearMissing: Bool = true) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard directoryExists(at: url) else {
            if clearMissing { clearStoredSelection() }
            return nil
        }
        return url
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func clearStoredSelection() {
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")
    }
}
