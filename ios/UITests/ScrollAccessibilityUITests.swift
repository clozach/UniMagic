import XCTest

final class ScrollAccessibilityUITests: XCTestCase {
    func testAccessibilityFollowsTheVisibleRowsThroughAFlick() {
        let app = XCUIApplication(bundleIdentifier: "com.clozach.unimagic")
        app.launch()
        let prompt = app.buttons["Continue"]
        if prompt.waitForExistence(timeout: 1) { prompt.tap() }
        let table = app.tables["glyph-results"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        app.buttons["browse-category"].tap()
        app.buttons["browse-set:Emojis"].tap()
        let glyphs = table.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'glyph-'"))
        let before = glyphs.allElementsBoundByIndex.map(\.identifier)
        XCTAssertFalse(before.isEmpty)
        XCTAssertLessThan(before.count, 240, "The accessibility tree contains the visible glyph rows")
        table.swipeUp()
        XCTAssertTrue(glyphs.firstMatch.waitForExistence(timeout: 5))
        let after = glyphs.allElementsBoundByIndex.map(\.identifier)
        XCTAssertFalse(after.isEmpty)
        XCTAssertNotEqual(before, after)
        XCTAssertLessThan(after.count, 240)
    }
}
