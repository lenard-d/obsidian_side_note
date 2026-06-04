import AppKit
import UniformTypeIdentifiers

enum MediaAttachmentImporter {
    private static let maxRemoteMediaBytes = 25 * 1024 * 1024

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

    static func importFromPasteboard(_ pasteboard: NSPasteboard = .general, completion: @escaping (String?) -> Void) {
        if let relativePath = importFromPasteboard(pasteboard) {
            completion(relativePath)
            return
        }

        guard let remoteURL = remoteMediaURL(from: pasteboard) else {
            completion(nil)
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

    static func importFirst(from providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        importFirst(from: ArraySlice(providers), completion: completion)
    }

    static func isSupportedMedia(_ url: URL) -> Bool {
        let supportedExtensions = ["apng", "avif", "gif", "jpeg", "jpg", "m4v", "mov", "mp4", "png", "svg", "tif", "tiff", "webp"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func importFirst(from providers: ArraySlice<NSItemProvider>, completion: @escaping (String?) -> Void) {
        guard let provider = providers.first else {
            completion(nil)
            return
        }

        importProvider(provider) { relativePath in
            if let relativePath {
                completion(relativePath)
            } else {
                importFirst(from: providers.dropFirst(), completion: completion)
            }
        }
    }

    private static func importProvider(_ provider: NSItemProvider, completion: @escaping (String?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let sourceURL = sourceURL(from: item),
                      isSupportedMedia(sourceURL) else {
                    completion(nil)
                    return
                }

                completion(VaultStore.copyAttachment(from: sourceURL))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                guard let sourceURL = sourceURL(from: item) else {
                    completion(nil)
                    return
                }

                importRemoteMedia(from: sourceURL, completion: completion)
            }
            return
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    completion(nil)
                    return
                }

                completion(VaultStore.saveAttachmentImage(image))
            }
            return
        }

        for type in [UTType.png, .jpeg, .tiff, .gif] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data,
                      let image = NSImage(data: data) else {
                    completion(nil)
                    return
                }

                completion(VaultStore.saveAttachmentImage(image))
            }
            return
        }

        completion(nil)
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

    private static func importRemoteMedia(from url: URL, completion: @escaping (String?) -> Void) {
        guard isRemoteMedia(url) else {
            completion(nil)
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 20)
        RemoteMediaDownloader(maxBytes: maxRemoteMediaBytes).download(request) { data, response in
            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                completion(nil)
                return
            }

            let baseName = url.deletingPathExtension().lastPathComponent.isEmpty
                ? VaultStore.pastedImageBaseName()
                : url.deletingPathExtension().lastPathComponent
            completion(VaultStore.saveAttachmentData(data, suggestedName: baseName, fileExtension: url.pathExtension))
        }
    }

    private static func isRemoteMedia(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
        return isSupportedMedia(url)
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

final class RemoteMediaDownloader {
    private let maxBytes: Int
    private let configuration: URLSessionConfiguration

    init(maxBytes: Int, configuration: URLSessionConfiguration = .default) {
        self.maxBytes = maxBytes
        self.configuration = configuration
    }

    func download(_ request: URLRequest, completion: @escaping (Data?, URLResponse?) -> Void) {
        let delegate = RemoteMediaDownloadDelegate(maxBytes: maxBytes, completion: completion)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        delegate.session = session
        session.dataTask(with: request).resume()
    }
}

private final class RemoteMediaDownloadDelegate: NSObject, URLSessionDataDelegate {
    private let maxBytes: Int
    private let completion: (Data?, URLResponse?) -> Void
    private var data = Data()
    private var response: URLResponse?
    private var didComplete = false

    var session: URLSession?

    init(maxBytes: Int, completion: @escaping (Data?, URLResponse?) -> Void) {
        self.maxBytes = maxBytes
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300 ~= httpResponse.statusCode) {
            completionHandler(.cancel)
            complete(data: nil, response: response, cancelSession: true)
            return
        }

        if response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            complete(data: nil, response: response, cancelSession: true)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count + chunk.count <= maxBytes else {
            complete(data: nil, response: response, cancelSession: true)
            return
        }

        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard error == nil else {
            complete(data: nil, response: response, cancelSession: false)
            return
        }

        complete(data: data, response: response, cancelSession: false)
    }

    private func complete(data: Data?, response: URLResponse?, cancelSession: Bool) {
        guard !didComplete else { return }

        didComplete = true
        completion(data, response)

        if cancelSession {
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }
    }
}
