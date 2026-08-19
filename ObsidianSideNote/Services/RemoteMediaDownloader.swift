import Foundation

struct RemoteMediaDownload {
    let data: Data
    let response: URLResponse
}

protocol RemoteMediaDownloading {
    func download(
        _ request: URLRequest,
        completion: @escaping (Result<RemoteMediaDownload, Error>) -> Void
    )
}

final class RemoteMediaDownloader: RemoteMediaDownloading {
    private let maxBytes: Int
    private let configuration: URLSessionConfiguration

    init(maxBytes: Int, configuration: URLSessionConfiguration = .default) {
        self.maxBytes = maxBytes
        self.configuration = configuration
    }

    func download(_ request: URLRequest, completion: @escaping (Data?, URLResponse?) -> Void) {
        performDownload(request) { result in
            switch result {
            case let .success(download):
                completion(download.data, download.response)
            case let .failure(error):
                completion(nil, (error as? RemoteMediaDownloadError)?.response)
            }
        }
    }

    func download(
        _ request: URLRequest,
        completion: @escaping (Result<RemoteMediaDownload, Error>) -> Void
    ) {
        performDownload(request, completion: completion)
    }

    private func performDownload(
        _ request: URLRequest,
        completion: @escaping (Result<RemoteMediaDownload, Error>) -> Void
    ) {
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
    private let completion: (Result<RemoteMediaDownload, Error>) -> Void
    private var data = Data()
    private var response: URLResponse?
    private var didComplete = false

    var session: URLSession?

    init(maxBytes: Int, completion: @escaping (Result<RemoteMediaDownload, Error>) -> Void) {
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
            complete(.failure(RemoteMediaDownloadError.rejectedHTTPStatus(response)), cancelSession: true)
            return
        }

        if response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            complete(.failure(RemoteMediaDownloadError.exceedsSizeLimit(response)), cancelSession: true)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count + chunk.count <= maxBytes else {
            complete(.failure(RemoteMediaDownloadError.exceedsSizeLimit(response)), cancelSession: true)
            return
        }

        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            complete(.failure(error), cancelSession: false)
            return
        }

        guard let response else {
            complete(.failure(RemoteMediaDownloadError.missingResponse), cancelSession: false)
            return
        }

        complete(.success(RemoteMediaDownload(data: data, response: response)), cancelSession: false)
    }

    private func complete(_ result: Result<RemoteMediaDownload, Error>, cancelSession: Bool) {
        guard !didComplete else { return }

        didComplete = true
        completion(result)

        if cancelSession {
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }
    }
}

private enum RemoteMediaDownloadError: Error {
    case rejectedHTTPStatus(URLResponse)
    case exceedsSizeLimit(URLResponse?)
    case missingResponse

    var response: URLResponse? {
        switch self {
        case let .rejectedHTTPStatus(response):
            return response
        case let .exceedsSizeLimit(response):
            return response
        case .missingResponse:
            return nil
        }
    }
}
