import Foundation

/// Owns all normalization and containment rules for paths inside a vault.
/// Keeping this logic separate makes the filesystem boundary explicit and
/// prevents callers from constructing unchecked vault URLs.
enum VaultPathResolver {
    static func relativePath(for fileURL: URL, in vaultURL: URL) -> String {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(vaultPath.count + 1))
    }

    static func note(for fileURL: URL, in vaultURL: URL) -> VaultNote {
        let relativePath = relativePath(for: fileURL, in: vaultURL)
        let title = fileURL.deletingPathExtension().lastPathComponent
        return VaultNote(relativePath: relativePath, title: title, url: fileURL)
    }

    static func note(relativePath: String, in vaultURL: URL) -> VaultNote? {
        guard let fileURL = url(forRelativePath: relativePath, in: vaultURL),
              let safeRelativePath = safeRelativePath(relativePath) else {
            return nil
        }

        let title = fileURL.deletingPathExtension().lastPathComponent
        return VaultNote(relativePath: safeRelativePath, title: title, url: fileURL)
    }

    static func candidates(for path: String) -> [String] {
        var candidates: [String] = []

        func appendCandidate(_ candidate: String) {
            guard let safePath = safeRelativePath(candidate),
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

    static func comparableRelativePath(_ path: String) -> String {
        path.decomposedStringWithCanonicalMapping.lowercased()
    }

    static func url(
        forRelativePath path: String,
        in vaultURL: URL,
        isDirectory: Bool = false,
        allowEmpty: Bool = false
    ) -> URL? {
        guard let relativePath = safeRelativePath(path, allowEmpty: allowEmpty) else {
            return nil
        }

        guard !relativePath.isEmpty else {
            return vaultURL
        }

        let candidate = vaultURL
            .appendingPathComponent(relativePath, isDirectory: isDirectory)
            .standardizedFileURL
        return isInsideVault(candidate, vaultURL: vaultURL) ? candidate : nil
    }

    static func safeRelativePath(_ path: String, allowEmpty: Bool = false) -> String? {
        let normalized = path.removingPercentEncoding ?? path
        let trimmed = normalized
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.hasPrefix("/") else { return nil }

        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if component.isEmpty || component == "." {
                continue
            }
            guard component != ".." else { return nil }
            components.append(component)
        }

        let relativePath = components.joined(separator: "/")
        guard allowEmpty || !relativePath.isEmpty else { return nil }
        return relativePath
    }

    private static func isInsideVault(_ url: URL, vaultURL: URL) -> Bool {
        let vaultPath = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath == vaultPath || filePath.hasPrefix(vaultPath + "/")
    }

    private static func repairingLiteralUnicodeEscapes(in text: String) -> String {
        var repaired = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let parsedScalar = parseUnicodeEscape(in: text, from: index) {
                repaired.append(String(parsedScalar.scalar))
                index = parsedScalar.nextIndex
            } else {
                repaired.append(text[index])
                index = text.index(after: index)
            }
        }

        return repaired
    }

    private static func parseUnicodeEscape(
        in text: String,
        from index: String.Index
    ) -> (scalar: UnicodeScalar, nextIndex: String.Index)? {
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

    private static func parseUnicodeScalar(
        in text: String,
        from startIndex: String.Index,
        digitCount: Int
    ) -> (scalar: UnicodeScalar, nextIndex: String.Index)? {
        var index = startIndex
        var hex = ""
        for _ in 0..<digitCount {
            guard index < text.endIndex, text[index].isHexDigit else { return nil }
            hex.append(text[index])
            index = text.index(after: index)
        }

        guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else { return nil }
        return (scalar, index)
    }
}
