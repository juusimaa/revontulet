import XCTest

/// Main screen with synthetic FMI data (`-uiTestStubs`) and a fixed location.
final class MainScreenResultUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(location: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStubs", "-uiTestResetCache", "-uiTestLocation", location, "-AppleLanguages", "(en)", "-AppleLocale", "en_FI"]
        app.launch()
        return app
    }

    @MainActor
    func testRovaniemiShowsResult() throws {
        let app = launch(location: "66.50,25.73")

        let headline = app.element("chanceHeadline").firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
        XCTAssertEqual(headline.label, "Chance to see the aurora")
        let value = try XCTUnwrap(headline.value as? String)
        XCTAssertTrue(["None", "Low", "Moderate", "High"].contains { value.hasPrefix($0 + ", ") }, value)

        XCTAssertTrue(app.element("placeName").label.contains("Rovaniemi"))
        let station = app.element("station").firstMatch
        XCTAssertTrue(station.exists)
        XCTAssertTrue(station.label.contains("Ranua"), station.label)
        XCTAssertTrue(station.label.contains("km"), station.label)
        let age = app.element("dataAge").firstMatch
        XCTAssertTrue(age.exists)
        XCTAssertTrue(age.label.hasPrefix("Measured"), age.label)

        app.buttons["detailsToggle"].tap()
        // The licence is written with non-breaking spaces so it never wraps mid-name.
        let attribution = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finnish Meteorological Institute (FMI), CC\u{00A0}BY\u{00A0}4.0"))
            .firstMatch
        XCTAssertTrue(attribution.waitForExistence(timeout: 5))
        XCTAssertTrue(attribution.label.contains("Statistics Finland, CC\u{00A0}BY\u{00A0}4.0"), attribution.label)
    }

    @MainActor
    func testStockholmIsOutsideCoverage() {
        let app = launch(location: "59.33,18.07")

        XCTAssertTrue(app.staticTexts["Outside coverage area"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.element("chanceHeadline").exists)
    }
}

extension XCUIApplication {
    /// Any element with the accessibility identifier, whatever its type.
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }
}
