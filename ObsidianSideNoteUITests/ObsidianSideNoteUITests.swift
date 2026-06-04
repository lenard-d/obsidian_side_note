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
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testRepeatedLaunchesDoNotCrash() throws {
        for _ in 0..<3 {
            let app = XCUIApplication()
            app.launch()
            XCTAssertTrue(waitUntilRunning(app))
            app.terminate()
        }
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
