import XCTest

final class StandaloneSettingsUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.clozach.unimagic")
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testConsentPersistenceCheckAndStableGeometry() {
        app.launch()
        XCTAssertTrue(app.buttons["category-settings"].waitForExistence(timeout: 10))
        capture("standalone-picker")
        app.buttons["category-settings"].tap()
        let consent = app.switches["paired-mac-updates"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(consent.value as? String, "0", "A fresh installation leaves updates off")
        let version = app.staticTexts["settings-version"]
        XCTAssertTrue(version.label.contains("1.0.0") && version.label.contains("1"))
        capture("settings-off")
        let check = app.buttons["paired-mac-check"], before = check.frame
        consent.tap()
        XCTAssertTrue(wait { consent.value as? String == "1" })
        XCTAssertEqual(check.frame.minY, before.minY, accuracy: 1, "Status changes preserve the check button's position")
        capture("settings-on")
        app.terminate(); app.launch(); app.buttons["category-settings"].tap()
        XCTAssertEqual(consent.value as? String, "1", "The app owns a durable update choice")
        consent.tap()
        check.tap()
        XCTAssertEqual(consent.value as? String, "0", "Checking is not automatic-update consent")
        XCTAssertTrue(app.staticTexts["paired-mac-status"].label.contains("Check requested"))
        XCTAssertEqual(check.frame.minY, before.minY, accuracy: 1)
        capture("settings-manual-check")
    }
    func testCategoryArtworkAndVisibilityRemainAvailable() {
        app.launch()
        XCTAssertTrue(app.buttons["category-settings"].waitForExistence(timeout: 10))
        app.buttons["category-settings"].tap()
        let filter = app.textFields["category-filter"]
        filter.tap(); filter.typeText("Musical Symbols\n")
        app.swipeUp()
        let toggle = app.switches["category-enabled-unichar:Category-MusicalSymbols"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
        let old = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, old)
        toggle.tap()
        capture("category-artwork")
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
