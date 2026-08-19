import Foundation
import OSLog
import ServiceManagement

protocol LoginItemSystemClient {
    var isEnabled: Bool { get }
    var statusDescription: String { get }

    func setEnabled(_ isEnabled: Bool) throws
}

enum LoginItemStore {
    static var systemClient: any LoginItemSystemClient = ServiceManagementLoginItemSystemClient()

    static var isEnabled: Bool {
        get {
            systemClient.isEnabled
        }
        set {
            do {
                try systemClient.setEnabled(newValue)
                UserDefaults.standard.set(newValue, forKey: "startAtLogin")
                AppConfigStore.saveStartAtLogin(newValue)
                AppLogger.app.info(newValue ? "Registered app as login item" : "Unregistered app as login item")
            } catch {
                AppLogger.app.error("Failed to update login item: \(AppLogger.errorSummary(error))")
            }
        }
    }

    static var statusDescription: String {
        systemClient.statusDescription
    }
}

private struct ServiceManagementLoginItemSystemClient: LoginItemSystemClient {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return UserDefaults.standard.bool(forKey: "startAtLogin")
    }

    var statusDescription: String {
        guard #available(macOS 13.0, *) else {
            return "Unavailable on this macOS version"
        }

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

    func setEnabled(_ isEnabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }

        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
