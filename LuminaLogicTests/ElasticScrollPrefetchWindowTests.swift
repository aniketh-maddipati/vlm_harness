import XCTest
@testable import Lumina

/// P2 item 4 — the window the tracker hands the browse service, derived from
/// where the realized plates are and how fast they are moving.
@MainActor
final class ElasticScrollPrefetchWindowTests: XCTestCase {

    func testStillPrefetchesOneScreenEitherSideNearestFirst() {
        let window = ElasticScrollTracker.prefetchWindow(visible: 40...59, velocity: 0, count: 400)
        XCTAssertEqual(window.keep, 20...79)
        XCTAssertEqual(window.ahead.prefix(4), [60, 39, 61, 38], "alternates outward from both edges")
        XCTAssertEqual(window.ahead.count, 40)
    }

    func testMovingForwardReachesTwoScreensAheadAndKeepsOneBehind() {
        let window = ElasticScrollTracker.prefetchWindow(visible: 40...59, velocity: 90, count: 400)
        XCTAssertEqual(window.ahead.first, 60)
        XCTAssertEqual(window.ahead.last, 99, "two screens of twenty past the leading edge")
        XCTAssertEqual(window.keep, 20...99, "one screen behind the trailing edge stays; 0…19 is cancelled")
    }

    func testMovingBackwardMirrors() {
        let window = ElasticScrollTracker.prefetchWindow(visible: 200...219, velocity: -90, count: 400)
        XCTAssertEqual(window.ahead.first, 199)
        XCTAssertEqual(window.ahead.last, 160)
        XCTAssertEqual(window.keep, 160...239)
    }

    func testWindowIsClampedToTheShoot() {
        let end = ElasticScrollTracker.prefetchWindow(visible: 390...399, velocity: 90, count: 400)
        XCTAssertTrue(end.ahead.isEmpty, "nothing past the last frame")
        XCTAssertEqual(end.keep, 380...399)
        let start = ElasticScrollTracker.prefetchWindow(visible: 0...9, velocity: -90, count: 400)
        XCTAssertTrue(start.ahead.isEmpty)
        XCTAssertEqual(start.keep, 0...19)
    }

    func testANarrowViewportStillLooksAMinimumScreenAhead() {
        let window = ElasticScrollTracker.prefetchWindow(visible: 50...51, velocity: 30, count: 400)
        XCTAssertEqual(window.ahead.count, ElasticScrollTracker.minimumScreenFrames * ElasticScrollTracker.screensAhead)
    }

    func testEmptyShootHasNoWindow() {
        XCTAssertEqual(ElasticScrollTracker.prefetchWindow(visible: 0...0, velocity: 5, count: 0), .empty)
    }

    func testVelocityIsEstimatedFromTheCentreOverTheHorizon() {
        var now: CFTimeInterval = 100
        let tracker = ElasticScrollTracker(clock: { now })
        let paths = (0..<400).map { "/f\($0).jpg" }
        tracker.shootChanged(paths: paths)
        // A screen of twenty realized at index 0, then the whole screen
        // advances by ten frames every 100 ms — 100 frames/s.
        for i in 0..<20 { tracker.plateAppeared(path: paths[i]) }
        for step in 1...3 {
            now += 0.1
            for i in 0..<10 { tracker.plateDisappeared(path: paths[(step - 1) * 10 + i]) }
            for i in 0..<10 { tracker.plateAppeared(path: paths[20 + (step - 1) * 10 + i]) }
        }
        // The median moves in two phases per step (plates leave, then plates
        // arrive), so the estimate sits between 50 and 200 depending on which
        // phase the horizon's oldest sample caught. Direction and magnitude
        // are what the window needs; a frame-exact figure is not.
        XCTAssertGreaterThan(tracker.velocity, 50)
        XCTAssertLessThan(tracker.velocity, 200)
        XCTAssertGreaterThan(tracker.lastWindow.ahead.count, 0)
        XCTAssertEqual(tracker.lastWindow.ahead.first, 50, "one past the leading edge")
    }
}
