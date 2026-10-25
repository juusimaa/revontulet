import XCTest

/// Alert settings with an in-memory alert service and notifications allowed (`-uiTestAlertsStub`).
final class AlertSettingsUITests: XCTestCase {
    private static let language = ["-AppleLanguages", "(en)", "-AppleLocale", "en_FI"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAlertsStub", "-uiTestStubs"] + arguments + Self.language
        app.launch()
        return app
    }

    @MainActor
    func testTurnOnWithModerate() throws {
        let app = launch(["-uiTestResetCache", "-uiTestLocation", "65.01,25.47"])
        // The zone comes from the main screen's result for Oulu.
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))

        let bell = app.buttons["alertsButton"]
        XCTAssertEqual(bell.label, "Aurora alerts, off")
        bell.tap()

        XCTAssertTrue(app.element("alertArea").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("alertArea").label.contains("Oulujärvi"), app.element("alertArea").label)
        app.buttons["threshold-moderate"].tap()
        XCTAssertTrue(app.buttons["threshold-moderate"].isSelected)
        app.buttons["turnOnAlerts"].tap()

        let confirmed = app.element("alertConfirmation")
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmed.waitForLabel(containing: "Confirmed", timeout: 5), confirmed.label)
        XCTAssertTrue(app.element("alertArea").label.contains("Oulujärvi"))
        XCTAssertTrue(app.buttons["threshold-moderate"].isSelected)
        XCTAssertTrue(app.element("alertsStatus").label.contains("On"), app.element("alertsStatus").label)

        app.buttons["alertSettingsDone"].tap()
        XCTAssertTrue(bell.waitForLabel(containing: "Aurora alerts, on", timeout: 5), bell.label)
    }

    @MainActor
    func testNoZoneWithoutPlace() throws {
        let app = launch(["-uiTestResetCache", "-uiTestLocationDenied"])
        XCTAssertTrue(app.element("locationDenied").waitForExistence(timeout: 15))

        app.buttons["alertsButton"].tap()

        XCTAssertTrue(app.element("alertsNoZone").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a place in Finland first"].exists)
        XCTAssertFalse(app.buttons["turnOnAlerts"].exists)
        XCTAssertTrue(app.buttons["alertsChoosePlace"].exists)
    }
}
