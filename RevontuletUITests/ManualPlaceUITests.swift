import XCTest

/// Without location access the user chooses a municipality; the choice survives a relaunch.
final class ManualPlaceUITests: XCTestCase {
    private static let rovaniemi = "66.50,25.73"
    private static let language = ["-AppleLanguages", "(en)", "-AppleLocale", "en_FI"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testChooseMunicipalityWithoutLocation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStubs", "-uiTestResetCache", "-uiTestLocationDenied"] + Self.language
        app.launch()

        // Location denied: the screen explains it and offers a municipality.
        XCTAssertTrue(app.element("locationDenied").waitForExistence(timeout: 15))
        app.buttons["chooseMunicipalityButton"].tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Utsj")
        let utsjoki = app.buttons["municipality-890"]
        XCTAssertTrue(utsjoki.waitForExistence(timeout: 5))
        utsjoki.tap()

        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))
        let place = app.element("placeName")
        XCTAssertTrue(place.label.contains("Utsjoki"), place.label)
        XCTAssertTrue(place.label.contains("Chosen manually"), place.label)
        app.terminate()

        // Relaunch with a location available: the chosen municipality is still used.
        app.launchArguments = ["-uiTestStubs", "-uiTestLocation", Self.rovaniemi] + Self.language
        app.launch()
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))
        XCTAssertTrue(app.element("placeName").label.contains("Utsjoki"), app.element("placeName").label)

        // Back to the current location.
        app.buttons["changePlaceButton"].tap()
        let current = app.buttons["useCurrentLocation"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.tap()
        let rovaniemi = app.element("placeName")
        XCTAssertTrue(rovaniemi.waitForLabel(containing: "Rovaniemi", timeout: 15), rovaniemi.label)
        XCTAssertTrue(rovaniemi.label.contains("Current location"), rovaniemi.label)
    }

    @MainActor
    func testOutsideCoverageOffersMunicipality() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStubs", "-uiTestResetCache", "-uiTestLocation", "59.33,18.07"] + Self.language
        app.launch()

        XCTAssertTrue(app.element("outsideCoverage").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["chooseMunicipalityButton"].exists)
    }
}

extension XCUIElement {
    /// Waits until the element's label contains `text`.
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
