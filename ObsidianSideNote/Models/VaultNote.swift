import Foundation

nonisolated struct VaultNote: Identifiable, Hashable, Sendable {
    let relativePath: String
    let title: String
    let url: URL

    var id: String {
        relativePath
    }
}
