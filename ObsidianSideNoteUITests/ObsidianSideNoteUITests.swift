//
//  ObsidianSideNoteUITests.swift
//  ObsidianSideNoteUITests
//
//  Created by Luke  on 11/27/25.
//

import XCTest
import AppKit

final class ObsidianSideNoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInactiveWindowDragsFromEmptyHeaderOnFirstPress() throws {
        let app = testApplication()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowDragTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let bundleID = "live.lukesmith.ObsidianSideNote"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: bundleID))
        let savedDefaults = defaults.persistentDomain(forName: bundleID)
        app.launchEnvironment["OSN_TEST_CONFIG_URL"] = temporary.appendingPathComponent("config.json").path
        app.launchEnvironment["OSN_TEST_VAULT_PATH"] = temporary.path
        app.launchEnvironment["OSN_TEST_EDIT_FILE_PATH"] = "Example.md"
        try "# Example".write(to: temporary.appendingPathComponent("Example.md"), atomically: true, encoding: .utf8)
        app.launch()
        defer {
            app.terminate()
            if let savedDefaults { defaults.setPersistentDomain(savedDefaults, forName: bundleID) }
            else { defaults.removePersistentDomain(forName: bundleID) }
            defaults.synchronize()
            try? FileManager.default.removeItem(at: temporary)
        }
        app.typeKey("v", modifierFlags: [.command, .option, .control])
        let title = app.staticTexts["Edit Vault File"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch

        // Send the drag through Finder so XCTest does not first activate the note app.
        for headerPoint in [CGVector(dx: 0.75, dy: 23), CGVector(dx: 0.5, dy: 4)] {
            let before = window.frame
            let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
            finder.activate()
            XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
            XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "live.lukesmith.ObsidianSideNote")
            let start = CGPoint(x: before.minX + before.width * headerPoint.dx,
                                y: before.minY + headerPoint.dy)
            let end = CGPoint(x: start.x - 80, y: start.y + 50)
            let origin = finder.coordinate(withNormalizedOffset: .zero)
            let startCoordinate = origin.withOffset(CGVector(dx: start.x - origin.screenPoint.x,
                                                             dy: start.y - origin.screenPoint.y))
            let endCoordinate = origin.withOffset(CGVector(dx: end.x - origin.screenPoint.x,
                                                           dy: end.y - origin.screenPoint.y))
            startCoordinate.press(forDuration: 0.01, thenDragTo: endCoordinate)
            let moved = NSPredicate { _, _ in
                abs(window.frame.minX - (before.minX - 80)) < 12 &&
                abs(window.frame.minY - (before.minY + 50)) < 12
            }
            expectation(for: moved, evaluatedWith: nil)
            waitForExpectations(timeout: 3)
        }
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
        let linkedNoteURL = noteDirectory.appendingPathComponent("Linked.md")
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let noteText = "# Existing\n\nVisible UI test content.\n\n[Open linked](Inbox/Linked.md)\n\nOutside"

        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        try noteText.write(to: noteURL, atomically: true, encoding: .utf8)
        try "# Linked\n\nLinked UI test content.".write(
            to: linkedNoteURL,
            atomically: true,
            encoding: .utf8
        )
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
        // Keep the replacement test independent of the Mac's personal shortcuts.
        app.launchArguments += ["-NSUserDictionaryReplacementItems", """
        (
          { on = 1; replace = "==>"; with = "➯"; },
          { on = 1; replace = "=/"; with = "≠"; },
          { on = 1; replace = "nciht"; with = "nicht"; }
        )
        """]
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

        clickCenter(of: editor)
        attachInputDiagnostics(for: editor, in: app, step: "initial editor input")
        editor.typeText("OSN_UI_TEST")
        XCTAssertTrue((editor.value as? String)?.contains("OSN_UI_TEST") == true)
        XCTAssertTrue(waitForFileContent(noteURL, containing: "OSN_UI_TEST"))

        let boldButton = app.buttons["markdown-toolbar-bold"]
        XCTAssertTrue(boldButton.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(boldButton.frame.width, 28)
        XCTAssertGreaterThanOrEqual(boldButton.frame.height, 28)
        clickCenter(of: boldButton)
        attachInputDiagnostics(for: editor, in: app, step: "editor input after bold")
        editor.typeText("formatted")
        let toolbarAppliedBold = NSPredicate { _, _ in
            (editor.value as? String)?.contains("**formatted**") == true
        }
        expectation(for: toolbarAppliedBold, evaluatedWith: editor)
        waitForExpectations(timeout: 2)
        XCTAssertTrue(waitForFileContent(noteURL, containing: "**formatted**"))

        let markdownLink = app.buttons["Open link Open linked"]
        XCTAssertTrue(markdownLink.waitForExistence(timeout: 3))
        clickCenter(of: markdownLink)

        let linkedPathLoaded = NSPredicate { _, _ in
            searchField.value as? String == "Inbox/Linked.md"
                && (editor.value as? String)?.contains("Linked UI test content.") == true
        }
        expectation(for: linkedPathLoaded, evaluatedWith: searchField)
        waitForExpectations(timeout: 4)

        let linkedEditor = app.textViews.firstMatch
        attachInputDiagnostics(for: linkedEditor, in: app, step: "editor input after opening a Markdown link")
        linkedEditor.typeText("LINK_FOCUS_INPUT")
        XCTAssertTrue((linkedEditor.value as? String)?.contains("LINK_FOCUS_INPUT") == true)
        XCTAssertTrue(waitForFileContent(linkedNoteURL, containing: "LINK_FOCUS_INPUT"))

        for (shortcut, replacement, delimiter) in [("==>", "➯", " "), ("=/", "≠", " "), ("nciht", "nicht", "\n")] {
            linkedEditor.typeText("\n" + shortcut + delimiter)
            XCTAssertTrue((linkedEditor.value as? String)?.contains(replacement + delimiter) == true,
                          "Shortcut \(shortcut): \(linkedEditor.value ?? "missing editor value")")
            XCTAssertTrue(waitForFileContent(linkedNoteURL, containing: replacement + delimiter))
        }
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

    private func clickCenter(of element: XCUIElement) {
        // The note window intentionally floats above regular windows. XCUIElement.click()
        // can misclassify that same window as an interruption and try to scroll the
        // WebKit element, even though its frame is already visible. A direct coordinate
        // click exercises the same UI without depending on XCTest's scroll heuristic.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func attachInputDiagnostics(
        for element: XCUIElement,
        in app: XCUIApplication,
        step: String
    ) {
        XCTContext.runActivity(named: "Input diagnostics: \(step)") { activity in
            let screenshot = app.screenshot()
            let screenshotAttachment = XCTAttachment(screenshot: screenshot)
            screenshotAttachment.name = "UI immediately before text input"
            activity.add(screenshotAttachment)

            let hierarchyAttachment = XCTAttachment(
                string: "Target element:\n\(element.debugDescription)\n\nApplication hierarchy:\n\(app.debugDescription)"
            )
            hierarchyAttachment.name = "Accessibility hierarchy immediately before text input"
            activity.add(hierarchyAttachment)
        }
    }

    private func waitForFileContent(
        _ url: URL,
        containing expectedText: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let content = try? String(contentsOf: url, encoding: .utf8),
               content.contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
