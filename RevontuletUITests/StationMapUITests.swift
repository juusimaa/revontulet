import XCTest

/// The map page beside the main screen (issue #2).
final class StationMapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStubs", "-uiTestLocation", "65.01,25.47", "-AppleLanguages", "(en)", "-AppleLocale", "en_FI"]
            + (reset ? ["-uiTestResetCache"] : [])
        app.launch()
        return app
    }

    @MainActor
    func testSwipingShowsTheMapAndTheMostActiveStation() {
        let app = launch(reset: true)
        XCTAssertTrue(app.element("chanceHeadline").firstMatch.waitForExistence(timeout: 10))

        app.swipeLeft()

        XCTAssertTrue(app.staticTexts["Auroras in Finland now"].waitForExistence(timeout: 5))
        // The station card reads as one element with the thresholds in words.
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Probable from R'"))
        XCTAssertTrue(card.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Kevo"].exists)
    }

    @MainActor
    func testTappingAStationShowsIt() {
        let app = launch(reset: true)
        XCTAssertTrue(app.element("chanceHeadline").firstMatch.waitForExistence(timeout: 10))
        app.swipeLeft()

        let pello = app.buttons["Pello"]
        XCTAssertTrue(pello.waitForExistence(timeout: 10))
        pello.tap()

        XCTAssertTrue(pello.isSelected)
    }

    @MainActor
    func testTheMapPageIsRememberedAcrossLaunches() {
        var app = launch(reset: true)
        XCTAssertTrue(app.element("chanceHeadline").firstMatch.waitForExistence(timeout: 10))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Auroras in Finland now"].waitForExistence(timeout: 5))
        app.terminate()

        app = launch(reset: false)

        XCTAssertTrue(app.staticTexts["Auroras in Finland now"].waitForExistence(timeout: 10))
    }
}
