import AppKit
import UniformTypeIdentifiers

enum MediaAttachmentImportError: Error, Equatable {
    case unsupportedItem
    case providerLoadFailed
    case downloadFailed
    case invalidRemoteResponse
    case attachmentSaveFailed

    var userMessage: String {
        switch self {
        case .unsupportedItem:
            return "No supported image or video was found."
        case .providerLoadFailed:
            return "The image or video could not be read."
        case .downloadFailed:
            return "The remote media could not be downloaded."
        case .invalidRemoteResponse:
            return "The remote server did not return a supported image or video."
        case .attachmentSaveFailed:
            return "The media could not be saved in the selected vault."
        }
    }
}

enum MediaAttachmentImporter {
    private static let maxRemoteMediaBytes = 25 * 1024 * 1024
    static var remoteDownloaderFactory: (Int) -> any RemoteMediaDownloading = {
        RemoteMediaDownloader(maxBytes: $0)
    }

    static let supportedDropTypes: [UTType] = [
        .image,
        .png,
        .jpeg,
        .tiff,
        .gif,
        .fileURL,
        .movie,
        .mpeg4Movie,
        .quickTimeMovie
    ]

    static var pasteboardTypes: [NSPasteboard.PasteboardType] {
        supportedDropTypes.map { NSPasteboard.PasteboardType($0.identifier) }
            + [.URL, .html, .string]
    }

    static func importFromPasteboard(_ pasteboard: NSPasteboard = .general) -> String? {
        if let fileURL = fileURL(from: pasteboard),
           isSupportedMedia(fileURL) {
            return VaultStore.copyAttachment(from: fileURL)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return VaultStore.saveAttachmentImage(image)
        }

        return nil
    }

