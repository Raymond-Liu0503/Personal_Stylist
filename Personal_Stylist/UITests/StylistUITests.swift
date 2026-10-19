import XCTest

@MainActor final class StylistUITests: XCTestCase {
    private func openApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (scenario.map { [$0] } ?? [])
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { break }; app.swipeUp() }
    }
    private func signIn(_ app: XCUIApplication) {
        let adult = app.switches["adultConsent"]
        XCTAssertTrue(adult.waitForExistence(timeout: 5)); reveal(adult, in: app); adult.tap()
        let consent = app.switches["processingConsent"]; reveal(consent, in: app); consent.tap()
        let local = app.buttons["Local test login"]; reveal(local, in: app); local.tap()
        let email = app.textFields["testEmail"]; reveal(email, in: app); email.tap(); email.typeText("test@example.com")
        let password = app.secureTextFields["testPassword"]; password.tap(); password.typeText("test-password\n")
        let login = app.buttons["Sign in to local backend"]; reveal(login, in: app); login.tap()
        XCTAssertTrue(app.buttons["Take a photo"].waitForExistence(timeout: 5))
    }
    private func analyze(_ app: XCUIApplication) {
        let photo = app.buttons["testPhoto"]; reveal(photo, in: app); photo.tap()
        let analyze = app.buttons["Analyse outfit"]; XCTAssertTrue(analyze.waitForExistence(timeout: 5)); reveal(analyze, in: app); analyze.tap()
    }
    func testConsentAnalysisSaveHistoryAndPreferences() {
        let app = openApp(); signIn(app); analyze(app)
        let save = app.buttons["Save report"]; XCTAssertTrue(save.waitForExistence(timeout: 5)); reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons["Saved to history"].waitForExistence(timeout: 5))
        let saved = app.buttons["Saved reports"]; reveal(saved, in: app); saved.tap()
        XCTAssertTrue(app.staticTexts["Saved reports."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A balanced outfit with a clear, relaxed direction."].exists)
        app.tabBars.buttons["Account"].tap()
        let style = app.textFields["Preferred style"]; reveal(style, in: app); style.tap(); style.typeText("Relaxed\n")
        let savePreferences = app.buttons["Save preferences"]; reveal(savePreferences, in: app); savePreferences.tap()
        XCTAssertTrue(app.staticTexts["Preferences saved."].waitForExistence(timeout: 5))
    }
    func testRetakeOffersGuidanceWithoutSave() {
        let app = openApp(scenario: "--retake"); signIn(app); analyze(app)
        XCTAssertTrue(app.staticTexts["Find even light and try again."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save report"].exists)
        XCTAssertTrue(app.buttons["Retake this outfit"].exists)
    }
    func testPartialReportCanBeSaved() {
        let app = openApp(scenario: "--partial"); signIn(app); analyze(app)
        XCTAssertTrue(app.staticTexts["Partial assessment · some details could not be assessed."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save report"].exists)
    }
    func testMalformedResponseShowsExplicitRetry() {
        let app = openApp(scenario: "--invalid-output"); signIn(app); analyze(app)
        XCTAssertTrue(app.buttons["Start a new analysis (uses allowance)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save report"].exists)
    }
}
