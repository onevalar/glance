import XCTest

/// Drives the real app in the simulator: rating by pulling, discard, undo, filters, comparison, settings.
final class GestureTests: XCTestCase {
    private var app: XCUIApplication!
    /// Screenshots land here when GLANCE_UITEST_SHOTS is set.
    private let shotDirectory = ProcessInfo.processInfo.environment["GLANCE_UITEST_SHOTS"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-didShowGestureGuide", "YES",
                                "-resetRatings", "YES", "-didShowCompareHint", "NO"]
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
    /// "02 / 12": the position shown in the scope pill.
    private var position: String { (element("top.scope").value as? String) ?? "" }
    private var screenWidth: CGFloat { app.windows.firstMatch.frame.width }

    private func shot(_ name: String) {
        guard let shotDirectory else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: shotDirectory).appendingPathComponent("\(name).png"))
    }

    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// Drag from one screen point to another (0…1 fractions) and release.
    private func drag(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), hold: TimeInterval = 0.25) {
        at(from.0, from.1).press(forDuration: 0.05, thenDragTo: at(to.0, to.1), withVelocity: .slow, thenHoldForDuration: hold)
    }

    /// Horizontal centre (0…1) of star `k` (1…5) in the star row (matches `RatingDragModel.slot`).
    private func slotX(_ k: Int, slots: Int = 5) -> CGFloat {
        let inset: CGFloat = 18
        return (inset + (CGFloat(k - 1) + 0.5) / CGFloat(slots) * (screenWidth - inset * 2)) / screenWidth
    }

    /// The star row appears where the top bar is.
    private var bandY: CGFloat {
        let bar = element("top.scope").frame
        let height = app.windows.firstMatch.frame.height
        return bar.height > 0 && height > 0 ? bar.midY / height : 0.08
    }

    /// Screenshots at several moments while a gesture runs (the gesture call blocks until it is released).
    private func filmstrip(_ name: String, at times: [Double]) {
        for (index, time) in times.enumerated() {
            DispatchQueue.global().asyncAfter(deadline: .now() + time) { self.shot("\(name)-\(index)") }
        }
    }

    // MARK: - Rating by pulling up

    func testPullUpOntoFifthStarGivesFiveStars() throws {
        let before = position
        drag((0.5, 0.78), (slotX(5), bandY))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "rating shows the undo toast")
        sleep(1)
        shot("14-after-five")
        XCTAssertNotEqual(position, before, "advances to the next photo")
        pager.swipeRight()
        XCTAssertTrue(element("dock.star.5").waitForExistence(timeout: 3))
        XCTAssertTrue(element("dock.star.5").isSelected, "the first photo now has five stars")
    }

    func testPullUpOntoFirstStarGivesOneStar() throws {
        drag((0.5, 0.78), (slotX(1), bandY))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        pager.swipeRight()
        XCTAssertTrue(element("dock.star.1").waitForExistence(timeout: 3))
        XCTAssertTrue(element("dock.star.1").isSelected, "one star")
    }

    func testReleasingAwayFromTheStarsCancels() throws {
        let before = position
        drag((0.5, 0.78), (0.5, 0.60))          // pulled up, but never reached the star row
        XCTAssertFalse(element("toast.undo").waitForExistence(timeout: 2), "nothing was rated")
        XCTAssertEqual(position, before)
        for star in 1...5 { XCTAssertFalse(element("dock.star.\(star)").isSelected) }
    }

    func testTappingTheRatedStarAgainClearsIt() throws {
        element("dock.star.3").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        pager.swipeRight()
        let three = element("dock.star.3")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: three)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 4), .completed, "the rated photo comes back with 3 stars")
        three.tap()
        XCTAssertFalse(element("dock.star.3").isSelected, "rating cleared")
    }

    func testDiscardedPhotoShowsStatusInsteadOfStars() throws {
        element("dock.discard").tap()           // discards and moves on
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        pager.swipeRight()
        XCTAssertTrue(element("dock.restore").waitForExistence(timeout: 4), "the stars give way to a discarded status")
        XCTAssertFalse(element("dock.star.1").exists)
        shot("10-discarded-dock")
        element("dock.restore").tap()
        XCTAssertTrue(element("dock.star.1").waitForExistence(timeout: 3), "restoring brings the stars back")
    }

    func testStarsRiseWhilePulling() throws {
        let end = at(slotX(3), bandY)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-stars-hud") }
        at(0.5, 0.78).press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testStarsShowNothingLitUntilFingerIsOnAStar() throws {
        let end = at(0.5, 0.52)                 // pulled up, still below the row
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-stars-not-on-row") }
        at(0.5, 0.78).press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testThrowUpFilmstrip() throws {
        let y = bandY
        filmstrip("20-throw-up", at: [0.5, 0.8, 1.1, 1.4, 1.65, 1.8, 1.95, 2.2, 2.6])
        at(0.5, 0.75).press(forDuration: 0.05, thenDragTo: at(slotX(4), y), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "thrown into the 4th star")
        Thread.sleep(forTimeInterval: 1)
    }

    func testZoomUsesTheWholeScreen() throws {
        pager.pinch(withScale: 3, velocity: 4)
        sleep(1)
        XCTAssertFalse(element("dock.star.3").exists, "zooming in clears the bars like Photos")
        shot("21-zoomed")
        pager.doubleTap()
        sleep(1)
        shot("21-zoomed-back")
    }

    // MARK: - Discard by pulling down

    func testDropFilmstrip() throws {
        filmstrip("22-drop", at: [0.4, 0.7, 1.0, 1.3, 1.5, 1.65, 1.8, 2.0, 2.3])
        at(0.5, 0.35).press(forDuration: 0.05, thenDragTo: at(0.62, 0.80), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "dropped into the bin")
        Thread.sleep(forTimeInterval: 1)
    }

    func testPullDownDiscardsAndUndoRestores() throws {
        drag((0.5, 0.35), (0.5, 0.82))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "discard shows the undo toast")
        element("toast.undo").tap()
        XCTAssertFalse(element("dock.discard").isSelected, "undo takes the photo out of the discard pile")
    }

    func testPullDownMarksDiscardedNotDeleted() throws {
        drag((0.5, 0.35), (0.5, 0.82))
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("top.scope").tap()
        element("filter.discarded").tap()
        XCTAssertTrue(element("dock.discard").waitForExistence(timeout: 3))
        XCTAssertTrue(element("dock.discard").isSelected, "the discard pile still holds the photo")
        shot("09-discard-pile")
    }

    func testTrashRisesWhilePulling() throws {
        let end = at(0.5, 0.78)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-trash-hud") }
        at(0.5, 0.35).press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testTrashHalfway() throws {
        let end = at(0.5, 0.52)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { self.shot("08-trash-half") }
        at(0.5, 0.35).press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.0)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - No accidental triggers

    func testSmallPullDoesNothing() throws {
        drag((0.5, 0.50), (0.5, 0.58))
        drag((0.5, 0.50), (0.5, 0.43))
        XCTAssertFalse(element("toast.undo").waitForExistence(timeout: 2), "a small vertical drift rates nothing")
    }

    func testSidewaysSwipeWithDriftTurnsThePageOnly() throws {
        let before = position
        // Mostly sideways with a little downward drift, at flick speed.
        at(0.85, 0.50).press(forDuration: 0.05, thenDragTo: at(0.15, 0.60), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        shot("14-after-drift")
        XCTAssertNotEqual(position, before, "the page turned")
        XCTAssertFalse(element("toast.undo").exists, "and nothing was rated or discarded")
    }

    func testSlowSidewaysDragTurnsThePage() throws {
        let before = position
        drag((0.85, 0.50), (0.15, 0.50), hold: 0.05)
        sleep(1)
        XCTAssertNotEqual(position, before, "a slow, straight sideways drag turns the page too")
    }

    func testHorizontalPaging() throws {
        let start = position
        pager.swipeLeft()
        sleep(1)
        let afterLeft = position
        pager.swipeRight()
        sleep(1)
        XCTAssertNotEqual(start, afterLeft, "swipe left goes to the next photo")
        XCTAssertEqual(start, position, "swipe right comes back")
    }

    // MARK: - Dock, filters, scope

    func testDockStarsRate() throws {
        shot("10-dock")
        element("dock.star.3").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        pager.swipeRight()
        XCTAssertTrue(element("dock.star.3").waitForExistence(timeout: 3))
        XCTAssertTrue(element("dock.star.3").isSelected)
    }

    func testDockDiscardMarksThePhoto() throws {
        element("dock.discard").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        pager.swipeRight()
        XCTAssertTrue(element("dock.discard").isSelected)
    }

    func testStarFilterFromTheScopeMenu() throws {
        element("dock.star.4").tap()
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("top.scope").tap()
        shot("06-scope-menu")
        element("filter.stars4").tap()
        XCTAssertTrue(element("dock.star.4").waitForExistence(timeout: 3))
        XCTAssertTrue(element("dock.star.4").isSelected, "the 4-star filter shows the rated photo")
        shot("06-star-filter")
    }

    func testEachActionAppearsOnce() throws {
        // The compare entry is in the dock only; the more-menu has no second copy.
        element("top.more").tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["选择照片对比…"].exists, "no second compare entry in the menu")
        XCTAssertFalse(element("top.counter").exists, "position lives inside the scope pill, not beside it")
    }

    func testTapHidesAndShowsTheBars() throws {
        XCTAssertTrue(element("dock.star.3").exists)
        pager.tap()
        sleep(1)
        XCTAssertFalse(element("dock.star.3").exists, "bars hidden for a clean full-screen photo")
        shot("11-immersive")
        pager.tap()
        XCTAssertTrue(element("dock.star.3").waitForExistence(timeout: 2))
    }

    // MARK: - Overview, comparison, settings, guide

    func testPhotosGrid() throws {
        element("top.photos").tap()
        sleep(1)
        shot("04a-grid")
        XCTAssertTrue(element("grid.close").waitForExistence(timeout: 3))
        element("grid.close").tap()
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

    func testSettingsStarScale() throws {
        element("top.more").tap()
        element("menu.settings").tap()
        XCTAssertTrue(element("settings.starScale").waitForExistence(timeout: 3))
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

    /// Reaches a real photo and captures the layout over it.
    func testLayoutOverRealPhoto() throws {
        for _ in 0..<5 { pager.swipeLeft() }
        sleep(2)
        shot("13-layout-\(ProcessInfo.processInfo.environment["GLANCE_UITEST_TAG"] ?? "x")")
    }
}
