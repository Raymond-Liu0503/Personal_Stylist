import XCTest

@MainActor final class StylistUITests: XCTestCase {
    private func openApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (scenario.map { [$0] } ?? [])
        app.launch()
        return app
    }
    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertTrue(app.buttons["captureOutfit"].waitForExistence(timeout: 5))
    }
    private func analyze(_ app: XCUIApplication) {
        let photo = app.buttons["testPhoto"]; reveal(photo, in: app); photo.tap()
        let analyze = app.buttons["analyzeOutfit"]; XCTAssertTrue(analyze.waitForExistence(timeout: 5)); reveal(analyze, in: app); analyze.tap()
    }
    func testConsentAnalysisSaveHistoryAndPreferences() {
        let app = openApp(); signIn(app)
        snapshot("Camera home", app: app)
        app.buttons["testPhoto"].tap()
        XCTAssertTrue(app.buttons["analyzeOutfit"].waitForExistence(timeout: 5))
        snapshot("Photo review", app: app)
        app.buttons["analyzeOutfit"].tap()
        let save = app.buttons["Save report"]; XCTAssertTrue(save.waitForExistence(timeout: 5)); snapshot("Results", app: app); reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 5))
        let saved = app.buttons["Saved reports"]; reveal(saved, in: app); saved.tap()
        XCTAssertTrue(app.staticTexts["Saved reports."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A balanced outfit with a clear, relaxed direction."].exists)
        app.buttons["Done"].tap()
        app.buttons["Close"].tap()
        app.buttons["Account"].tap()
        let style = app.textFields["Preferred style"]; reveal(style, in: app); style.tap(); style.typeText("Relaxed\n")
        let savePreferences = app.buttons["Save preferences"]; reveal(savePreferences, in: app); savePreferences.tap()
        XCTAssertTrue(app.staticTexts["Preferences saved."].waitForExistence(timeout: 5))
    }
    func testRetakeOffersGuidanceWithoutSave() {
        let app = openApp(scenario: "--retake"); signIn(app); analyze(app)
        XCTAssertTrue(app.staticTexts["Find even light and try again."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save report"].exists)
        XCTAssertTrue(app.buttons["Retake"].exists)
    }
    func testPartialReportCanBeSaved() {
        let app = openApp(scenario: "--partial"); signIn(app); analyze(app)
        XCTAssertTrue(app.staticTexts["Partial assessment · some details could not be assessed."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save report"].exists)
    }
    func testMalformedResponseShowsExplicitRetry() {
        let app = openApp(scenario: "--invalid-output"); signIn(app); analyze(app)
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save report"].exists)
    }
    func testReviewRetakePreservesQuestionAndDoesNotAnalyzeAutomatically() {
        let app = openApp(); signIn(app)
        app.buttons["testPhoto"].tap()
        XCTAssertTrue(app.buttons["analyzeOutfit"].waitForExistence(timeout: 5))
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Styling options")).firstMatch
        reveal(options, in: app); options.tap()
        let question = app.textFields["Optional outfit question"]
        reveal(question, in: app); question.tap(); question.typeText("Keep my shoes")
        app.swipeDown()
        let retake = app.buttons["Retake"]
        for _ in 0..<5 { if retake.isHittable { break }; app.swipeDown() }
        retake.tap()
        XCTAssertTrue(app.buttons["captureOutfit"].waitForExistence(timeout: 5))
        app.buttons["testPhoto"].tap()
        XCTAssertTrue(app.buttons["analyzeOutfit"].waitForExistence(timeout: 5))
        reveal(options, in: app); options.tap()
        XCTAssertEqual(question.value as? String, "Keep my shoes")
        XCTAssertFalse(app.buttons["Save report"].exists)
    }
    func testCancelSlowAnalysisReturnsToCamera() {
        let app = openApp(scenario: "--slow-analysis"); signIn(app); analyze(app)
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["captureOutfit"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save report"].exists)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Your account."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["captureOutfit"].waitForExistence(timeout: 5))
    }

    func testLargeTextKeepsPrimaryActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); signIn(app)
        XCTAssertTrue(app.buttons["Account"].isHittable)
        XCTAssertTrue(app.buttons["Choose photo"].isHittable)
        snapshot("Camera with large text", app: app)
        app.buttons["testPhoto"].tap()
        let analyze = app.buttons["analyzeOutfit"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        XCTAssertTrue(analyze.isHittable)
        snapshot("Review with large text", app: app)
        analyze.tap()
        let save = app.buttons["Save report"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        snapshot("Results with large text", app: app)
    }

    func testDismissingPhotoLibraryReturnsToCamera() {
        let app = openApp(); signIn(app)
        app.buttons["Choose photo"].tap()
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        else {
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        }
        XCTAssertTrue(app.buttons["captureOutfit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose photo"].isHittable)
        XCTAssertFalse(app.buttons["analyzeOutfit"].exists)
    }

}
