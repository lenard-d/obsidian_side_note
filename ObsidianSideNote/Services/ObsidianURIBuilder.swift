import Foundation

struct ObsidianURIBuilder {
    static func openDaily(vaultName: String) -> URL? {
        components(host: "daily", queryItems: [
            URLQueryItem(name: "vault", value: vaultName)
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
