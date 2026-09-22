import SwiftUI
import XCTest
@testable import Lumina

/// P2 — what the time table has realized is the set scroll is judged against.
@MainActor
final class ElasticScrollTrackerTests: XCTestCase {

    func testAppearAndDisappearMaintainTheVisibleSet() {
        let tracker = ElasticScrollTracker()
        tracker.plateAppeared(path: "/a.jpg")
        tracker.plateAppeared(path: "/b.jpg")
        XCTAssertEqual(tracker.visiblePaths, ["/a.jpg", "/b.jpg"])
        tracker.plateDisappeared(path: "/a.jpg")
        XCTAssertEqual(tracker.visiblePaths, ["/b.jpg"])
        XCTAssertEqual(tracker.appearEvents, 2)
        XCTAssertEqual(tracker.disappearEvents, 1)
    }

    func testPathChangeSwapsWithoutCountingAnAppearance() {
        let tracker = ElasticScrollTracker()
        tracker.plateAppeared(path: "/old.jpg")
        tracker.plateChanged(from: "/old.jpg", to: "/new.jpg")
        XCTAssertEqual(tracker.visiblePaths, ["/new.jpg"])
        XCTAssertEqual(tracker.appearEvents, 1, "a recycled plate is not a new row")
    }

    func testResetClearsEverything() {
        let tracker = ElasticScrollTracker()
        tracker.plateAppeared(path: "/a.jpg")
        tracker.reset()
        XCTAssertTrue(tracker.visiblePaths.isEmpty)
        XCTAssertEqual(tracker.appearEvents, 0)
    }

    func testEnvironmentDefaultsToNoTracker() {
        // The shelf and the version column must not report: only the table
        // carries a tracker, and it is injected in ElasticRootView.
        XCTAssertNil(EnvironmentValues().elasticScrollTracker)
    }
}
