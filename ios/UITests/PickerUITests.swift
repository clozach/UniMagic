import XCTest
import UIKit

final class PickerUITests: XCTestCase {
    static let bundleID = ProcessInfo.processInfo.environment["UNIMAGIC_TEST_APP_BUNDLE"] ?? "com.clozach.unimagic"
    let app = XCUIApplication(bundleIdentifier: PickerUITests.bundleID)
    var hosted: Bool { Self.bundleID == "com.clozach.amaanah.alerts" }
    var containerName: String { hosted ? "PowWorm!" : "Unimagic" }
    var keyboardName: String { hosted ? "UniMagic — PowWorm!, English" : "Unimagic, English" }
    override func setUp() { super.setUp(); continueAfterFailure = false }

    /// Search in the app while its own extension is selected, rather than replacing it with English.
    func testOwnKeyboardKeepsAppResultsVisible() {
        launchPicker()
        let search = app.textFields["glyph-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        if !app.buttons["keyboard-search"].exists {
            app.buttons["Next keyboard"].firstMatch.press(forDuration: 1)
            XCTAssertTrue(app.cells[keyboardName].waitForExistence(timeout: 5), app.debugDescription)
            app.cells[keyboardName].tap()
        }
        XCTAssertTrue(app.buttons["keyboard-search"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["keyboard-browse"].tap()
        let table = app.tables["glyph-results"]
        XCTAssertTrue(table.waitForExistence(timeout: 10), app.debugDescription)
        let browseHeight = table.frame.height
        let browseInk = tableInkRange(table)
        capture("own-keyboard-app-browse")
        app.buttons["keyboard-search"].tap()
        for key in ["h", "e", "a"] { app.buttons[key].tap() }
        let heart = keyboardResults.buttons["glyph-2764"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(heart.isHittable, "Compacting the keyboard must retain a tappable suggestion")
        let searchHeight = table.frame.height
        let searchInk = tableInkRange(table)
        capture("own-keyboard-app-search")
        let geometry = XCTAttachment(string: "browseTable=\(browseHeight), searchTable=\(searchHeight), browseInk=\(browseInk), searchInk=\(searchInk), table=\(table.frame), search=\(search.frame), extensionSearch=\(app.buttons["keyboard-search"].frame)\n" + app.debugDescription)
        geometry.name = "own-keyboard-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        XCTAssertGreaterThanOrEqual(browseHeight, 104, "The host needs a usable glyph browsing area")
        XCTAssertGreaterThanOrEqual(searchHeight, 104, "Opening the extension's query keys must preserve app results")
        XCTAssertGreaterThan(browseInk, 60, "The app table must paint its glyphs, beyond reporting a nonzero frame")
        XCTAssertGreaterThan(searchInk, 60, "The app table must remain painted while the extension searches")
        heart.tap()
        XCTAssertTrue(wait { (search.value as? String)?.unicodeScalars.contains { $0.value == 0x2764 } == true })
        XCTAssertTrue(table.buttons["glyph-2764"].waitForExistence(timeout: 10), app.debugDescription)
        capture("own-keyboard-app-results")
        app.buttons["Clear search"].firstMatch.tap()
        table.swipeUp()
        XCTAssertTrue(wait { !self.app.buttons["keyboard-search"].exists })
        XCTAssertTrue(table.cells.allElementsBoundByIndex.contains { $0.isHittable })
        capture("own-keyboard-app-vertical-scroll")
    }

    /// Sample an actual hittable glyph, excluding headers and the independently painted side index.
    private func tableInkRange(_ table: XCUIElement) -> Int {
        guard let glyph = table.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "glyph-"))
            .allElementsBoundByIndex.first(where: { $0.isHittable }) else { return 0 }
        let shot = app.screenshot().image
        let scale = CGFloat(shot.cgImage?.width ?? 0) / app.frame.width
        let region = glyph.frame.intersection(table.frame)
        guard !region.isNull, region.width > 0, region.height > 0 else { return 0 }
        let crop = CGRect(x: region.minX * scale, y: region.minY * scale,
                          width: region.width * scale, height: region.height * scale)
        guard let image = shot.cgImage?.cropping(to: crop) else { return 0 }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let brightness = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2]) }
        return ((brightness.max() ?? 0) - (brightness.min() ?? 0)) / 3
    }

    func testFloatingChooserAndLiveSearch() {
        launchPicker()
        useSystemKeyboard()
        let search = app.textFields["glyph-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        chooseAppCategory("unichar:Category-LetterlikeSymbolsAll", matching: "Letterlike")
        XCTAssertTrue(app.tables["glyph-results"].buttons["glyph-00A9"].waitForExistence(timeout: 10))
        capture("browse-after")
        search.tap()
        for prefix in ["h", "he", "hea"] {
            search.typeText(String(prefix.last!))
            XCTAssertTrue(wait { search.value as? String == prefix })
        }
        XCTAssertTrue(app.tables["glyph-results"].buttons["glyph-2764"].waitForExistence(timeout: 10), app.debugDescription)
        capture("live-search-after")
        app.buttons["Clear search"].tap()
        XCTAssertTrue(wait { search.value as? String == "Search characters" || search.value as? String == "" })
        XCTAssertTrue(app.keyboards.count > 0, "Exercise category choice from focused search")
        chooseAppCategory("unichar:Category-EnclosedCharacters", matching: "Enclosed")
        XCTAssertTrue(wait { self.app.keyboards.count == 0 }, app.debugDescription)
        XCTAssertTrue(app.tables["glyph-results"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "glyph-")).allElementsBoundByIndex.contains { $0.isHittable })
        capture("floating-category-from-focused-search")
    }

    func testRecentsUpdatesOnReturn() {
        launchPicker()
        useSystemKeyboard()
        let search = app.textFields["glyph-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("hea")
        let heart = app.tables["glyph-results"].buttons["glyph-2764"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        heart.tap()
        app.buttons["Clear search"].tap()
        chooseAppCategory("utility:recents", matching: "Recents")
        XCTAssertTrue(wait {
            self.app.tables["glyph-results"].buttons.matching(identifier: "glyph-2764").allElementsBoundByIndex.contains { $0.isHittable }
        }, app.debugDescription)
        capture("app-recents-new-pick")
    }

    func testBrowseBeyondFirstHundred() {
        launchPicker()
        useSystemKeyboard()
        chooseAppCategory("unichar:Category-LetterlikeSymbolsAll", matching: "Letterlike")
        let table = app.tables["glyph-results"]
        let pageTwo = table.buttons["glyph-339D"] // Inventory position100, after the former More boundary.
        for _ in 0..<20 where !pageTwo.isHittable {
            table.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35)))
        }
        XCTAssertTrue(pageTwo.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "more-")).firstMatch.exists)
        capture("continuous-browse-page-two")
    }

    func testEnableKeyboard() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if settings.buttons["Cancel"].exists { settings.buttons["Cancel"].tap() }
        for _ in 0..<4 where !settings.buttons["General"].exists { settings.navigationBars.buttons.firstMatch.tap() }
        settings.buttons["General"].tap()
        let keyboard = settings.buttons["Keyboard"]
        for _ in 0..<5 where !keyboard.isHittable { settings.swipeUp() }
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), settings.debugDescription)
        keyboard.tap()
        settings.buttons["KEYBOARDS"].tap()
        if settings.cells[Self.bundleID + ".keyboard"].exists { return }
        XCTAssertTrue(settings.buttons["AddNewKeyboard"].waitForExistence(timeout: 5), settings.debugDescription)
        settings.buttons["AddNewKeyboard"].tap()
        XCTAssertTrue(settings.cells[containerName].waitForExistence(timeout: 5), settings.debugDescription)
        settings.cells[containerName].tap()
    }

    func testKeyboardSearchAndInsert() {
        launchPicker()
        XCTAssertTrue(app.buttons["Help"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Help"].firstMatch.tap()
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        for _ in 0..<5 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        if !app.buttons["keyboard-search"].exists {
            app.buttons["Next keyboard"].press(forDuration: 1)
            XCTAssertTrue(app.cells[keyboardName].waitForExistence(timeout: 5), app.debugDescription)
            app.cells[keyboardName].tap()
        }
        XCTAssertTrue(app.buttons["keyboard-search"].waitForExistence(timeout: 30), app.debugDescription)
        chooseKeyboardCategory("unichar:Category-LetterlikeSymbolsAll", swipeLeft: false)
        capture("keyboard-browse")
        app.buttons["keyboard-search"].tap()
        for key in ["h", "e", "a"] { app.buttons[key].tap() }
        let heart = keyboardResults.buttons["glyph-2764"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(heart.isHittable, app.debugDescription)
        capture("keyboard-live-search")
        heart.tap()
        XCTAssertTrue(wait { (field.value as? String)?.unicodeScalars.contains { $0.value == 0x2764 } == true }, app.debugDescription)
        capture("keyboard-inserted")
        app.buttons["Delete search letter"].tap()
        XCTAssertTrue(app.staticTexts["he"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue((field.value as? String)?.unicodeScalars.contains { $0.value == 0x2764 } == true)
        app.buttons["Delete from your text"].tap()
        XCTAssertFalse((field.value as? String)?.unicodeScalars.contains { $0.value == 0x2764 } == true)
        chooseKeyboardCategory("unichar:Category-LetterlikeSymbolsAll", swipeLeft: false)
        XCTAssertFalse(app.buttons["Space"].exists)
        XCTAssertEqual(app.buttons["keyboard-search"].label, "Search characters")
        capture("keyboard-browse-return")
        chooseKeyboardCategory("unichar:Category-MusicalSymbols", swipeLeft: true)
        XCTAssertTrue(keyboardResults.buttons["glyph-266A"].waitForExistence(timeout: 10))
        capture("keyboard-music")
        XCTAssertTrue(keyboardResults.buttons["glyph-1D11E"].waitForExistence(timeout: 10))
        capture("keyboard-music-clef")
        // The inventory's exact insertion forms must survive canonical-ID reuse.
        chooseKeyboardCategory("unichar:Category-LetterlikeSymbolsAll", swipeLeft: false)
        keyboardResults.buttons["glyph-00A9"].tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x00A9] }, app.debugDescription)
        app.buttons["Delete from your text"].tap()
        chooseKeyboardCategory("unichar:Category-Pictographs", swipeLeft: true)
        keyboardResults.buttons["glyph-2600"].tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x2600, 0xFE0E] }, app.debugDescription)
        capture("keyboard-exact-text-presentation")
        app.buttons["Delete from your text"].tap()
        chooseKeyboardCategory("unichar:Category-MusicalSymbols", swipeLeft: true)
        keyboardResults.buttons["glyph-266A"].tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x266A] }, app.debugDescription)
        app.buttons["Delete from your text"].tap()
        app.buttons["keyboard-search"].tap()
        for key in Array("square mol").map(String.init) { app.buttons[key == " " ? "Space" : key].tap() }
        let compound = keyboardResults.buttons["glyph-0064 33D6"]
        XCTAssertTrue(compound.waitForExistence(timeout: 10), app.debugDescription)
        compound.tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x0064, 0x33D6] }, app.debugDescription)
        capture("keyboard-exact-supplement-sequence")
        app.buttons["Delete from your text"].tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x0064] }, app.debugDescription)
        app.buttons["Delete from your text"].tap()
        useSystemKeyboard()
    }

    private func scalars(_ field: XCUIElement) -> [UInt32] {
        (field.value as? String ?? "").unicodeScalars.map(\.value)
    }

    func testKeyboardCategorySelectionAndRecents() {
        launchPicker()
        XCTAssertTrue(app.buttons["Help"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Help"].firstMatch.tap()
        let field = app.descendants(matching: .any)["keyboard-test-field"].firstMatch
        for _ in 0..<5 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        if !app.buttons["keyboard-search"].exists {
            app.buttons["Next keyboard"].press(forDuration: 1)
            XCTAssertTrue(app.cells[keyboardName].waitForExistence(timeout: 5), app.debugDescription)
            app.cells[keyboardName].tap()
        }
        XCTAssertTrue(app.buttons["keyboard-search"].waitForExistence(timeout: 30), app.debugDescription)
        chooseKeyboardCategory("unichar:Category-IdeographicDescCharacters", swipeLeft: true)
        let first = keyboardResults.buttons["glyph-2FF0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10) && first.isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["category-unichar:Category-IdeographicDescCharacters"].isSelected)
        capture("keyboard-last-category")
        first.tap()
        XCTAssertTrue(wait { self.scalars(field) == [0x2FF0] }, app.debugDescription)
        chooseKeyboardCategory("utility:recents", swipeLeft: false)
        XCTAssertTrue(app.buttons["category-utility:recents"].isSelected)
        XCTAssertTrue(wait { self.keyboardResults.buttons["glyph-2FF0"].isHittable }, app.debugDescription)
        capture("keyboard-first-category-recent-pick")
        app.buttons["Delete from your text"].tap()
        useSystemKeyboard()
    }

    /// Leaves a known exact string on the real simulator clipboard for independent pbpaste readback.
    func testToneChoiceCopiesOnlySelectedVariant() {
        launchPicker()
        useSystemKeyboard()
        let search = app.textFields["glyph-search"]
        search.tap(); search.typeText("thumbs up")
        let thumb = app.tables["glyph-results"].buttons["glyph-1F44D"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 10), app.debugDescription)
        thumb.press(forDuration: 0.7)
        let tone = app.buttons["Skin tone 1"].firstMatch
        for _ in 0..<5 where !tone.isHittable { app.swipeUp() }
        XCTAssertTrue(tone.isHittable, app.debugDescription)
        tone.tap()
        capture("detail-selected-skin-tone")
        app.navigationBars["Character"].buttons["Done"].tap()
        capture("detail-skin-tone-result")
        let expected = "Copied \u{1F44D}\u{1F3FB}\u{FE0F}"
        XCTAssertTrue(wait { self.app.staticTexts["glyph-status"].label == expected }, app.debugDescription)
    }

    /// Leaves a known exact string on the real simulator clipboard for independent pbpaste readback.
    func testZExactAppCopy() {
        launchPicker()
        useSystemKeyboard()
        chooseAppCategory("unichar:Category-LetterlikeSymbolsAll", matching: "Letterlike")
        let copies = app.buttons.matching(identifier: "glyph-00A9")
        XCTAssertTrue(wait { copies.allElementsBoundByIndex.contains { $0.isHittable } }, app.debugDescription)
        copies.allElementsBoundByIndex.first { $0.isHittable }!.tap()
        XCTAssertTrue(wait { self.app.staticTexts["glyph-status"].label == "Copied ©" }, app.debugDescription)
        capture("app-copy-exact-bare-copyright")
    }

    private func launchPicker() {
        app.launchArguments = hosted ? ["--show-unimagic"] : []
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
    }

    private func chooseAppCategory(_ id: String, matching title: String) {
        let toggle = app.buttons["browse-category"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        toggle.tap()
        let list = app.descendants(matching: .any)["browse-category-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
        let filter = app.textFields["browse-category-search"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), app.debugDescription)
        filter.tap(); filter.typeText(title)
        let row = app.buttons["browse-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable, app.debugDescription)
        row.tap()
        XCTAssertTrue(wait { !list.exists }, app.debugDescription)
    }

    private var keyboardResults: XCUIElement {
        let collection = app.collectionViews["glyph-results"]
        return collection.exists ? collection : app.scrollViews["glyph-results"]
    }

    private func chooseKeyboardCategory(_ id: String, swipeLeft: Bool) {
        if !app.scrollViews["category-strip"].exists { app.buttons["keyboard-browse"].tap() }
        let target = app.buttons["category-" + id]
        let strip = app.scrollViews["category-strip"]
        func visible() -> Bool {
            target.exists && strip.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY))
        }
        for _ in 0..<8 where !visible() {
            if swipeLeft { strip.swipeLeft() } else { strip.swipeRight() }
        }
        XCTAssertTrue(visible(), app.debugDescription)
        target.tap()
    }

    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: 10) == .completed
    }

    private func useSystemKeyboard() {
        // Select the fixture keyboard explicitly; a missing extension AX subtree
        // must not be mistaken for an already-selected system keyboard.
        let next = app.buttons["Next keyboard"].firstMatch
        guard next.waitForExistence(timeout: 2) else { return }
        next.press(forDuration: 1)
        let english = app.cells["English (US)"]
        XCTAssertTrue(english.waitForExistence(timeout: 5), app.debugDescription)
        english.tap()
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
