import XCTest

/// The last result survives a relaunch and is shown, marked outdated, when FMI cannot be reached.
final class MainScreenOfflineUITests: XCTestCase {
    private static let rovaniemi = "66.50,25.73"
    private static let language = ["-AppleLanguages", "(en)", "-AppleLocale", "en_FI"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testRelaunchOfflineShowsCachedResult() throws {
        // First launch online: a result is computed and stored.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStubs", "-uiTestResetCache", "-uiTestLocation", Self.rovaniemi] + Self.language
        app.launch()
        let headline = app.element("chanceHeadline")
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
        let onlineValue = try XCTUnwrap(headline.value as? String)
        XCTAssertFalse(app.element("outdatedBadge").exists)
        app.terminate()

        // Relaunch with every request failing.
        app.launchArguments = ["-uiTestOffline", "-uiTestLocation", Self.rovaniemi] + Self.language
        app.launch()
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("offlineMessage").waitForExistence(timeout: 15))
        XCTAssertTrue(app.element("outdatedBadge").exists)
        XCTAssertTrue(app.element("placeName").label.contains("Rovaniemi"))
        XCTAssertTrue(app.buttons["retryButton"].exists)

        // Same level and reason as before, now announced as outdated.
        let offlineValue = try XCTUnwrap(app.element("chanceHeadline").value as? String)
        XCTAssertEqual(offlineValue, onlineValue + ", outdated")
    }

    @MainActor
    func testFirstLaunchOfflineOffersRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestOffline", "-uiTestResetCache", "-uiTestLocation", Self.rovaniemi] + Self.language
        app.launch()

        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["retryButton"].exists)
        XCTAssertFalse(app.element("chanceHeadline").exists)
    }
}
