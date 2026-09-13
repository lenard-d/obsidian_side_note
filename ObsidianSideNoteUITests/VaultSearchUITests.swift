import XCTest

final class VaultSearchUITests: XCTestCase {
    @MainActor
    func testFolderSectionsKeyboardSelectionAndUnicodeFilename() throws {
        continueAfterFailure = false
        let bundleID = "live.lukesmith.ObsidianSideNote"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: bundleID))
        let savedDefaults = defaults.persistentDomain(forName: bundleID)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("SearchUITest-\(UUID().uuidString)")
        let vault = temporary.appendingPathComponent("Vault")
        let archive = vault.appendingPathComponent("Work/Archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try "# Existing\n\nStart here.".write(to: vault.appendingPathComponent("Existing.md"), atomically: true, encoding: .utf8)
        try "# Plan\n\nDirect file content.".write(to: vault.appendingPathComponent("Work/Plan.md"), atomically: true, encoding: .utf8)
        let exactURL = archive.appendingPathComponent("Team’s Weekly Review.md")
        try "# Team’s Weekly Review\n\nUnicode search target.".write(to: exactURL, atomically: true, encoding: .utf8)
        let projects = vault.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try "# Projects\n\nFolder note content.".write(to: projects.appendingPathComponent("Projects.md"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()

        defer {
            app.terminate()
            if let savedDefaults { defaults.setPersistentDomain(savedDefaults, forName: bundleID) }
            else { defaults.removePersistentDomain(forName: bundleID) }
            defaults.synchronize()
            try? FileManager.default.removeItem(at: temporary)
        }
        app.launchArguments = ["--uitesting", "-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment["OSN_TEST_CONFIG_URL"] = temporary.appendingPathComponent("config.json").path
        app.launchEnvironment["OSN_TEST_VAULT_PATH"] = vault.path
        app.launchEnvironment["OSN_TEST_EDIT_FILE_PATH"] = "Existing.md"
        app.launch()
        app.typeKey("v", modifierFlags: [.command, .option, .control])
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceSearch(search, with: "Work/", in: app)

        let folder = app.buttons["vault-search-row-Work/Archive"]
        let direct = app.buttons["vault-search-row-Work/Plan.md"]
        let nested = app.buttons["vault-search-row-Work/Archive/Team’s Weekly Review.md"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(direct.exists)
        XCTAssertTrue(nested.exists)
        XCTAssertLessThan(folder.frame.minY, direct.frame.minY)
        XCTAssertLessThan(direct.frame.minY, nested.frame.minY)
        XCTAssertEqual(direct.label, "Plan")
        XCTAssertEqual(nested.label, "Team’s Weekly Review")
        attachScreenshot(app, name: "Folder and file sections")

        app.typeKey(.downArrow, modifierFlags: [.command])
        XCTAssertTrue(waitForValue("Selected", on: direct))
        app.typeKey(.downArrow, modifierFlags: [.command])
        XCTAssertTrue(waitForValue("Selected", on: nested))
        app.typeKey(.upArrow, modifierFlags: [.command])
        XCTAssertTrue(waitForValue("Selected", on: direct))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("Work/Plan.md", on: search))
        let editor = app.textViews.firstMatch
        XCTAssertTrue(waitForText("Direct file content.", on: editor))

        replaceSearch(search, with: "Work/", in: app)
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("Work/Archive/", on: search))
        // Typing after folder activation proves that the search field kept keyboard focus.
        app.typeText("Team's Weekly Review.md")
        XCTAssertTrue(waitForValue("Selected", on: nested))
        attachScreenshot(app, name: "Exact Unicode filename match")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForText("Unicode search target.", on: editor))
        XCTAssertTrue(waitForValue("Work/Archive/Team’s Weekly Review.md", on: search))

        replaceSearch(search, with: "Projects", in: app)
        let projectsFolder = app.buttons["vault-search-row-Projects"]
        let folderNote = app.buttons["vault-search-row-Projects/Projects.md"]
        XCTAssertTrue(waitForValue("Selected", on: projectsFolder))
        app.typeKey(.downArrow, modifierFlags: [.command])
        XCTAssertTrue(waitForValue("Selected", on: folderNote))
        app.typeKey(.upArrow, modifierFlags: [.command])
        XCTAssertTrue(waitForValue("Selected", on: projectsFolder))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("Projects/", on: search))
        XCTAssertTrue(waitForText("Unicode search target.", on: editor))

        replaceSearch(search, with: "Projects.md", in: app)
        XCTAssertTrue(waitForValue("Selected", on: folderNote))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("Projects/Projects.md", on: search))
        XCTAssertTrue(waitForText("Folder note content.", on: editor))

        replaceSearch(search, with: "Work/", in: app)
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(folder.exists)
        XCTAssertTrue(search.exists)
    }

    @MainActor
    private func replaceSearch(_ field: XCUIElement, with query: String, in app: XCUIApplication) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeText(query)
    }

    private func waitForValue(_ value: String, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)], timeout: 5) == .completed
    }

    private func waitForText(_ text: String, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)], timeout: 5) == .completed
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
