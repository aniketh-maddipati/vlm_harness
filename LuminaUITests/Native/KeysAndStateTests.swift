import XCTest

/// Port of "Lumina Stress Test.dc.html": keys & state.
final class KeysAndStateTests: XCTestCase {
    var l: Lumina!
    override func setUp() { continueAfterFailure = false; l = Lumina().launch() }
    override func tearDown() { assertNoErrors(l); l.app.terminate() }

    /// R-01
    func test_R01_enterMashOnOpen_startsCullingNeverSave() {
        for i in 0..<6 { l.enter(); l.pause(i < 2 ? 0.03 : 0.01) }
        l.pause(0.5)
        XCTAssertEqual(l.state.step, "cull")
    }

    /// R-04
    func test_R04_fastKeepUndoRedo_exactCounts() {
        l.startCulling()
        for _ in 0..<10 { l.key("r"); l.pause(0.05) }
        XCTAssertEqual(l.state.kept, 10)
        for _ in 0..<10 { l.cmd("z"); l.pause(0.03) }
        XCTAssertEqual(l.state.kept, 0)
        for _ in 0..<3 { l.key("z", [.command, .shift]); l.pause(0.03) }
        XCTAssertEqual(l.state.kept, 3)
    }

    /// R-05
    func test_R05_keepAndOutSameInstant_noHalfStates() {
        l.startCulling()
        for _ in 0..<20 { l.key("r"); l.key("x"); l.pause(0.025) }
        l.pause(0.3)
        let s = l.state
        XCTAssertEqual(s.kept + s.out + s.undecided, s.total, "every photo is exactly one of kept/out/undecided")
    }

    /// R-02
    func test_R02_stepSwitchSpam_lastPressWins() {
        l.startCulling(); l.keepN(6)
        var last = 1
        for _ in 0..<40 { last = Int.random(in: 1...4); l.cmd("\(last)"); l.pause(0.015) }
        l.pause(0.9)
        XCTAssertEqual(l.state.step, ["open", "cull", "edit", "save"][last - 1])
    }

    /// R-06
    func test_R06_variationThenPhotoSwitch_newPhotoUntouched() {
        l.startCulling(); l.keepN(6); l.go(3, settle: 1.2)
        let c0 = l.state.cur
        l.hold("v", for: 0.35) { l.right() }
        l.right(); l.pause(0.01)
        let c1 = l.state.cur, look0 = l.state.look
        l.pause(0.7)
        XCTAssertNotEqual(c1, c0, "photo didn’t switch")
        XCTAssertEqual(l.state.look, look0, "R-06 variation landed on the next photo")
    }

    /// R-24
    func test_R24_blurWhileHoldingV_closesGrid() {
        l.startCulling(); l.keepN(4); l.go(3, settle: 1.2)
        l.command("{\"keyDown\":\"v\"}"); l.pause(0.25)
        XCTAssertEqual(l.state.overlay, "variations")
        l.blurWindow(); l.pause(0.25)
        XCTAssertNil(l.state.overlay)
        l.command("{\"keyUp\":\"v\"}")
    }

    /// R-07
    func test_R07_editThenLeaveWithin50ms_isSaved() {
        l.startCulling(); l.keepN(4); l.go(3, settle: 1.2)
        let before = l.state.look
        for _ in 0..<3 { l.key("."); l.pause(0.015) }
        let after = l.state.look
        XCTAssertNotEqual(after, before, "harness: nudge did nothing")
        l.cmd("2"); l.pause(0.4)
        l.relaunch(); l.go(3, settle: 1.2)
        XCTAssertEqual(l.state.look, after, "R-07 edit made just before ⌘2 was lost")
    }

    /// R-08
    func test_R08_outInEdit_undoInCull_doesNotRevive() {
        l.startCulling(); l.keepN(6); l.go(3, settle: 1.0)
        let c = l.state.cur!
        l.key("x"); l.pause(0.15)
        l.go(2, settle: 0.5); l.cmd("z"); l.pause(0.3)
        XCTAssertEqual(l.state.keep[c], false, "R-08 Cull ⌘Z brought back a photo taken out in Edit")
    }

    /// R-03
    func test_R03_heldEnterOnLastPhoto_landsOnSave_doesNotSave() {
        l.startCulling(); l.keepN(6); l.go(3, settle: 1.0)
        for _ in 0..<40 { l.right(); l.pause(0.02) }
        for _ in 0..<6 { l.enter(); l.pause(0.03) }
        l.pause(0.6)
        XCTAssertEqual(l.state.step, "save"); XCTAssertNil(l.state.saved, "R-03 held ⏎ saved")
    }
}
