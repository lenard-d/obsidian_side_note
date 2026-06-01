import Foundation

struct ObsidianURIBuilder {
    static func appendDaily(vaultName: String, text: String) -> URL? {
        components(host: "daily", queryItems: [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "content", value: "\n\n" + text),
            URLQueryItem(name: "append", value: nil),
            URLQueryItem(name: "silent", value: nil)
        ]).url
    }

    static func openFile(vaultName: String, filePath: String) -> URL? {
        components(host: "open", queryItems: [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: filePath)
        ]).url
    }

    private static func components(host: String, queryItems: [URLQueryItem]) -> URLComponents {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = host
        components.queryItems = queryItems
        return components
    }
}
