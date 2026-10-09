import XCTest

/// Drives the real app in the simulator: rating by swiping, undo, the grid and the comparison screen.
final class GestureTests: XCTestCase {
    private var app: XCUIApplication!
    /// Screenshots land here when GLANCE_UITEST_SHOTS is set.
    private let shotDirectory = ProcessInfo.processInfo.environment["GLANCE_UITEST_SHOTS"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-didShowGestureGuide", "YES", "-resetRatings", "YES", "-didShowCompareHint", "NO"]
        addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            for label in ["允许完全访问", "Allow Full Access"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        // First run on a fresh simulator: accept the photo-library prompt.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["允许完全访问", "Allow Full Access"] where springboard.buttons[label].waitForExistence(timeout: 2) {
            springboard.buttons[label].tap()
        }
        XCTAssertTrue(pager.waitForExistence(timeout: 15), "photo pager should appear")
    }

    private var pager: XCUIElement { app.descendants(matching: .any)["viewer.pager"].firstMatch }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: shotDirectory).appendingPathComponent("\(name).png"))
    }

    /// Drag from a point on the screen to another (both in 0…1 screen fractions) and release.
    private func drag(from: CGVector, to: CGVector, hold: TimeInterval = 0.05) {
        let start = app.coordinate(withNormalizedOffset: from)
        let end = app.coordinate(withNormalizedOffset: to)
        start.press(forDuration: hold, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
    }

    func testDragUpRightEndGivesFiveStars() throws {
        let before = element("top.counter").label
        shot("01-start")
        // Up and to the right edge: the last of five stars.
        drag(from: CGVector(dx: 0.5, dy: 0.55), to: CGVector(dx: 0.95, dy: 0.25))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "rating shows the undo toast")
        XCTAssertNotEqual(element("top.counter").label, before, "advances to the next photo")
        pager.swipeRight()
        XCTAssertTrue(element("badge.stars.5").waitForExistence(timeout: 3), "five stars badge")
        shot("03-badge")
    }

    func testDragUpLeftEndGivesOneStar() throws {
        drag(from: CGVector(dx: 0.5, dy: 0.55), to: CGVector(dx: 0.06, dy: 0.25))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        pager.swipeRight()
        XCTAssertTrue(element("badge.stars.1").waitForExistence(timeout: 3), "one star badge")
    }

    func testStarsAppearWhileDraggingUp() throws {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        // Capture while the finger is still down at the end of the drag.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-stars-hud") }
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testPullDownDiscardsAndUndoRestores() throws {
        drag(from: CGVector(dx: 0.5, dy: 0.35), to: CGVector(dx: 0.5, dy: 0.75))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "discard shows the undo toast")
        element("toast.undo").tap()
        XCTAssertFalse(element("badge.discarded").waitForExistence(timeout: 2), "undo removes the discard mark")
    }

    func testPullDownMarksDiscardedNotDeleted() throws {
        drag(from: CGVector(dx: 0.5, dy: 0.35), to: CGVector(dx: 0.5, dy: 0.75))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("filter.menu").tap()
        element("filter.discarded").tap()
        XCTAssertTrue(element("badge.discarded").waitForExistence(timeout: 3), "the discard pile still holds the photo")
        shot("09-discard-pile")
    }

    func testTrashAppearsWhileDraggingDown() throws {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-trash-hud") }
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testDockStarsAndDiscardRate() throws {
        shot("10-dock")
        element("dock.star.3").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "dock rating shows the undo toast")
        pager.swipeRight()
        XCTAssertTrue(element("badge.stars.3").waitForExistence(timeout: 3), "three stars badge")
    }

    func testBrowseGrid() throws {
        element("top.grid").tap()
        sleep(1)
        shot("04a-grid")
        XCTAssertTrue(app.buttons["选择"].waitForExistence(timeout: 3), "browse grid offers 选择")
        app.buttons["完成"].tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
    }

    func testCompareManyPhotos() throws {
        element("dock.compare").tap()
        XCTAssertTrue(element("grid.compare").waitForExistence(timeout: 5), "picker opens with the compare button")
        let cells = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH '照片'"))
        XCTAssertGreaterThanOrEqual(cells.count, 6)
        XCTAssertFalse(element("grid.compare").isEnabled, "needs two photos before it starts")
        shot("04-picker-start")
        for index in 1...5 { cells.element(boundBy: index).tap() }   // six photos in total
        XCTAssertTrue(element("grid.compare").isEnabled)
        shot("04b-picker-six")
        element("grid.compare").tap()
        XCTAssertTrue(element("compare.close").waitForExistence(timeout: 5), "comparison opens")
        XCTAssertTrue(element("compare.hint.ok").waitForExistence(timeout: 3), "first-use hint explains the screen")
        shot("05-compare-hint")
        element("compare.hint.ok").tap()
        sleep(1)
        shot("05-compare-six")
        element("compare.close").tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
    }

    func testStarFilter() throws {
        element("dock.star.4").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("filter.menu").tap()
        element("filter.stars4").tap()
        XCTAssertTrue(element("badge.stars.4").waitForExistence(timeout: 3), "4-star filter shows the rated photo")
        shot("06-star-filter")
    }

    func testSettingsStarScale() throws {
        element("top.more").tap()
        element("menu.settings").tap()
        let scale = element("settings.starScale")
        XCTAssertTrue(scale.waitForExistence(timeout: 3))
        app.segmentedControls.buttons["3 星"].tap()
        shot("12-settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(element("dock.star.3").waitForExistence(timeout: 3))
        XCTAssertFalse(element("dock.star.4").exists, "three-star mode shows three stars")
        shot("12-three-stars")
    }

    func testGuideShowsOnFirstLaunch() throws {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-didShowGestureGuide", "NO", "-resetRatings", "YES"]
        app.launch()
        XCTAssertTrue(element("guide.start").waitForExistence(timeout: 10), "gesture guide shows on first launch")
        shot("07-guide")
        element("guide.start").tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertFalse(element("guide.start").exists)
    }

    /// Reaches a real photo and captures the glass controls over it.
    func testGlassOverRealPhoto() throws {
        for _ in 0..<5 { pager.swipeLeft() }
        sleep(2)
        shot("11-over-photo-\(ProcessInfo.processInfo.environment["GLANCE_UITEST_TAG"] ?? "x")")
    }
}
