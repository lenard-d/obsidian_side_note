import AppKit
import UniformTypeIdentifiers

enum MediaAttachmentImporter {
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
            return url
        }

        guard let string = pasteboard.string(forType: .fileURL) else {
            return nil
        }

        return URL(string: string)
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
}
