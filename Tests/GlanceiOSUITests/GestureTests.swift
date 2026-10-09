import XCTest

/// Drives the real app in the simulator: rating by swiping, undo, the grid and the comparison screen.
final class GestureTests: XCTestCase {
    private var app: XCUIApplication!
    /// Screenshots land here when GLANCE_UITEST_SHOTS is set.
    private let shotDirectory = ProcessInfo.processInfo.environment["GLANCE_UITEST_SHOTS"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-didShowGestureGuide", "YES", "-resetRatings", "YES"]
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

    func testSwipeUpKeepsAndAdvances() throws {
        let before = element("top.counter").label
        shot("01-start")
        pager.swipeUp(velocity: .fast)

        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3), "undo toast should show after rating")
        XCTAssertNotEqual(element("top.counter").label, before, "should advance to the next photo")
        shot("02-after-keep")

        // Going back shows the badge on the photo that was kept.
        pager.swipeRight()
        XCTAssertTrue(element("badge.keep").waitForExistence(timeout: 3), "kept photo shows the keep badge")
        shot("03-badge")
    }

    func testSwipeDownDiscardsAndUndoRestores() throws {
        pager.swipeDown(velocity: .fast)
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("toast.undo").tap()
        XCTAssertFalse(element("badge.discard").waitForExistence(timeout: 2), "undo removes the discard mark")
    }

    func testGridSelectionAndCompare() throws {
        element("top.grid").tap()
        shot("04a-grid")
        XCTAssertTrue(element("grid.select").waitForExistence(timeout: 3))
        element("grid.select").tap()
        let cells = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH '照片'"))
        XCTAssertGreaterThanOrEqual(cells.count, 2)
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        shot("04-grid-selected")
        element("grid.compare").tap()
        XCTAssertTrue(element("compare.close").waitForExistence(timeout: 5), "comparison opens")
        sleep(2)
        shot("05-compare")
        element("compare.close").tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
    }

    func testFilterPill() throws {
        pager.swipeUp(velocity: .fast)
        XCTAssertTrue(element("toast.undo").waitForExistence(timeout: 3))
        element("pill.保留").tap()
        shot("06a-after-tap")
        XCTAssertTrue(element("badge.keep").waitForExistence(timeout: 3), "keep filter shows the kept photo")
        shot("06-keep-filter")
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
}
