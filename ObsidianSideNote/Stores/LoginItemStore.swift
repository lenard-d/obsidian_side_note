import Foundation
import OSLog
import ServiceManagement

enum LoginItemStore {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }

            return UserDefaults.standard.bool(forKey: "startAtLogin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "startAtLogin")
            AppConfigStore.saveStartAtLogin(newValue)

            guard #available(macOS 13.0, *) else {
                return
            }

            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    AppLogger.app.info("Registered app as login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    AppLogger.app.info("Unregistered app as login item")
                }
            } catch {
                AppLogger.app.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "Enabled"
            case .requiresApproval:
                return "Requires approval in System Settings"
            case .notRegistered:
                return "Off"
            case .notFound:
                return "Unavailable"
            @unknown default:
                return "Unknown"
            }
        }

        return "Unavailable on this macOS version"
    }
}
