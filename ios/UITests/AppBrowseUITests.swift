import XCTest
import UIKit

final class AppBrowseUITests: XCTestCase {
    static let bundleID = ProcessInfo.processInfo.environment["UNIMAGIC_TEST_APP_BUNDLE"] ?? "com.clozach.unimagic"
    let app = XCUIApplication(bundleIdentifier: AppBrowseUITests.bundleID)
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testThumbChooserStartsAtEmojiWithSearchBelowEvenAfterLateSelection() {
        continueAfterFailure = true
        launch()
        let toggle = app.buttons["browse-category"], closed = toggle.frame
        let list = app.scrollViews["browse-category-list"]
        let emoji = app.buttons["browse-set:Emojis"]
        let search = app.textFields["browse-category-search"]
        toggle.tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        capture("thumb-chooser-initial")
        XCTAssertTrue(emoji.exists && emoji.isHittable, "Emoji opens within thumb reach")
        if emoji.exists { XCTAssertEqual(emoji.frame.maxY, list.frame.maxY, accuracy: 2, "The first category is the bottom row") }
        XCTAssertGreaterThanOrEqual(search.frame.minY, list.frame.maxY, "Find category sits below the list")
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        choose("block:Cuneiform", matching: "Cuneiform")
        toggle.tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        capture("thumb-chooser-late-selection")
        XCTAssertTrue(emoji.exists && emoji.isHittable, "A late selection does not replace the bottom opening position")
        if emoji.exists { XCTAssertEqual(emoji.frame.maxY, list.frame.maxY, accuracy: 2) }
        XCTAssertGreaterThanOrEqual(search.frame.minY, list.frame.maxY)
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.05,
            thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertFalse(emoji.exists && emoji.isHittable, "Pulling down reaches categories above Emoji")
        search.tap(); search.typeText("Symbols")
        let first = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browse-")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5) && first.isHittable)
        XCTAssertTrue(wait { self.app.popovers.firstMatch.frame.contains(search.frame) && search.isHittable },
                      "The search field remains within the chooser after the keyboard resizes it")
        XCTAssertEqual(first.frame.minY, list.frame.minY, accuracy: 2, "Filtered matches start at the top")
        capture("thumb-chooser-filtered")
        first.tap()
        XCTAssertTrue(wait { !list.exists && self.app.keyboards.count == 0 })
        XCTAssertEqual(toggle.frame, closed, "Opening, filtering and choosing preserve the floater frame")
    }
    func testColdLaunchAndClearedSearchMatchVisibleCategory() {
        app.terminate()
        app.launchArguments = Self.bundleID == "com.clozach.amaanah.alerts" ? ["--show-unimagic"] : []
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        let table = app.tables["glyph-results"], toggle = app.buttons["browse-category"]
        let recents = app.otherElements["browse-header-utility:recents"].firstMatch
        XCTAssertTrue(recents.waitForExistence(timeout: 10), app.debugDescription)
        capture("app-cold-launch-category")
        XCTAssertTrue(wait { toggle.label == "Category: Recents" }, app.debugDescription)
        XCTAssertEqual(recents.frame.minY, table.frame.minY, accuracy: 2)
        choose("unichar:Category-Pictographs", matching: "Pictographs")
        XCTAssertTrue(wait { toggle.label == "Category: Pictographs" })
        let pictographs = app.otherElements["browse-header-unichar:Category-Pictographs"].firstMatch
        XCTAssertEqual(pictographs.frame.minY, table.frame.minY, accuracy: 2, "Explicit navigation keeps its landing")
        let search = app.textFields["glyph-search"]
        search.tap(); search.typeText("U+00A9")
        XCTAssertTrue(table.buttons["glyph-00A9"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Clear search"].firstMatch.tap()
        XCTAssertTrue(wait { toggle.label == "Category: Recents" }, app.debugDescription)
        XCTAssertEqual(recents.frame.minY, table.frame.minY, accuracy: 2)
        toggle.tap()
        let list = app.scrollViews["browse-category-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(wait { !list.exists && self.app.keyboards.count == 0 })
        XCTAssertEqual(toggle.label, "Category: Recents", "Keyboard dismissal preserves the visible category")
        capture("app-cleared-search-category")
    }
    func testPinnedHeaderAndFloatingChooserGeometry() {
        launch()
        let table = app.tables["glyph-results"], toggle = app.buttons["browse-category"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        let closed = toggle.frame
        XCTAssertEqual(closed.width, 64, accuracy: 1); XCTAssertEqual(closed.height, 52, accuracy: 1)
        XCTAssertEqual(closed.midX, app.frame.midX, accuracy: 1)
        XCTAssertLessThan(closed.maxY, table.frame.maxY)
        XCTAssertFalse(app.otherElements["category-index"].exists)
        choose("unichar:Category-Pictographs", matching: "Pictographs")
        XCTAssertEqual(toggle.frame, closed, "A selected exemplar must not reshape the control")
        for _ in 0..<2 { drag(table, from: 0.7, to: 0.43) }
        let header = app.otherElements["browse-header-unichar:Category-Pictographs"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(header.frame.minY, table.frame.minY, accuracy: 2, "Heading remains pinned")
        XCTAssertGreaterThan(inkRange(header.frame), 70, "Pinned header must paint readable text against its background")
        capture("app-pinned-heading-and-floater")
        toggle.tap()
        let list = app.scrollViews["browse-category-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
        let selected = app.buttons["browse-set:Emojis"]
        XCTAssertTrue(selected.isHittable, "Reopening starts at Emoji beside the thumb")
        capture("app-chooser-open-selected")
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(wait { !list.exists })
        toggle.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5) && selected.isHittable)
        let search = app.textFields["browse-category-search"]
        search.tap(); let searchWidth = search.frame.width; search.typeText("Symbols")
        XCTAssertEqual(search.frame.width, searchWidth, accuracy: 1, "The clear button reserves its width while empty")
        let rows = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browse-")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThan(rows.count, 1)
        let firstMatch = list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browse-")).firstMatch
        XCTAssertEqual(firstMatch.frame.minY, list.frame.minY, accuracy: 1, "Filtering starts at the first matching row")
        let labels = rows.compactMap { row -> CGFloat? in
            let title = row.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Symbols")).firstMatch
            return title.exists ? title.frame.minX : nil
        }
        XCTAssertGreaterThan(labels.count, 1)
        if let first = labels.first { for x in labels { XCTAssertEqual(x, first, accuracy: 1, "English labels align beside a reserved glyph column") } }
        capture("app-chooser-glyph-left-search")
        rows.first!.tap()
        XCTAssertTrue(wait { !list.exists })
        XCTAssertTrue(wait { self.app.keyboards.count == 0 }, app.debugDescription)
        XCTAssertEqual(toggle.frame, closed)
    }
    func testContinuousPagingAcrossWindowTrim() {
        launch(); choose("unichar:Category-LetterlikeSymbolsAll", matching: "Letterlike")
        let table = app.tables["glyph-results"]
        let beyondFirstPage = table.buttons["glyph-339D"]
        for _ in 0..<20 where !beyondFirstPage.isHittable { drag(table, from: 0.74, to: 0.39) }
        XCTAssertTrue(beyondFirstPage.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "more-")).firstMatch.exists)
        capture("app-continuous-page-two")
        for _ in 0..<14 { drag(table, from: 0.74, to: 0.39) }
        XCTAssertGreaterThan(inkRange(table.frame.insetBy(dx: 20, dy: 70)), 70, "Later bounded windows paint glyphs")
        capture("app-continuous-late-window")
        for _ in 0..<10 { drag(table, from: 0.35, to: 0.74) }
        XCTAssertGreaterThan(inkRange(table.frame.insetBy(dx: 20, dy: 70)), 70)
        capture("app-continuous-earlier-window")
    }
    func testLateContextExactOccurrenceAndSearchReturn() {
        launch()
        let search = app.textFields["glyph-search"]
        search.tap(); search.typeText("U+1D11E")
        let result = app.tables["glyph-results"].buttons["glyph-1D11E"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        result.press(forDuration: 0.6)
        let show = app.buttons["glyph-show-in-category"]
        for _ in 0..<4 where !show.isHittable { app.swipeUp() }
        XCTAssertTrue(show.waitForExistence(timeout: 5) && show.isHittable, app.debugDescription)
        show.tap()
        let target = app.buttons["category-destination-set:Other Glyphs"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription); target.tap()
        let table = app.tables["glyph-results"]
        XCTAssertTrue(wait { table.buttons["glyph-1D11E"].isHittable }, app.debugDescription)
        XCTAssertTrue(app.buttons["app-context-back"].exists)
        capture("app-late-exact-context")
        app.buttons["app-context-back"].tap()
        XCTAssertTrue(wait { search.value as? String == "U+1D11E" })
        XCTAssertTrue(result.isHittable, "Back restores the exact search result")
        capture("app-context-back-to-search")
    }
    func testUnsupportedCategoryExemplarStaysLegible() {
        launch()
        app.buttons["category-settings"].tap()
        let filter = app.textFields["category-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), app.debugDescription)
        filter.tap(); filter.typeText("Byzantine")
        let visibility = app.switches["category-enabled-block:Byzantine Musical Symbols"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 5), app.debugDescription)
        if visibility.value as? String == "0" { visibility.tap() }
        if app.buttons["close"].exists { app.buttons["close"].tap() }
        app.buttons["category-settings-done"].tap()
        choose("block:Byzantine Musical Symbols", matching: "Byzantine")
        XCTAssertEqual(app.buttons["browse-category"].value as? String, "U+1D000")
        capture("app-unsupported-category-exemplar")
    }
    func testReducedMotionChooserKeepsFixedFrame() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let motion = settings.switches["Reduce Motion"]
        if !motion.exists {
            let accessibility = settings.buttons["Accessibility"]
            for _ in 0..<6 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.waitForExistence(timeout: 5), settings.debugDescription); accessibility.tap()
            let row = settings.buttons["Motion"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), settings.debugDescription); row.tap()
        }
        XCTAssertTrue(motion.waitForExistence(timeout: 5), settings.debugDescription)
        let original = motion.value as? String
        defer {
            app.terminate()
            settings.activate()
            XCTAssertTrue(wait { settings.state == .runningForeground })
            if motion.value as? String != original {
                motion.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            XCTAssertTrue(wait { motion.value as? String == original })
            settings.terminate()
        }
        if original != "1" { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertTrue(wait { motion.value as? String == "1" }, settings.debugDescription)
        let receipt = XCTAttachment(string: "Actual Settings Reduce Motion=\(motion.value ?? "nil"); original=\(original ?? "nil")"); receipt.name = "reduce-motion-settings"; receipt.lifetime = .keepAlways; add(receipt)
        launch()
        let toggle = app.buttons["browse-category"], before = toggle.frame
        choose("set:Emojis", matching: "Emoji")
        XCTAssertEqual(toggle.frame, before)
        toggle.tap()
        XCTAssertTrue(app.buttons["browse-set:Emojis"].isHittable)
        capture("app-reduce-motion-chooser")
    }
    func testEnlargedTextChooserAndPinnedHeading() {
        launch(); choose("unichar:Category-Pictographs", matching: "Pictographs")
        let table = app.tables["glyph-results"]
        drag(table, from: 0.7, to: 0.43)
        let header = app.otherElements["browse-header-unichar:Category-Pictographs"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(inkRange(header.frame), 70)
        XCTAssertEqual(app.buttons["browse-category"].frame.width, 64, accuracy: 1)
        capture("app-enlarged-text-heading")
        app.buttons["browse-category"].tap()
        let list = app.scrollViews["browse-category-list"]
        let selected = app.buttons["browse-set:Emojis"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5) && selected.isHittable)
        XCTAssertTrue(list.frame.contains(selected.frame), "Emoji fits the scrollable chooser")
        capture("app-enlarged-text-chooser")
        selected.tap()
        let search = app.textFields["glyph-search"]
        search.tap(); search.typeText("hea")
        let searchHeader = app.otherElements["browse-search-header"].firstMatch
        XCTAssertTrue(searchHeader.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(searchHeader.frame.height, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 8)
        capture("app-enlarged-text-search")
    }
    private func launch() {
        app.launchArguments = Self.bundleID == "com.clozach.amaanah.alerts" ? ["--show-unimagic"] : []
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 1) { app.buttons["Continue"].tap() }
        let table = app.tables["glyph-results"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        if app.keyboards.count > 0 { drag(table, from: 0.7, to: 0.5) }
    }
    private func choose(_ id: String, matching title: String) {
        app.buttons["browse-category"].tap()
        let filter = app.textFields["browse-category-search"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), app.debugDescription)
        filter.tap(); filter.typeText(title)
        let row = app.buttons["browse-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable, app.debugDescription)
        row.tap()
        XCTAssertTrue(wait { !filter.exists })
    }
    private func drag(_ table: XCUIElement, from: CGFloat, to: CGFloat) {
        table.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: from)).press(forDuration: 0.05, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: to)))
    }
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: 10) == .completed
    }
    private func inkRange(_ frame: CGRect) -> Int {
        let shot = app.screenshot().image
        let scale = CGFloat(shot.cgImage?.width ?? 0) / app.frame.width
        guard let image = shot.cgImage?.cropping(to: CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)) else { return 0 }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let values = stride(from: 0, to: pixels.count, by: 4).map { (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3 }
        return (values.max() ?? 0) - (values.min() ?? 0)
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let ax = XCTAttachment(string: "app=\(app.frame), table=\(app.tables["glyph-results"].frame), floater=\(app.buttons["browse-category"].frame)\n" + app.debugDescription)
        ax.name = name + "-geometry"; ax.lifetime = .keepAlways; add(ax)
    }
}
