import Foundation

struct VaultNote: Identifiable, Hashable {
    let relativePath: String
    let title: String
    let url: URL

    var id: String {
        relativePath
    }
}
