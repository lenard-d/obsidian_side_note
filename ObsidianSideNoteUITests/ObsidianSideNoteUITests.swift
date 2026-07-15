//
//  ObsidianSideNoteUITests.swift
//  ObsidianSideNoteUITests
//
//  Created by Luke  on 11/27/25.
//

import XCTest

final class ObsidianSideNoteUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = testApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testRepeatedLaunchesDoNotCrash() throws {
        for _ in 0..<3 {
            let app = testApplication()
            app.launch()
            XCTAssertTrue(waitUntilRunning(app))
            app.terminate()
        }
    }

    @MainActor
    func testEditVaultShortcutLoadsContentAndAcceptsTyping() throws {
        let bundleIdentifier = "live.lukesmith.ObsidianSideNote"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: bundleIdentifier))
        let originalDefaults = defaults.persistentDomain(forName: bundleIdentifier)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObsidianSideNoteUITests-\(UUID().uuidString)", isDirectory: true)
        let vaultURL = temporaryDirectory.appendingPathComponent("Vault", isDirectory: true)
        let noteDirectory = vaultURL.appendingPathComponent("Inbox", isDirectory: true)
        let noteURL = noteDirectory.appendingPathComponent("Existing.md")
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let noteText = "# Existing\n\nVisible UI test content."

        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        try noteText.write(to: noteURL, atomically: true, encoding: .utf8)
        defer {
            if let originalDefaults {
                defaults.setPersistentDomain(originalDefaults, forName: bundleIdentifier)
            } else {
                defaults.removePersistentDomain(forName: bundleIdentifier)
            }
            defaults.synchronize()
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let app = testApplication()
        app.launchEnvironment["OSN_TEST_CONFIG_URL"] = configURL.path
        app.launchEnvironment["OSN_TEST_VAULT_PATH"] = vaultURL.path
        app.launchEnvironment["OSN_TEST_EDIT_FILE_PATH"] = "Inbox/Existing.md"
        app.launch()
        defer {
            app.terminate()
        }

        XCTAssertTrue(waitUntilRunning(app))
        app.typeKey("v", modifierFlags: [.command, .option, .control])

        let title = app.staticTexts["Edit Vault File"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        XCTAssertEqual(searchField.value as? String, "Inbox/Existing.md")

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertTrue((editor.value as? String)?.contains("Visible UI test content.") == true)

        app.typeText("OSN_UI_TEST")
        XCTAssertTrue((editor.value as? String)?.contains("OSN_UI_TEST") == true)

        let boldButton = app.buttons["markdown-toolbar-bold"]
        XCTAssertTrue(boldButton.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(boldButton.frame.width, 28)
        XCTAssertGreaterThanOrEqual(boldButton.frame.height, 28)
        boldButton.click()
        let toolbarAppliedBold = NSPredicate { _, _ in
            (editor.value as? String)?.contains("**text**") == true
        }
        expectation(for: toolbarAppliedBold, evaluatedWith: editor)
        waitForExpectations(timeout: 2)

        app.typeKey("z", modifierFlags: .command)
    }

    private func testApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        return app
    }

    private func waitUntilRunning(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.state != .notRunning {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
