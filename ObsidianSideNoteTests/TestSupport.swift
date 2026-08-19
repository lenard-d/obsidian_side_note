import Testing
import Foundation
import AppKit
import WebKit
@testable import ObsidianSideNote

func testImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 12, height: 12))
    image.lockFocus()
    NSColor.systemPurple.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
    image.unlockFocus()
    return image
}

func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

func javaScriptStringLiteral(_ string: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [string])
    guard var literal = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
        return "\"\""
    }

    literal.removeFirst()
    literal.removeLast()
    return literal
}

final class MarkdownEditorReadyMessageHandler: NSObject, WKScriptMessageHandler {
    var isReady = false
    var errorMessage: String?
    var receivedMessages: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        receivedMessages.append(body)

        if type == "ready" {
            isReady = true
        } else if type == "error" {
            errorMessage = body["message"] as? String ?? "Unknown editor error"
        }
    }
}

func downloadRemoteMedia(maxBytes: Int) throws -> (data: Data?, response: URLResponse?) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemoteMediaURLProtocol.self]

    let downloader = RemoteMediaDownloader(maxBytes: maxBytes, configuration: configuration)
    let semaphore = DispatchSemaphore(value: 0)
    let url = URL(string: "https://example.com/media.png")!
    var result: (Data?, URLResponse?)?

    downloader.download(URLRequest(url: url)) { data, response in
        result = (data, response)
        semaphore.signal()
    }

    #expect(semaphore.wait(timeout: .now() + 2) == .success)
    let unwrappedResult = try #require(result)
    return (unwrappedResult.0, unwrappedResult.1)
}

final class RemoteMediaURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, chunks) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
func commandKeyEvent(_ key: String) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: key,
        charactersIgnoringModifiers: key,
        isARepeat: false,
        keyCode: 0
    )
}
