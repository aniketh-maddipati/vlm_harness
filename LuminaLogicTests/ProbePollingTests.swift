import XCTest
@testable import Lumina

/// F04.2 — timed-out predicate wait returns nil, never the last-seen non-matching snapshot.
final class ProbePollingTests: XCTestCase {

    func testTimedOutWaitReturnsNilWhenPredicateNeverMatched() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let deadline = now.addingTimeInterval(1.0)
        var pollCount = 0

        let result = ProbePolling.waitUntil(
            deadline: deadline,
            pollInterval: 0.05,
            now: { now },
            sleep: { interval in now = now.addingTimeInterval(interval) },
            snapshot: {
                pollCount += 1
                return "wrong-state-\(pollCount)"
            },
            where: { $0 == "expected-state" }
        )

        XCTAssertNil(result, "must return nil when predicate never matched")
        XCTAssertGreaterThan(pollCount, 0, "poll loop must have observed snapshots")
        XCTAssertGreaterThanOrEqual(now, deadline, "poll must run until deadline")
    }

    func testWaitReturnsMatchingSnapshotBeforeDeadline() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let deadline = now.addingTimeInterval(1.0)
        var reads = 0

        let result = ProbePolling.waitUntil(
            deadline: deadline,
            pollInterval: 0.05,
            now: { now },
            sleep: { interval in now = now.addingTimeInterval(interval) },
            snapshot: {
                reads += 1
                return reads < 3 ? "pending" : "ready"
            },
            where: { $0 == "ready" }
        )

        XCTAssertEqual(result, "ready")
        XCTAssertEqual(reads, 3)
    }
}
