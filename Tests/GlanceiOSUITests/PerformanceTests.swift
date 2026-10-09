import XCTest

/// Measures frame hitches while paging and while pulling photos (uses a library with hundreds of photos).
final class PerformanceTests: XCTestCase {
    @available(iOS 26.0, *)
    func testPagingAndPullingHitches() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Hitch metrics need iOS 26") }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-didShowGestureGuide", "YES", "-resetRatings", "YES"]
        app.launch()
        let pager = app.descendants(matching: .any)["viewer.pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 20))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTClockMetric()], options: options) {
            for _ in 0..<5 { pager.swipeLeft(velocity: .fast) }
            for _ in 0..<3 { pager.swipeRight(velocity: .fast) }
            // Short pulls that release before anything is committed.
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            let down = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            let up = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            for _ in 0..<3 {
                top.press(forDuration: 0.05, thenDragTo: down, withVelocity: .slow, thenHoldForDuration: 0.1)
                top.press(forDuration: 0.05, thenDragTo: up, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
    }
}
