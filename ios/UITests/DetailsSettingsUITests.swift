import XCTest

final class DetailsSettingsUITests: XCTestCase {
    private static let bundleID = ProcessInfo.processInfo.environment["UNIMAGIC_TEST_APP_BUNDLE"] ?? "com.clozach.unimagic"
    private let app = XCUIApplication(bundleIdentifier: bundleID)
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testDetailActionsAndCustomFontReset() {
        launchPicker()
        searchForCopyright()
        XCTAssertFalse(app.buttons["Details mode"].exists)
        let glyph = app.buttons["glyph-00A9"].firstMatch
        XCTAssertTrue(glyph.waitForExistence(timeout: 10))
        let statusBefore = app.staticTexts["glyph-status"].label
        glyph.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["glyph-show-in-category"].waitForExistence(timeout: 8), app.debugDescription)
        capture("after-character-details")
        let encodings = app.staticTexts["Encodings"].firstMatch
        let encodingsY = encodings.isHittable ? encodings.frame.minY : nil
        app.buttons["glyph-use-category-symbol"].tap()
        let destinationSearch = app.textFields["category-filter"]
        XCTAssertTrue(destinationSearch.waitForExistence(timeout: 5), app.debugDescription)
        destinationSearch.tap(); destinationSearch.typeText("Musical Symbols")
        let customID = "unichar:Category-MusicalSymbols"
        let target = app.buttons["category-destination-" + customID]
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["category-destination-block:Musical Symbols"].exists, "Duplicate titles need separate source destinations")
        capture("after-symbol-destination-sources")
        target.tap()
        let reset = app.buttons["category-reset-" + customID]
        XCTAssertTrue(wait { reset.exists && reset.isEnabled }, app.debugDescription)
        if let encodingsY, encodings.isHittable {
            XCTAssertEqual(encodings.frame.minY, encodingsY, accuracy: 1, "Changing the symbol keeps neighboring detail rows fixed")
        }
        capture("after-custom-font-reset-label")
        app.navigationBars["Character"].buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["glyph-status"].label, statusBefore, "Long press and symbol assignment must not pick a character")
        glyph.tap()
        XCTAssertTrue(wait { self.app.staticTexts["glyph-status"].label.contains("Copied") }, "The accessibility center of the glyph button must pick")
        app.buttons["category-settings"].tap()
        filterCategories("Musical Symbols")
        let symbolSettings = app.buttons["category-symbol-settings-" + customID]
        XCTAssertTrue(symbolSettings.waitForExistence(timeout: 5), app.debugDescription)
        symbolSettings.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(reset.isEnabled)
        capture("after-category-symbol-settings")
        reset.tap()
        XCTAssertTrue(wait { !reset.isEnabled }, app.debugDescription)
        capture("after-category-default-restored")
    }

    func testVisibilityPersistenceAndSourceLabels() {
        launchPicker()
        app.buttons["category-settings"].tap()
        filterCategories("Musical Symbols")
        let toggle = app.switches["category-enabled-block:Musical Symbols"]
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UniChar sample")).firstMatch.exists)
        reveal(toggle, in: app.collectionViews["category-settings-list"])
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unicode block")).firstMatch.exists)
        let old = toggle.value as? String
        toggle.tap()
        XCTAssertTrue(wait { toggle.value as? String != old })
        let changed = toggle.value as? String
        capture("after-category-visibility-sources")
        app.terminate(); launchPicker()
        app.buttons["category-settings"].tap()
        filterCategories("Musical Symbols")
        reveal(toggle, in: app.collectionViews["category-settings-list"])
        XCTAssertEqual(toggle.value as? String, changed, "Visibility survives restart")
        toggle.tap()
        XCTAssertTrue(wait { toggle.value as? String == old })
    }

    func testShowInHiddenCategoryAndHelpRoute() {
        launchPicker()
        app.buttons["category-settings"].tap()
        filterCategories("Miscellaneous Technical")
        let visibility = app.switches["category-enabled-block:Miscellaneous Technical"]
        if visibility.value as? String == "1" { visibility.tap() }
        XCTAssertTrue(wait { visibility.value as? String == "0" })
        app.buttons["category-settings-done"].tap()
        searchFor("U+2308")
        app.buttons["glyph-2308"].firstMatch.press(forDuration: 0.7)
        let show = app.buttons["glyph-show-in-category"]
        XCTAssertTrue(show.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(wait { show.isEnabled })
        show.tap()
        filterCategories("Miscellaneous Technical")
        let destination = app.buttons["category-destination-block:Miscellaneous Technical"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), app.debugDescription)
        capture("after-context-destination")
        destination.tap()
        XCTAssertTrue(wait { !self.app.buttons["glyph-show-in-category"].exists })
        XCTAssertTrue(app.buttons["glyph-2308"].firstMatch.waitForExistence(timeout: 10))
        capture("after-hidden-category-context")
        app.buttons["app-context-back"].tap()
        XCTAssertTrue(wait { self.app.textFields["glyph-search"].value as? String == "U+2308" })
        app.buttons["Help"].tap()
        capture("after-help")
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        for _ in 0..<5 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.exists, app.debugDescription)
        capture("after-help-keyboard-route")
    }

    func testNonprintingAndWideCategorySymbols() {
        for (query, glyphID, name) in [("U+0305", "0305", "combining"), ("d㏖", "0064 33D6", "wide"), ("U+0020", "0020", "space")] {
            launchPicker()
            searchFor(query)
            let glyph = app.buttons["glyph-" + glyphID].firstMatch
            XCTAssertTrue(glyph.waitForExistence(timeout: 10), app.debugDescription)
            glyph.press(forDuration: 0.7)
            let use = app.buttons["glyph-use-category-symbol"]
            XCTAssertTrue(use.waitForExistence(timeout: 8), app.debugDescription)
            use.tap()
            filterCategories("Runic")
            app.buttons["category-destination-block:Runic"].tap()
            let reset = app.buttons["category-reset-block:Runic"]
            XCTAssertTrue(wait { reset.exists && reset.isEnabled })
            app.navigationBars["Character"].buttons["Done"].tap()
            app.buttons["category-settings"].tap()
            filterCategories("Runic")
            app.buttons["category-symbol-settings-block:Runic"].tap()
            capture("category-exemplar-" + name)
            reset.tap()
            XCTAssertTrue(wait { !reset.isEnabled })
        }
    }

    private func launchPicker() {
        app.launchArguments = Self.bundleID == "com.clozach.amaanah.alerts" ? ["--show-unimagic"] : []
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        XCTAssertTrue(app.buttons["category-settings"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func searchForCopyright() {
        searchFor("©")
    }
    private func searchFor(_ term: String) {
        let search = app.textFields["glyph-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if app.buttons["keyboard-search"].waitForExistence(timeout: 1) {
            app.buttons["Next keyboard"].firstMatch.press(forDuration: 1)
            app.cells["English (US)"].tap()
        }
        if app.buttons["Clear search"].isEnabled { app.buttons["Clear search"].tap() }
        search.typeText(term + "\n")
    }
    private func filterCategories(_ term: String) {
        let search = app.textFields["category-filter"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap(); search.typeText(term + "\n")
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
    }
    private func reveal(_ element: XCUIElement, in container: XCUIElement) {
        for _ in 0..<5 where !element.exists || !element.isHittable {
            if container.exists { container.swipeUp() } else { app.swipeUp() }
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
