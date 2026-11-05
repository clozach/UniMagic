import XCTest
final class RotationUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.clozach.unimagic")
    func testStandaloneRotationPreservesBrowseAndSearch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        let search = app.textFields["glyph-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let next = app.buttons["Next keyboard"].firstMatch
        if next.waitForExistence(timeout: 2) {
            next.press(forDuration: 1)
            let english = app.cells["English (US)"]
            XCTAssertTrue(english.waitForExistence(timeout: 5)); english.tap()
        }
        let table = app.tables["glyph-results"]
        table.swipeUp()
        let previousCategory = app.buttons["browse-category"].label
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait { self.app.frame.width > self.app.frame.height })
        XCTAssertTrue(table.waitForExistence(timeout: 5)); XCTAssertGreaterThan(table.frame.height, 100)
        XCTAssertTrue(wait { self.app.buttons["browse-category"].label == previousCategory }, "Rotation preserves the visible category")
        capture("standalone-landscape-browse")
        search.tap(); search.typeText("U+00A9")
        XCTAssertTrue(table.buttons["glyph-00A9"].waitForExistence(timeout: 8))
        capture("standalone-landscape-search")
        XCTAssertGreaterThanOrEqual(table.frame.height, 88, "One result row and its heading stay visible above the keyboard")
        table.buttons["glyph-00A9"].tap()
        XCTAssertTrue(app.staticTexts["Copied ©️"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait { self.app.frame.height > self.app.frame.width })
        XCTAssertTrue(app.navigationBars["Unimagic"].exists, "Portrait restores the app title")
        XCTAssertTrue(table.buttons["glyph-00A9"].isHittable)
        app.buttons["Clear search"].firstMatch.tap()
        table.swipeUp()
        XCTAssertGreaterThan(table.frame.height, 100)
        XCTAssertTrue(app.buttons["browse-category"].isHittable)
        capture("standalone-returned-portrait")
    }
    func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in predicate() },object:nil)],timeout:10) == .completed
    }
    func capture(_ name: String) {
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.name=name+"-full-screen"; screen.lifetime = .keepAlways; add(screen)
        let b = XCTAttachment(string: app.debugDescription); b.name=name+"-tree"; b.lifetime = .keepAlways; add(b)
    }
}
