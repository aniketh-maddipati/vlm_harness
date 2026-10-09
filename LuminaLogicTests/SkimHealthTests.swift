import XCTest
@testable import Lumina

/// Skim's pacing steps (`SkimHealth.Pacer`): down at once when the Mac gets hot, back up one level
/// at a time after a quiet spell, and the reason it gives in plain words.
final class SkimHealthTests: XCTestCase {
    func testStepsDownAtOnceAndBackUpOneAtATime() {
        var p = SkimHealth.Pacer()
        XCTAssertEqual(p.step(asked: 0, now: 0), 0)
        XCTAssertEqual(p.step(asked: 3, now: 10), 3)
        XCTAssertEqual(p.step(asked: 0, now: 20), 3, "too soon to step up")
        let up = VideoPolicy.recoverAfterSeconds
        XCTAssertEqual(p.step(asked: 0, now: 10 + up + 1), 2)
        XCTAssertEqual(p.step(asked: 0, now: 10 + up + 2), 2, "one level per quiet spell")
        XCTAssertEqual(p.step(asked: 0, now: 10 + 2 * up + 3), 1)
        XCTAssertEqual(p.step(asked: 2, now: 10 + 2 * up + 4), 2, "worse again: straight down")
    }

    func testReasonNamesTheWorstSignal() {
        XCTAssertNil(SkimHealth.reason(thermal: 0, low: false, pressure: .none, slowdown: 1, level: 0))
        XCTAssertEqual(SkimHealth.reason(thermal: 2, low: true, pressure: .warning, slowdown: 1, level: 2), "Mac is hot")
        XCTAssertEqual(SkimHealth.reason(thermal: 0, low: false, pressure: .critical, slowdown: 1, level: 3), "memory is short")
        XCTAssertEqual(SkimHealth.reason(thermal: 0, low: true, pressure: .none, slowdown: 1, level: 1), "Low Power Mode")
        XCTAssertEqual(SkimHealth.reason(thermal: 0, low: false, pressure: .none, slowdown: 1.6, level: 1), "decoding has slowed")
    }

    func testReadingHasEveryField() {
        let r = SkimHealth.shared.read(slowdown: 1)
        for k in ["thermal", "lowPower", "pressure", "level", "duty", "reason", "memGB"] { XCTAssertNotNil(r[k], k) }
    }
}