    static func importFromPasteboard(
        _ pasteboard: NSPasteboard = .general,
        completion: @escaping (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        if let fileURL = fileURL(from: pasteboard),
           isSupportedMedia(fileURL) {
            completeAttachmentSave(
                VaultStore.copyAttachment(from: fileURL),
                completion: completion
            )
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            completeAttachmentSave(
                VaultStore.saveAttachmentImage(image),
                completion: completion
            )
            return
        }

        guard let remoteURL = remoteMediaURL(from: pasteboard) else {
            completion(.failure(.unsupportedItem))
            return
        }

        importRemoteMedia(from: remoteURL, completion: completion)
    }

    static func canImportFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        if let fileURL = fileURL(from: pasteboard), isSupportedMedia(fileURL) {
            return true
        }

        if remoteMediaURL(from: pasteboard) != nil {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
    }

    static func importFirst(
        from providers: [NSItemProvider],
        completion: @escaping (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        importFirst(
            from: ArraySlice(providers),
            lastFailure: .unsupportedItem,
            completion: completion
        )
    }

    static func isSupportedMedia(_ url: URL) -> Bool {
        let supportedExtensions = ["apng", "avif", "gif", "jpeg", "jpg", "m4v", "mov", "mp4", "png", "svg", "tif", "tiff", "webp"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func importFirst(
        from providers: ArraySlice<NSItemProvider>,
        lastFailure: MediaAttachmentImportError,
        completion: @escaping (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        guard let provider = providers.first else {
            completion(.failure(lastFailure))
            return
        }

        importProvider(provider) { result in
            switch result {
            case .success:
                completion(result)
            case let .failure(error):
                let nextFailure = error == .unsupportedItem ? lastFailure : error
                importFirst(
                    from: providers.dropFirst(),
                    lastFailure: nextFailure,
                    completion: completion
                )
            }
        }
    }

    private static func importProvider(
        _ provider: NSItemProvider,
        completion: @escaping (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil else {
                    completeProviderLoadFailure(error, completion: completion)
                    return
                }
                guard let sourceURL = sourceURL(from: item),
                      isSupportedMedia(sourceURL) else {
                    completion(.failure(.unsupportedItem))
                    return
                }

                completeAttachmentSave(
                    VaultStore.copyAttachment(from: sourceURL),
                    completion: completion
                )
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                guard error == nil else {
                    completeProviderLoadFailure(error, completion: completion)
                    return
                }
                guard let sourceURL = sourceURL(from: item) else {
                    completeProviderLoadFailure(nil, completion: completion)
                    return
                }

                importRemoteMedia(from: sourceURL, completion: completion)
            }
            return
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, error in
                guard error == nil else {
                    completeProviderLoadFailure(error, completion: completion)
                    return
                }
                guard let image = object as? NSImage else {
                    completeProviderLoadFailure(nil, completion: completion)
                    return
                }

                completeAttachmentSave(
                    VaultStore.saveAttachmentImage(image),
                    completion: completion
                )
            }
            return
        }

        for type in [UTType.png, .jpeg, .tiff, .gif] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                guard error == nil else {
                    completeProviderLoadFailure(error, completion: completion)
                    return
                }
                guard let data,
                      let image = NSImage(data: data) else {
                    completeProviderLoadFailure(nil, completion: completion)
                    return
                }

                completeAttachmentSave(
                    VaultStore.saveAttachmentImage(image),
                    completion: completion
                )
            }
            return
        }

        completion(.failure(.unsupportedItem))
    }

    private static func completeProviderLoadFailure(
        _ error: Error?,
        completion: (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        if let error {
            AppLogger.media.error("Media provider load failed: \(AppLogger.errorSummary(error))")
        } else {
            AppLogger.media.error("Media provider load failed without a usable value")
        }
        completion(.failure(.providerLoadFailed))
    }

    private static func completeAttachmentSave(
        _ relativePath: String?,
        completion: (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        guard let relativePath else {
            AppLogger.media.error("Media attachment save failed")
            completion(.failure(.attachmentSaveFailed))
            return
        }
        completion(.success(relativePath))
    }

    private static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        if let url = NSURL(from: pasteboard) as URL? {
            return url.isFileURL ? url : nil
        }

        guard let string = pasteboard.string(forType: .fileURL) else {
            return nil
        }

        let url = URL(string: string)
        return url?.isFileURL == true ? url : nil
    }

    private static func remoteMediaURL(from pasteboard: NSPasteboard) -> URL? {
        if let url = pasteboard.string(forType: .URL).flatMap(URL.init(string:)),
           isRemoteMedia(url) {
            return url
        }

        if let html = pasteboard.string(forType: .html),
           let url = imageSourceURL(fromHTML: html),
           isRemoteMedia(url) {
            return url
        }

        if let string = pasteboard.string(forType: .string),
           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
           isRemoteMedia(url) {
            return url
        }

        return nil
    }

    private static func sourceURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }

    private static func importRemoteMedia(
        from url: URL,
        completion: @escaping (Result<String, MediaAttachmentImportError>) -> Void
    ) {
        guard isRemoteMedia(url) else {
            completion(.failure(.unsupportedItem))
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 20)
        remoteDownloaderFactory(maxRemoteMediaBytes).download(request) { result in
            guard case let .success(download) = result else {
                if case let .failure(error) = result {
                    AppLogger.media.error("Remote media download failed: \(AppLogger.errorSummary(error))")
                }
                completion(.failure(.downloadFailed))
                return
            }

            guard let httpResponse = download.response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  isSupportedRemoteMediaResponse(httpResponse, fileExtension: url.pathExtension) else {
                AppLogger.media.warn("Remote media response was not a supported image or video")
                completion(.failure(.invalidRemoteResponse))
                return
            }

            let baseName = url.deletingPathExtension().lastPathComponent.isEmpty
                ? VaultStore.pastedImageBaseName()
                : url.deletingPathExtension().lastPathComponent
            guard let relativePath = VaultStore.saveAttachmentData(
                download.data,
                suggestedName: baseName,
                fileExtension: url.pathExtension
            ) else {
                completion(.failure(.attachmentSaveFailed))
                return
            }
            completion(.success(relativePath))
        }
    }

    private static func isRemoteMedia(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
        return isSupportedMedia(url)
    }

    static func isSupportedRemoteMediaResponse(_ response: HTTPURLResponse, fileExtension: String) -> Bool {
        guard let contentTypeHeader = response.value(forHTTPHeaderField: "Content-Type") else {
            return true
        }

        let mimeType = contentTypeHeader
            .split(separator: ";", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? ""
        guard let contentType = UTType(mimeType: mimeType) else {
            return false
        }

        let extensionType = UTType(filenameExtension: fileExtension.lowercased())
        let isMediaContent = contentType.conforms(to: .image) || contentType.conforms(to: .movie)
        let extensionMatches = extensionType.map { contentType.conforms(to: $0) || $0.conforms(to: contentType) } ?? true
        return isMediaContent && extensionMatches
    }

    private static func imageSourceURL(fromHTML html: String) -> URL? {
        guard let range = html.range(
            of: #"<img[^>]+src=["']([^"']+)["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let match = String(html[range])
        guard let srcRange = match.range(
            of: #"src=["']([^"']+)["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let attribute = String(match[srcRange])
        let value = attribute
            .replacingOccurrences(of: #"^src=["']"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: value)
    }
}
