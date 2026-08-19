import Foundation
import Testing
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @MainActor
    @Test func rejectedLoginItemChangeDoesNotPersistAnEnabledState() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let originalConfigURL = AppConfigStore.configURLOverride
        let originalClient = LoginItemStore.systemClient

        AppConfigStore.configURLOverride = configURL
        UserDefaults.standard.set(false, forKey: "startAtLogin")
        AppConfigStore.saveStartAtLogin(false)
        LoginItemStore.systemClient = RejectingLoginItemSystemClient()

        defer {
            LoginItemStore.systemClient = originalClient
            AppConfigStore.configURLOverride = originalConfigURL
            UserDefaults.standard.removeObject(forKey: "startAtLogin")
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        LoginItemStore.isEnabled = true

        #expect(!LoginItemStore.isEnabled)
        #expect(UserDefaults.standard.bool(forKey: "startAtLogin") == false)
        #expect(AppConfigStore.read()?.startAtLogin == false)
    }
}

private struct RejectingLoginItemSystemClient: LoginItemSystemClient {
    var isEnabled: Bool { false }
    var statusDescription: String { "Off" }

    func setEnabled(_ isEnabled: Bool) throws {
        throw LoginItemTestError.rejected
    }
}

private enum LoginItemTestError: Error {
    case rejected
}
