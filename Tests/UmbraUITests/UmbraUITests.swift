import XCTest

/// UI end-to-end tests. They drive Umbra's main window through accessibility, like a person would.
/// Run with scripts/e2e/ui_e2e.sh, which quits the installed copy first and reopens it after.
final class UmbraUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Open the main window, and skip the welcome screen and permission explainers.
        app.launchArguments = ["--window", "-onboardingDone", "YES", "-askedAccessibility", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mode.manual"].waitForExistence(timeout: 10), "the main window did not open")
        app.buttons["mode.manual"].click()
    }

    override func tearDownWithError() throws {
        app.buttons["mode.manual"].click()
        app.terminate()
    }

    func testModePickerChangesMode() {
        app.buttons["mode.sync"].click()
        let status = app.staticTexts["mode.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "value CONTAINS 'Following' OR label CONTAINS 'Following'")
        expectation(for: predicate, evaluatedWith: status)
        waitForExpectations(timeout: 3)
    }

    func testBrightnessSliderMoves() throws {
        let slider = app.sliders.matching(NSPredicate(format: "identifier BEGINSWITH 'brightness.'")).firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 3), "no brightness slider")
        let before = slider.normalizedSliderPosition
        slider.adjust(toNormalizedSliderPosition: before > 0.5 ? 0.3 : 0.7)
        XCTAssertNotEqual(slider.normalizedSliderPosition, before, accuracy: 0.05)
        slider.adjust(toNormalizedSliderPosition: before)
    }

    func testSettingsShowAwayMode() {
        app.buttons["openSettings"].click()
        let toggle = app.checkBoxes["away.enabled"].exists ? app.checkBoxes["away.enabled"] : app.switches["away.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Away mode setting is missing")
    }
}
