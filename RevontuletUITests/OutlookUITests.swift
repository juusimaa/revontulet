import XCTest

/// The moon, the "soon" line and the outlook with stubbed FMI and NOAA data
/// (`-uiTestOutlook <scenario>`, specs/003-aurora-outlook quickstart §3).
final class OutlookUITests: XCTestCase {
    /// Oulu, inside the Oulujärvi zone (band Central).
    private static let oulu = "65.01,25.47"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ scenario: String, time: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestStubs", "-uiTestResetCache", "-uiTestOutlook", scenario, "-uiTestTime", time,
            "-uiTestLocation", Self.oulu, "-AppleLanguages", "(en)", "-AppleLocale", "en_FI",
        ] + extra
        app.launch()
        return app
    }

    /// Strong activity, a dark, clear sky and the full moon high in the south.
    @MainActor
    func testBrightMoonLowersTheHeadline() throws {
        let app = launch("moon", time: "2026-11-24T21:00:00Z")

        let headline = app.element("chanceHeadline").firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
        XCTAssertEqual(headline.value as? String, "Moderate, Bright moon")

        app.buttons["detailsToggle"].tap()
        let moon = app.element("moonDetail")
        XCTAssertTrue(moon.waitForExistence(timeout: 5))
        XCTAssertTrue(moon.label.contains("full moon"), moon.label)
        XCTAssertTrue(moon.label.hasSuffix("up"), moon.label)
    }
}
