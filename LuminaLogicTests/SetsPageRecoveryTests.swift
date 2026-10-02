import XCTest
@testable import Lumina

/// Threat model T7 with no WebKit behind it: how often a page that stopped may be reloaded
/// (3 in 60 s, then ask), and the unsaved-keepers question Quit waits on (the first of the page's
/// answer or the 2 s timeout, exactly once). The clock and the timer are injected.
@MainActor
final class SetsPageRecoveryTests: XCTestCase {
    /// A clock the test moves by hand.
    final class Clock { var t: TimeInterval = 1000 }

    private func policy(_ clock: Clock) -> SetsReloadPolicy { SetsReloadPolicy(now: { clock.t }) }

    // MARK: Reload policy

    func testShippedLimitIsThreeReloadsInSixtySeconds() {
        let p = SetsReloadPolicy()
        XCTAssertEqual(p.limit, 3); XCTAssertEqual(p.window, 60)
    }

    func testThreeReloadsInAMinuteThenTheFourthIsRefused() {
        let clock = Clock(); var p = policy(clock)
        for i in 0..<3 {
            XCTAssertEqual(p.pageStopped(), .reload, "reload \(i + 1) of 3")
            clock.t += 5
        }
        XCTAssertEqual(p.pageStopped(), .ask, "the 4th stop inside the minute is not reloaded")
        clock.t += 1
        XCTAssertEqual(p.pageStopped(), .ask, "and stays refused while the window holds")
        XCTAssertEqual(p.reloads.count, 3, "a refused stop is not counted")
    }

    func testFourStopsAtTheSameInstant() {
        let clock = Clock(); var p = policy(clock)
        XCTAssertEqual((0..<4).map { _ in p.pageStopped() }, [.reload, .reload, .reload, .ask])
    }

    func testAllowedAgainOnceTheWindowHasPassed() {
        let clock = Clock(); var p = policy(clock)
        for _ in 0..<3 { _ = p.pageStopped() }                 // three reloads at t
        clock.t += 59.9
        XCTAssertEqual(p.pageStopped(), .ask, "59.9 s later all three are still inside the window")
        clock.t += 0.1
        XCTAssertEqual(p.pageStopped(), .reload, "60 s later they are not")
        XCTAssertEqual(p.reloads.count, 1)
    }

    func testTheWindowSlides() {
        let clock = Clock(); var p = policy(clock)
        XCTAssertEqual(p.pageStopped(), .reload)               // t
        clock.t += 30; XCTAssertEqual(p.pageStopped(), .reload) // t + 30
        clock.t += 20; XCTAssertEqual(p.pageStopped(), .reload) // t + 50
        clock.t += 5;  XCTAssertEqual(p.pageStopped(), .ask)    // t + 55: three inside the last 60 s
        clock.t += 6;  XCTAssertEqual(p.pageStopped(), .reload) // t + 61: the first has left the window
        XCTAssertEqual(p.pageStopped(), .ask, "t + 30, t + 50 and t + 61 are inside it")
    }

    func testOccasionalStopsNeverAsk() {
        let clock = Clock(); var p = policy(clock)
        for _ in 0..<50 { XCTAssertEqual(p.pageStopped(), .reload); clock.t += 21 }   // at most 3 in any 60 s
    }

    func testTryAgainResetsTheCount() {
        let clock = Clock(); var p = policy(clock)
        for _ in 0..<3 { _ = p.pageStopped() }
        XCTAssertEqual(p.pageStopped(), .ask)
        p.reset()                                              // "Try Again": the window reloads the page itself
        XCTAssertTrue(p.reloads.isEmpty)
        for i in 0..<3 { XCTAssertEqual(p.pageStopped(), .reload, "reload \(i + 1) of 3 after Try Again") }
        XCTAssertEqual(p.pageStopped(), .ask, "then it asks again")
    }

    // MARK: The alert's words

    func testAlertNamesTheLimitAndThatDecisionsAreSaved() {
        XCTAssertEqual(SetsPageStoppedAlert.message, "Lumina keeps stopping")
        XCTAssertEqual(SetsPageStoppedAlert.detail(), "It stopped again after reloading 3 times in a minute. Your decisions so far are saved.")
        XCTAssertEqual([SetsPageStoppedAlert.tryAgain, SetsPageStoppedAlert.quit], ["Try Again", "Quit"])
    }

    // MARK: Exactly one reply to Quit

    /// A timer and a page the test fires by hand, in either order.
    final class Rig {
        var timeout: TimeInterval?
        var fire: (@MainActor () -> Void)?
        var answer: (@MainActor (Int) -> Void)?
        var replies: [Int] = []

        @MainActor func ask() {
            SetsFirstAnswer<Int>.ask(timeout: 2, fallback: 0,
                                     schedule: { after, fire in self.timeout = after; self.fire = fire },
                                     question: { self.answer = $0 },
                                     done: { self.replies.append($0) })
        }
    }

    func testAnswerFirstThenTimeoutRepliesOnceWithTheAnswer() {
        let rig = Rig(); rig.ask()
        XCTAssertEqual(rig.timeout, 2)
        XCTAssertEqual(rig.replies, [], "nothing until one of them comes")
        rig.answer?(4)
        XCTAssertEqual(rig.replies, [4])
        rig.fire?()
        XCTAssertEqual(rig.replies, [4], "the timeout after the answer is dropped")
    }

    func testTimeoutFirstThenAnswerRepliesOnceWithZero() {
        let rig = Rig(); rig.ask()
        rig.fire?()
        XCTAssertEqual(rig.replies, [0], "no answer in 2 s counts as no unsaved keepers")
        rig.answer?(4)
        XCTAssertEqual(rig.replies, [0], "a late answer is dropped")
    }

    func testPageThatNeverAnswersRepliesOnceOnTimeout() {
        let rig = Rig(); rig.ask()
        rig.fire?(); rig.fire?()
        XCTAssertEqual(rig.replies, [0])
    }

    func testPageThatAnswersTwiceRepliesOnce() {
        let rig = Rig(); rig.ask()
        rig.answer?(0); rig.answer?(7)
        XCTAssertEqual(rig.replies, [0])
    }

    func testAnswerInsideTheQuestionItselfStillRepliesOnce() {
        var replies: [Int] = []
        var fire: (@MainActor () -> Void)?
        SetsFirstAnswer<Int>.ask(timeout: 2, fallback: 0, schedule: { _, f in fire = f },
                                 question: { $0(3) }, done: { replies.append($0) })
        fire?()
        XCTAssertEqual(replies, [3])
    }

    func testFirstAnswerReportsWhichCallWon() {
        var got: [String] = []
        let first = SetsFirstAnswer<String> { got.append($0) }
        XCTAssertFalse(first.isAnswered)
        XCTAssertTrue(first.answer("page"))
        XCTAssertFalse(first.answer("timeout"))
        XCTAssertTrue(first.isAnswered)
        XCTAssertEqual(got, ["page"])
    }

    func testQuitWaitsTwoSeconds() {
        XCTAssertEqual(SetsWindowController.unsavedKeepersTimeout, 2)
    }
}
