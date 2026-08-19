import Foundation

enum LinkPreviewPreferences {
    static let hoverDelaySecondsKey = "linkPreview.hoverDelaySeconds"
    static let defaultHoverDelaySeconds = 0.5
    static let allowedHoverDelaySeconds = 0.0 ... 5.0

    static var hoverDelaySeconds: Double {
        guard UserDefaults.standard.object(forKey: hoverDelaySecondsKey) != nil else {
            return defaultHoverDelaySeconds
        }
        return sanitized(UserDefaults.standard.double(forKey: hoverDelaySecondsKey))
    }

    static func setHoverDelaySeconds(_ seconds: Double) {
        let value = sanitized(seconds)
        UserDefaults.standard.set(value, forKey: hoverDelaySecondsKey)
        AppConfigStore.saveLinkPreviewHoverDelay(value)
    }

    static func sanitized(_ seconds: Double) -> Double {
        let finiteSeconds = seconds.isFinite ? seconds : defaultHoverDelaySeconds
        let clamped = min(max(finiteSeconds, allowedHoverDelaySeconds.lowerBound), allowedHoverDelaySeconds.upperBound)
        return (clamped * 10).rounded() / 10
    }
}
