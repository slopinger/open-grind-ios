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
        // In the form, not the chips behind the sheet.
        let age = app.collectionViews.buttons["Age"]
        age.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5), "Tapping a range row opens its wheels")
        snapshot(app, "17-filter-wheel")
        age.tap()
        app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tags'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Hiking"].waitForExistence(timeout: 10), "The tag catalog should load")
        app.buttons["Hiking"].tap()
        app.buttons["Coffee"].tap()
        snapshot(app, "11-tags")
        // Closing the sheet applies the filters; the rest of the tour wants the whole grid.
        app.buttons["Hiking"].tap()
        app.buttons["Coffee"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()

        // The common filters are chips too; age opens two wheels from the bottom.
        app.buttons["Age"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5), "The age chip opens wheels")
        snapshot(app, "20-age-chip")
        app.buttons["Done"].tap()

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
        XCTAssertTrue(app.buttons["Explore Another Place"].waitForExistence(timeout: 10))

        tile.tap()
        // The first tile's page comes first; the next profile's page may be loaded beside it.
        let message = app.buttons.matching(identifier: "Message").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        sleep(2)
        snapshot(app, "05-profile")
        // Below the photos, which page up and down themselves.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        snapshot(app, "06-profile-details")

        message.tap()
        let field = app.textFields["Message"].exists ? app.textFields["Message"] : app.textViews["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hey, how's your evening going?")
        app.buttons["Send"].tap()
        sleep(4)  // The demo replies after a short pause.
        snapshot(app, "07-chat")

        // Back to the grid: the profile covers the tab bar.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
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

        app.buttons["Edit Profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit Profile"].waitForExistence(timeout: 5))
        sleep(1)
        snapshot(app, "18-edit-profile")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photos'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 5))
        sleep(2)
        snapshot(app, "14-photos")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo 2 of'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Make Main Photo"].waitForExistence(timeout: 5))
        snapshot(app, "15-photo-menu")
        app.buttons["Make Main Photo"].tap()
        sleep(1)
        snapshot(app, "16-photos-reordered")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let age = app.buttons["Age"]
        for _ in 0..<6 where !age.isHittable { app.swipeUp() }
        age.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5), "Tapping a number row opens a wheel")
        snapshot(app, "19-age-wheel")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
