import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @MainActor
    @Test func localMediaSaveFailureIsNotReportedAsUnsupported() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaAttachmentImporterTests-\(UUID().uuidString).png")
        try #require(pngData(from: testImage())).write(to: sourceURL, options: .atomic)

        let pasteboard = NSPasteboard(name: .init("MediaAttachmentImporterTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([sourceURL as NSURL]))

        UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
        UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "obsidianVault")

        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            pasteboard.clearContents()
        }

        let result = await withCheckedContinuation { continuation in
            MediaAttachmentImporter.importFromPasteboard(pasteboard) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .failure(.attachmentSaveFailed) = result else {
            Issue.record("Expected an attachment-save failure, got \(result)")
            return
        }
    }

    @MainActor
    @Test func providerLoadFailureIsReturnedAndLogged() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(nil, MediaProviderTestError.unavailable)
            return nil
        }

        let originalLogLevel = AppLogger.minimumLevel
        AppLogger.configure(minimumLevel: .off)
        AppLogger.clearRecentEntries()

        defer {
            AppLogger.configure(minimumLevel: originalLogLevel)
            AppLogger.clearRecentEntries()
        }

        let result = await withCheckedContinuation { continuation in
            MediaAttachmentImporter.importFirst(from: [provider]) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .failure(.providerLoadFailed) = result else {
            Issue.record("Expected a typed provider failure, got \(result)")
            return
        }
        #expect(AppLogger.recentEntries.contains { entry in
            entry.category == "media"
                && entry.level == .error
                && entry.message.contains("Media provider load failed")
        })
    }

    @MainActor
    @Test func remoteMediaTransportFailureIsReturnedAndLogged() async {
        let pasteboard = NSPasteboard(name: .init("MediaAttachmentImporterTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/offline.png", forType: .URL)

        let originalFactory = MediaAttachmentImporter.remoteDownloaderFactory
        let originalLogLevel = AppLogger.minimumLevel
        MediaAttachmentImporter.remoteDownloaderFactory = { _ in
            FailingRemoteMediaDownloader()
        }
        AppLogger.configure(minimumLevel: .off)
        AppLogger.clearRecentEntries()

        defer {
            MediaAttachmentImporter.remoteDownloaderFactory = originalFactory
            AppLogger.configure(minimumLevel: originalLogLevel)
            AppLogger.clearRecentEntries()
            pasteboard.clearContents()
        }

        let result = await withCheckedContinuation { continuation in
            MediaAttachmentImporter.importFromPasteboard(pasteboard) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .failure(.downloadFailed) = result else {
            Issue.record("Expected a typed download failure, got \(result)")
            return
        }
        #expect(AppLogger.recentEntries.contains { entry in
            entry.category == "media"
                && entry.level == .error
                && entry.message.contains("Remote media download failed")
                && !entry.message.contains("offline.png")
        })
    }
}

private struct FailingRemoteMediaDownloader: RemoteMediaDownloading {
    func download(
        _ request: URLRequest,
        completion: @escaping (Result<RemoteMediaDownload, Error>) -> Void
    ) {
        completion(.failure(MediaTransportTestError.offline))
    }
}

private enum MediaTransportTestError: Error {
    case offline
}

private enum MediaProviderTestError: Error {
    case unavailable
}
