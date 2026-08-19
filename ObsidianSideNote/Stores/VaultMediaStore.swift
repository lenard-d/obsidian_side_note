import AppKit
import Foundation
import ImageIO

/// Resolves and caches media links for one selected vault. VaultStore keeps the
/// public facade; this type owns the expensive scan/downsample/cache behavior.
enum VaultMediaStore {
    private static let mediaURLCache = NSCache<NSString, NSURL>()
    private static let mediaCacheLock = NSLock()
    private static var missingMediaURLCache: Set<String> = []
    private static let mediaImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    static func url(forMarkdownLink link: String, in vaultURL: URL) -> URL? {
        if let url = URL(string: link), url.scheme != nil {
            return url
        }

        let cleanedPath = link.removingPercentEncoding ?? link
        guard let directURL = VaultPathResolver.url(forRelativePath: cleanedPath, in: vaultURL) else {
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

    static func url(forWikiLink link: String, in vaultURL: URL) -> URL? {
        let target = wikiTarget(from: link)
        if let url = url(forMarkdownLink: target, in: vaultURL),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard URL(fileURLWithPath: target).pathExtension.isEmpty else { return nil }
        return url(forMarkdownLink: "\(target).md", in: vaultURL)
    }

    static func image(for link: String, in vaultURL: URL, maxPixelWidth: CGFloat) -> NSImage? {
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer { if didAccess { vaultURL.stopAccessingSecurityScopedResource() } }

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
        AppLogger.media.debug("Loaded media image")
        return image
    }

    static func cachedImage(for link: String, in vaultURL: URL, maxPixelWidth: CGFloat) -> NSImage? {
        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer { if didAccess { vaultURL.stopAccessingSecurityScopedResource() } }

        guard let url = mediaFileURL(for: link, in: vaultURL, allowVaultScan: false), url.isFileURL else {
            return nil
        }
        return mediaImageCache.object(forKey: mediaImageCacheKey(for: url, maxPixelWidth: maxPixelWidth))
    }

    static func invalidate() {
        mediaCacheLock.withLock {
            mediaURLCache.removeAllObjects()
            missingMediaURLCache.removeAll()
        }
        mediaImageCache.removeAllObjects()
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
        let cached: (URL?, Bool) = mediaCacheLock.withLock {
            (mediaURLCache.object(forKey: cacheKey) as URL?, missingMediaURLCache.contains(cacheKeyString))
        }

        if let cachedURL = cached.0 { return cachedURL }
        if cached.1 { return nil }

        guard let url = resolvedMediaFileURL(for: link, in: vaultURL, allowVaultScan: allowVaultScan), url.isFileURL else {
            if allowVaultScan {
                _ = mediaCacheLock.withLock { missingMediaURLCache.insert(cacheKeyString) }
            }
            return nil
        }

        mediaCacheLock.withLock { mediaURLCache.setObject(url as NSURL, forKey: cacheKey) }
        return url
    }

    private static func resolvedMediaFileURL(for link: String, in vaultURL: URL, allowVaultScan: Bool) -> URL? {
        if let url = URL(string: link), url.scheme != nil { return url }

        let rawTarget = wikiTarget(from: link)
        let decodedTarget = (rawTarget.removingPercentEncoding ?? rawTarget)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedTarget.isEmpty,
              let directURL = VaultPathResolver.url(forRelativePath: decodedTarget, in: vaultURL) else {
            return nil
        }
        if FileManager.default.fileExists(atPath: directURL.path) { return directURL }
        guard allowVaultScan else { return nil }
        if let foundURL = findVaultFile(named: decodedTarget, in: vaultURL) { return foundURL }
        guard URL(fileURLWithPath: decodedTarget).pathExtension.isEmpty else { return nil }
        return findVaultFile(named: "\(decodedTarget).md", in: vaultURL)
    }

    private static func mediaImageCacheKey(for url: URL, maxPixelWidth: CGFloat) -> NSString {
        let modificationTime = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0)
        return "\(url.path)|\(Int(maxPixelWidth.rounded(.up)))|\(modificationTime)" as NSString
    }

    private static func downsampledImage(at url: URL, maxPixelWidth: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(80, Int(maxPixelWidth.rounded(.up)))
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func imageCost(_ image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }
}
