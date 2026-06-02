import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "live.lukesmith.ObsidianSideNote"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let vault = Logger(subsystem: subsystem, category: "vault")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
}
