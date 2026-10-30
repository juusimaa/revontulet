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

    // MARK: Soon (US2)

    /// 21:00 in Finland on a new-moon night.
    private static let darkNight = "2026-11-09T19:00:00Z"

    @MainActor
    func testStormShowsTheSoonLineAndLeavesTheHeadline() throws {
        let app = launch("storm", time: Self.darkNight)

        let soon = app.element("soonLine")
        XCTAssertTrue(soon.waitForExistence(timeout: 15))
        XCTAssertTrue(soon.label.hasPrefix("Forecast: Activity likely to rise within about"), soon.label)
        // The stubs' activity is Possible at Oulujärvi: the headline is the measurement, unchanged.
        XCTAssertEqual(app.element("chanceHeadline").value as? String, "Moderate, Some activity")
    }

    @MainActor
    func testQuietHasNoSoonLine() throws {
        let app = launch("quiet", time: Self.darkNight)

        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))
        XCTAssertTrue(app.element("outlookTonight").waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("soonLine").exists)
        app.buttons["detailsToggle"].tap()
        let solarWind = app.element("solarWindDetail")
        XCTAssertTrue(solarWind.waitForExistence(timeout: 5))
        XCTAssertTrue(solarWind.label.contains("No sign of rising activity"), solarWind.label)
    }

    @MainActor
    func testNoaaDownHidesTheSoonLineAndKeepsTheHeadline() throws {
        let app = launch("noaa-down", time: Self.darkNight)

        let headline = app.element("chanceHeadline")
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
        XCTAssertEqual(headline.value as? String, "Moderate, Some activity")
        XCTAssertTrue(app.element("outlookUnavailable").waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("soonLine").exists)
        app.buttons["detailsToggle"].tap()
        let solarWind = app.element("solarWindDetail")
        XCTAssertTrue(solarWind.waitForExistence(timeout: 5))
        XCTAssertTrue(solarWind.label.contains("Solar wind data unavailable"), solarWind.label)
    }

    // MARK: Outlook (US3)

    @MainActor
    func testStormWatchRaisesTonight() throws {
        let app = launch("storm", time: Self.darkNight)

        let tonight = app.element("outlookTonight")
        XCTAssertTrue(tonight.waitForExistence(timeout: 15))
        XCTAssertEqual(tonight.label, "Forecast for tonight: High, Geomagnetic storm watch")
    }

    @MainActor
    func testSummerIsTooLightForBothNights() throws {
        let app = launch("summer", time: "2026-06-21T12:00:00Z")

        let tonight = app.element("outlookTonight")
        XCTAssertTrue(tonight.waitForExistence(timeout: 15))
        XCTAssertEqual(tonight.label, "Forecast for tonight: None, Too light")
        XCTAssertEqual(app.element("outlookTomorrow").label, "Forecast for tomorrow night: None, Too light")
    }

    @MainActor
    func testNoaaDownShowsOutlookUnavailable() throws {
        let app = launch("noaa-down", time: Self.darkNight)

        XCTAssertTrue(app.element("outlookUnavailable").waitForExistence(timeout: 15))
        XCTAssertTrue(app.element("chanceHeadline").exists)
        XCTAssertFalse(app.element("outlookTonight").exists)
    }

    @MainActor
    func testOutlookDetailsOpen() throws {
        let app = launch("storm", time: Self.darkNight)

        let section = app.element("outlookSection")
        XCTAssertTrue(section.waitForExistence(timeout: 15))
        section.tap()
        XCTAssertTrue(app.staticTexts["This is a forecast, not a measurement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["G2 (moderate)"].exists)
    }

    /// A stubbed run, then a relaunch with every request failing: the outlook comes from cache.
    @MainActor
    func testOfflineRelaunchShowsTheCachedOutlook() throws {
        let first = launch("storm", time: Self.darkNight)
        XCTAssertTrue(first.element("outlookTonight").waitForExistence(timeout: 15))
        first.terminate()

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestOffline", "-uiTestTime", Self.darkNight, "-uiTestLocation", Self.oulu,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_FI",
        ]
        app.launch()
        let tonight = app.element("outlookTonight")
        XCTAssertTrue(tonight.waitForExistence(timeout: 15))
        XCTAssertEqual(tonight.label, "Forecast for tonight: High, Geomagnetic storm watch")
    }
}
