import Testing
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @Test func loggingCanStayQuietWhileRetainingFailureDiagnostics() {
        let previousLevel = AppLogger.minimumLevel
        defer {
            AppLogger.configure(minimumLevel: previousLevel)
            AppLogger.clearRecentEntries()
        }

        AppLogger.configure(minimumLevel: .off)
        AppLogger.clearRecentEntries()

        AppLogger.app.debug("debug diagnostic")
        AppLogger.app.info("info diagnostic")
        AppLogger.app.warn("warning diagnostic")
        AppLogger.app.error("error diagnostic")

        #expect(AppLogger.recentEntries.map(\.level) == [.debug, .info, .warn, .error])
        #expect(AppLogger.recentEntries.allSatisfy { $0.category == "app" })
    }

    @Test func diagnosticBufferHasABoundedSize() {
        AppLogger.clearRecentEntries()
        defer { AppLogger.clearRecentEntries() }

        for index in 0..<250 {
            AppLogger.app.debug("diagnostic \(index)")
        }

        #expect(AppLogger.recentEntries.count == 200)
    }
}
