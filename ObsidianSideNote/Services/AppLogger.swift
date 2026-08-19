import Foundation
import OSLog

enum AppLogLevel: Int, Comparable, Sendable {
    case debug
    case info
    case warn
    case error
    case off

    static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AppLogEntry: Equatable, Sendable {
    let timestamp: Date
    let category: String
    let level: AppLogLevel
    let message: String
}

struct AppLogChannel: Sendable {
    let category: String
    private let logger: Logger

    init(subsystem: String, category: String) {
        self.category = category
        logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: @autoclosure () -> String) {
        log(message, level: .debug)
    }

    func info(_ message: @autoclosure () -> String) {
        log(message, level: .info)
    }

    func warn(_ message: @autoclosure () -> String) {
        log(message, level: .warn)
    }

    func error(_ message: @autoclosure () -> String) {
        log(message, level: .error)
    }

    private func log(_ message: () -> String, level: AppLogLevel) {
        let text = message()
        guard AppLogger.record(text, category: category, level: level) else {
            return
        }

        switch level {
        case .debug:
            logger.debug("\(text, privacy: .private)")
        case .info:
            logger.info("\(text, privacy: .private)")
        case .warn:
            logger.warning("\(text, privacy: .private)")
        case .error:
            logger.error("\(text, privacy: .private)")
        case .off:
            break
        }
    }
}

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "live.lukesmith.ObsidianSideNote"
    private static let state = AppLogState()

    static let app = AppLogChannel(subsystem: subsystem, category: "app")
    static let vault = AppLogChannel(subsystem: subsystem, category: "vault")
    static let media = AppLogChannel(subsystem: subsystem, category: "media")
    static let shortcuts = AppLogChannel(subsystem: subsystem, category: "shortcuts")

    static var minimumLevel: AppLogLevel {
        state.minimumLevel
    }

    static var recentEntries: [AppLogEntry] {
        state.entries
    }

    static func configure(minimumLevel: AppLogLevel) {
        state.minimumLevel = minimumLevel
    }

    static func clearRecentEntries() {
        state.clearEntries()
    }

    static func errorSummary(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(String(reflecting: type(of: error))) [\(nsError.domain):\(nsError.code)]"
    }

    fileprivate static func record(
        _ message: String,
        category: String,
        level: AppLogLevel
    ) -> Bool {
        state.record(
            AppLogEntry(
                timestamp: Date(),
                category: category,
                level: level,
                message: message
            )
        )
        return level >= state.minimumLevel && level != .off
    }
}

private final class AppLogState: @unchecked Sendable {
    private static let entryLimit = 200
    private let lock = NSLock()
    private var storedEntries: [AppLogEntry] = []
    private var storedMinimumLevel: AppLogLevel = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        ? .info
        : .off

    var minimumLevel: AppLogLevel {
        get {
            lock.withLock { storedMinimumLevel }
        }
        set {
            lock.withLock { storedMinimumLevel = newValue }
        }
    }

    var entries: [AppLogEntry] {
        lock.withLock { storedEntries }
    }

    func record(_ entry: AppLogEntry) {
        lock.withLock {
            storedEntries.append(entry)
            if storedEntries.count > Self.entryLimit {
                storedEntries.removeFirst(storedEntries.count - Self.entryLimit)
            }
        }
    }

    func clearEntries() {
        lock.withLock { storedEntries.removeAll(keepingCapacity: true) }
    }
}
