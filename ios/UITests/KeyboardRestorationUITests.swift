import XCTest

final class KeyboardRestorationUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.clozach.unimagic")
    override func setUp() { continueAfterFailure = false }

    func testCaptureKeyboardBaseline() {
        enableKeyboard()
        openKeyboard()
        capture("keyboard-browse-before")
        app.buttons["keyboard-search"].tap()
        for letter in ["h", "e", "a"] { app.buttons[letter].tap() }
        XCTAssertTrue(app.buttons["glyph-2764"].waitForExistence(timeout: 10), app.debugDescription)
        capture("keyboard-search-before")
    }
    func testFixedRailAndExactSearchInsertion() {
        enableKeyboard(); openKeyboard()
        let browse = app.buttons["keyboard-browse"], search = app.buttons["keyboard-search"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5), app.debugDescription)
        let browseFrame = browse.frame, searchFrame = search.frame
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        let original = field.value as? String
        let snapshotStart = Date(), snapshot = app.debugDescription
        let receipt = XCTAttachment(string: "snapshotSeconds=\(Date().timeIntervalSince(snapshotStart))\n" + snapshot)
        receipt.name = "keyboard-accessibility-viewport"; receipt.lifetime = .keepAlways; add(receipt)
        capture("keyboard-browse-after")
        let emojis = app.buttons["category-set:Emojis"], spaces = app.buttons["category-set:Spaces"]
        if emojis.isHittable && spaces.isHittable {
            let before = emojis.frame; spaces.tap()
            XCTAssertEqual(emojis.frame, before, "Category target keeps its full size when selection changes")
            emojis.tap()
        }
        search.tap()
        for letter in ["h", "e", "a"] { app.buttons[letter].tap() }
        let results = app.scrollViews["glyph-results"].firstMatch
        let heart = results.buttons["glyph-2764"].firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(field.value as? String, original, "Query keys leave the source document unchanged")
        XCTAssertEqual(browse.frame, browseFrame); XCTAssertEqual(search.frame, searchFrame)
        app.buttons["Delete search letter"].tap()
        XCTAssertEqual(field.value as? String, original)
        app.buttons["keyboard-clear-search"].tap()
        for letter in Array("polar bear").map(String.init) { app.buttons[letter == " " ? "Space" : letter].tap() }
        let bear = results.buttons["glyph-1F43B 200D 2744"].firstMatch
        XCTAssertTrue(bear.waitForExistence(timeout: 10), app.debugDescription); bear.tap()
        XCTAssertEqual((field.value as? String ?? "").unicodeScalars.map(\.value), [0x1F43B, 0x200D, 0x2744, 0xFE0F], "Exact ZWJ insertion")
        capture("keyboard-search-after")
        browse.tap()
        XCTAssertFalse(app.buttons["Space"].exists)
        XCTAssertEqual(browse.frame, browseFrame); XCTAssertEqual(search.frame, searchFrame)
        XCTAssertTrue(app.buttons.matching(identifier: "Details mode").allElementsBoundByIndex.filter(\.isHittable).isEmpty)
    }
    func testContinuousBrowseAndHold() {
        enableKeyboard(); openKeyboard()
        let strip = app.scrollViews["category-strip"].firstMatch
        let writing = app.buttons["category-legacy:Writing"]
        for _ in 0..<6 where !writing.isHittable { strip.swipeLeft() }
        XCTAssertTrue(writing.isHittable, app.debugDescription); writing.tap()
        let browser = app.scrollViews["glyph-results"].firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 10), app.debugDescription)
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        let original = field.value as? String
        for _ in 0..<14 {
            let value = browser.value as? String ?? ""
            if value.hasPrefix("Writing, character "), let position = Int(value.components(separatedBy: "character ").last?.components(separatedBy: " of").first ?? ""), position > 110 { break }
            browser.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.05, thenDragTo: browser.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        }
        let value = browser.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("Writing, character "), value)
        let position = Int(value.components(separatedBy: "character ").last?.components(separatedBy: " of").first ?? "") ?? 0
        XCTAssertGreaterThan(position, 100, "Continuous browse loads past the first page")
        XCTAssertFalse(app.buttons["More"].isHittable)
        let glyph = browser.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "glyph-")).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(glyph, app.debugDescription)
        capture("keyboard-continuous-after")
        glyph?.press(forDuration: 0.7)
        XCTAssertTrue(app.navigationBars["Character"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(field.value as? String, original, "Hold opens details without insertion")
        capture("keyboard-hold-details-after")
    }
    private func enableKeyboard() {
        app.launch()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<6 where !settings.buttons["General"].exists { settings.navigationBars.buttons.firstMatch.tap() }
        settings.buttons["General"].tap()
        let keyboard = settings.buttons["Keyboard"]
        for _ in 0..<6 where !keyboard.isHittable { settings.swipeUp() }
        keyboard.tap(); settings.buttons["KEYBOARDS"].tap()
        if settings.cells["com.clozach.unimagic.keyboard"].exists { return }
        settings.buttons["AddNewKeyboard"].tap(); settings.cells["Unimagic"].tap()
    }
    private func openKeyboard() {
        app.launch()
        XCTAssertTrue(app.buttons["Help"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Help"].firstMatch.tap()
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        for _ in 0..<6 where !field.isHittable { app.swipeUp() }
        field.tap()
        if !app.buttons["keyboard-search"].exists {
            let globe = app.buttons.matching(NSPredicate(format: "label == %@ AND value != nil", "Next keyboard")).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), app.debugDescription)
            globe.press(forDuration: 1)
            let choice = app.cells["Unimagic, English"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription); choice.tap()
        }
        XCTAssertTrue(app.buttons["keyboard-search"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
