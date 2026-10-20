import XCTest

/// Walks through the demo and keeps a screenshot of each screen, so changes to
/// the interface can be reviewed without a device.
final class DemoTourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-demoMode", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Sign In with Email"].waitForExistence(timeout: 10))
        snapshot(app, "01-welcome")

        app.buttons["Sign In with Email"].tap()
        XCTAssertTrue(app.navigationBars["Sign In"].waitForExistence(timeout: 5))
        snapshot(app, "02-sign-in")
    }

    @MainActor
    func testDemoTour() {
        let app = XCUIApplication()
        app.launchArguments += ["-demoMode", "YES"]
        app.launch()

        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'years'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "The nearby grid should load")
        sleep(3)  // Let the photos arrive.
        snapshot(app, "03-browse")

        app.buttons["Filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        snapshot(app, "04-filters")
        let tags = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tags'")).firstMatch
        for _ in 0..<6 where !tags.isHittable { app.swipeUp() }
        tags.tap()
        XCTAssertTrue(app.buttons["Hiking"].waitForExistence(timeout: 10), "The tag catalog should load")
        app.buttons["Hiking"].tap()
        app.buttons["Coffee"].tap()
        snapshot(app, "11-tags")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Cancel"].tap()

        app.buttons["Explore Another Place"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 5))
        sleep(3)  // Map tiles.
        app.maps.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        sleep(2)
        snapshot(app, "12-explore")
        app.buttons["Explore Here"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "The explored grid should load")
        sleep(2)
        snapshot(app, "13-exploring")
        app.buttons["Back to My Location"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 10))

        tile.tap()
        let message = app.buttons["Message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        sleep(2)
        snapshot(app, "05-profile")
        app.swipeUp()
        snapshot(app, "06-profile-details")

        message.tap()
        let field = app.textFields["Message"].exists ? app.textFields["Message"] : app.textViews["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hey, how's your evening going?")
        app.buttons["Send"].tap()
        sleep(4)  // The demo replies after a short pause.
        snapshot(app, "07-chat")

        // Back to the grid: the chat and the profile hide the tab bar.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Messages"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Messages"].tap()
        sleep(2)
        snapshot(app, "08-messages")

        app.tabBars.buttons["Interest"].tap()
        sleep(2)
        snapshot(app, "09-interest")

        app.tabBars.buttons["Profile"].tap()
        sleep(1)
        snapshot(app, "10-me")

        app.buttons["Edit Photos"].tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 5))
        sleep(2)
        snapshot(app, "14-photos")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo 2 of'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Make Main Photo"].waitForExistence(timeout: 5))
        snapshot(app, "15-photo-menu")
        app.buttons["Make Main Photo"].tap()
        sleep(1)
        snapshot(app, "16-photos-reordered")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
