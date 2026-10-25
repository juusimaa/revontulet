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

    /// Launches with a zone (Oulu) and opens the alert settings.
    @MainActor
    private func openSettings(_ arguments: [String] = []) -> XCUIApplication {
        let app = launch(["-uiTestResetCache", "-uiTestLocation", "65.01,25.47"] + arguments)
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))
        app.buttons["alertsButton"].tap()
        XCTAssertTrue(app.buttons["turnOnAlerts"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testFirstTimeExplainsWhatIsSent() throws {
        let app = openSettings()

        XCTAssertTrue(app.element("alertsWhatIsSent").exists)
        XCTAssertTrue(app.staticTexts["An anonymous notification address for this iPhone"].exists)
        XCTAssertTrue(app.staticTexts["They go to the developer's alert service in Finland."].exists)
        XCTAssertTrue(app.staticTexts["Turning alerts off deletes them."].exists)
        XCTAssertTrue(app.element("privacyPolicyLink").exists)

        // Once alerts have been on, Off shows only the short description and the privacy link.
        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.buttons["turnOffAlerts"].waitForExistence(timeout: 5))
        app.buttons["turnOffAlerts"].tap()
        XCTAssertTrue(app.buttons["turnOnAlerts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("alertsWhatIsSent").exists)
        XCTAssertTrue(app.element("privacyPolicyLink").exists)
    }

    @MainActor
    func testChangeThresholdWhileOn() throws {
        let app = openSettings()
        app.buttons["turnOnAlerts"].tap()
        let confirmation = app.element("alertConfirmation")
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["threshold-high"].isSelected)

        app.buttons["threshold-moderate"].tap()

        XCTAssertTrue(app.buttons["threshold-moderate"].isSelected)
        XCTAssertFalse(app.buttons["threshold-high"].isSelected)
        XCTAssertTrue(confirmation.waitForLabel(containing: "Confirmed", timeout: 5), confirmation.label)
        XCTAssertTrue(app.element("alertsStatus").label.contains("On"), app.element("alertsStatus").label)
    }

    @MainActor
    func testTurnOffShowsOffImmediately() throws {
        let app = openSettings()
        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.buttons["turnOffAlerts"].waitForExistence(timeout: 5))

        app.buttons["turnOffAlerts"].tap()

        XCTAssertTrue(app.buttons["turnOnAlerts"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.element("alertsStatus").label.contains("Off"), app.element("alertsStatus").label)
        app.buttons["alertSettingsDone"].tap()
        let bell = app.buttons["alertsButton"]
        XCTAssertTrue(bell.waitForLabel(containing: "Aurora alerts, off", timeout: 5), bell.label)
    }

    @MainActor
    func testUnreachableServiceWaitsQuietly() throws {
        let app = openSettings(["-uiTestAlertsUnreachable"])

        app.buttons["turnOnAlerts"].tap()
        let confirmation = app.element("alertConfirmation")
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.label.contains("Waiting to confirm"), confirmation.label)
        XCTAssertTrue(app.element("alertsStatus").label.contains("On"), app.element("alertsStatus").label)
        XCTAssertEqual(app.alerts.count, 0)

        // Off at once, with the deletion still pending.
        app.buttons["turnOffAlerts"].tap()
        XCTAssertTrue(app.element("alertsRemoving").waitForExistence(timeout: 2))
        XCTAssertTrue(app.element("alertsStatus").label.contains("Off"), app.element("alertsStatus").label)
        XCTAssertEqual(app.alerts.count, 0)

        app.buttons["alertSettingsDone"].tap()
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testSendTestShowsSent() throws {
        let app = openSettings()
        app.buttons["turnOnAlerts"].tap()
        let confirmation = app.element("alertConfirmation")
        XCTAssertTrue(confirmation.waitForLabel(containing: "Confirmed", timeout: 5), confirmation.label)

        let sendTest = app.buttons["sendTestAlert"]
        XCTAssertTrue(sendTest.waitForExistence(timeout: 5))
        sendTest.tap()

        let result = app.element("sendTestResult")
        XCTAssertTrue(result.waitForLabel(containing: "Test alert sent", timeout: 5), result.label)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testSendTestRateLimitedShowsTryAgainTime() throws {
        let app = openSettings(["-uiTestAlertsTestLimited"])
        app.buttons["turnOnAlerts"].tap()
        let sendTest = app.buttons["sendTestAlert"]
        XCTAssertTrue(sendTest.waitForExistence(timeout: 5))

        sendTest.tap()

        let result = app.element("sendTestResult")
        XCTAssertTrue(result.waitForLabel(containing: "Try again at", timeout: 5), result.label)
        XCTAssertNotNil(result.label.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression), result.label)
    }

    @MainActor
    func testNoDarkNightsNoteAtMidsummerInLapland() throws {
        let app = launch(["-uiTestResetCache", "-uiTestLocation", "69.90,27.02", "-uiTestTime", "2026-06-21T20:00:00Z"])
        XCTAssertTrue(app.element("chanceHeadline").waitForExistence(timeout: 15))
        app.buttons["alertsButton"].tap()
        XCTAssertTrue(app.buttons["turnOnAlerts"].waitForExistence(timeout: 5))

        app.buttons["turnOnAlerts"].tap()

        let note = app.element("alertsNoDarkNights")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("Alerts resume when nights get dark again"), note.label)
        XCTAssertTrue(app.element("alertsStatus").label.contains("On"), app.element("alertsStatus").label)
    }

    @MainActor
    func testNoDarkNightsNoteNotShownInNovember() throws {
        let app = openSettings(["-uiTestTime", "2026-11-03T18:00:00Z"])
        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.buttons["sendTestAlert"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.element("alertsNoDarkNights").exists)
    }

    // MARK: Accessibility (Principle VI)

    @MainActor
    func testSettingsPassAccessibilityAudit() throws {
        let app = openSettings()
        continueAfterFailure = true
        try audit(app, "off, first time")

        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.buttons["sendTestAlert"].waitForExistence(timeout: 5))
        try audit(app, "on")
        app.buttons["sendTestAlert"].tap()
        XCTAssertTrue(app.element("sendTestResult").waitForLabel(containing: "Test alert sent", timeout: 5))
        try audit(app, "test sent")
    }

    @MainActor
    func testWaitingAndRemovingPassAccessibilityAudit() throws {
        let app = openSettings(["-uiTestAlertsUnreachable"])
        continueAfterFailure = true
        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.element("alertConfirmation").waitForLabel(containing: "Waiting to confirm", timeout: 5))
        try audit(app, "waiting to confirm")

        app.buttons["turnOffAlerts"].tap()
        XCTAssertTrue(app.element("alertsRemoving").waitForExistence(timeout: 2))
        try audit(app, "removing")
    }

    @MainActor
    func testNoZoneAndNoDarkNightsPassAccessibilityAudit() throws {
        continueAfterFailure = true
        let noZone = launch(["-uiTestResetCache", "-uiTestLocationDenied"])
        XCTAssertTrue(noZone.element("locationDenied").waitForExistence(timeout: 15))
        noZone.buttons["alertsButton"].tap()
        XCTAssertTrue(noZone.element("alertsNoZone").waitForExistence(timeout: 5))
        try audit(noZone, "no zone")

        let lapland = launch(["-uiTestResetCache", "-uiTestLocation", "69.90,27.02", "-uiTestTime", "2026-06-21T20:00:00Z"])
        XCTAssertTrue(lapland.element("chanceHeadline").waitForExistence(timeout: 15))
        lapland.buttons["alertsButton"].tap()
        lapland.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(lapland.element("alertsNoDarkNights").waitForExistence(timeout: 5))
        try audit(lapland, "no dark nights")
    }

    /// The bell's state is in its label and the hero's "On"/"Off" text, never only in the symbol.
    @MainActor
    func testAlertStateIsNotBySymbolAlone() throws {
        let app = openSettings()
        XCTAssertTrue(app.element("alertsStatus").label.contains("Off"), app.element("alertsStatus").label)
        app.buttons["turnOnAlerts"].tap()
        XCTAssertTrue(app.element("alertsStatus").waitForLabel(containing: "On", timeout: 5))
        app.buttons["alertSettingsDone"].tap()
        XCTAssertTrue(app.buttons["alertsButton"].waitForLabel(containing: "Aurora alerts, on", timeout: 5))
    }

    /// Contrast is left out for the same reason as on the main screen: the audit samples the
    /// moving sky behind the text. The system toolbar's Done button keeps a fixed size by design
    /// and offers the Large Content Viewer instead, so its Dynamic Type issue is expected.
    @MainActor
    private func audit(_ app: XCUIApplication, _ state: String) throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            if issue.auditType == .dynamicType, issue.element?.identifier == "alertSettingsDone" { return true }
            XCTFail("\(state): \(issue.auditType) \(issue.compactDescription) – \(issue.element?.label ?? "?")")
            return true
        }
    }
}
