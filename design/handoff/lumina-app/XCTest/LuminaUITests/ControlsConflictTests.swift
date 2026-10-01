import XCTest

/// Port of "Lumina Controls Test.dc.html", Controls suite: confusions and conflicts.
final class ControlsConflictTests: XCTestCase {
    var l: Lumina!
    override func setUp() { continueAfterFailure = false; l = Lumina().launch(); l.startCulling(); l.keepN(30); l.pause(0.3) }
    override func tearDown() { assertNoErrors(l); l.app.terminate() }
    func inEdit() { l.go(3, settle: 1.2) }

    /// R-28
    func test_R28_xMeansOutEverywhere_undoRestores() {
        l.go(2); let c = l.state.cur!
        l.key("x"); l.pause(0.3); XCTAssertEqual(l.state.keep[c], false)
        l.cmd("z"); l.pause(0.3); XCTAssertNotEqual(l.state.keep[c], false)
        inEdit(); let e = l.state.cur!, e0 = l.state.keep[e]
        l.key("x"); l.pause(0.7); XCTAssertEqual(l.state.keep[e], false)
        l.cmd("z"); l.pause(0.7); XCTAssertEqual(l.state.keep[e], e0)
    }

    /// R-20
    func test_R20_rInEdit_doesNotRotate_explains() {
        inEdit(); let look = l.state.look, c = l.state.cur
        l.key("r"); l.pause(0.4)
        XCTAssertEqual(l.state.look, look); XCTAssertEqual(l.state.cur, c)
        XCTAssertTrue(l.value("edit.toast").contains("R keeps photos in Cull"))
    }

    /// R-21
    func test_R21_tDoesNothing() {
        inEdit(); l.key("t"); l.pause(0.3); XCTAssertNil(l.state.overlay)
    }

    /// R-22
    func test_R22_typingAValue_doesNotTriggerShortcuts() {
        inEdit(); l.click("edit.value.ev"); XCTAssertTrue(l.exists("edit.valueField", timeout: 1))
        let s0 = l.state
        l.el("edit.valueField").typeText("rxzv0")
        l.right(); l.pause(0.4)
        let s1 = l.state
        XCTAssertEqual(s1.cur, s0.cur, "photo switched"); XCTAssertEqual(s1.zoom, s0.zoom, "zoomed")
        XCTAssertEqual(s1.keep, s0.keep, "keep changed"); XCTAssertNotEqual(s1.overlay, "variations")
        l.esc()
    }

    /// R-23
    func test_R23_helpBlocksThePhoto() {
        inEdit(); l.key("/", .shift); l.pause(0.3)
        XCTAssertEqual(l.state.overlay, "help")
        let s0 = l.state
        for k in ["x", "r", "."] { l.key(k) }; l.right(); l.pause(0.4)
        XCTAssertEqual(l.state.cur, s0.cur); XCTAssertEqual(l.state.keep, s0.keep); XCTAssertEqual(l.state.look, s0.look)
        l.esc(); l.pause(0.3); XCTAssertNil(l.state.overlay); XCTAssertEqual(l.state.cur, s0.cur)
    }

    /// R-24 (crop)
    func test_R24_cropOwnsTheKeyboard() {
        inEdit(); let s0 = l.state
        l.key("c"); l.pause(0.35); XCTAssertEqual(l.state.overlay, "crop")
        for k in ["x", "a", "0", ".", ","] { l.key(k); l.pause(0.04) }
        l.pause(0.4)
        XCTAssertEqual(l.state.keep[s0.cur!], s0.keep[s0.cur!], "X took it out under the crop")
        XCTAssertEqual(l.state.cur, s0.cur)
        l.esc(); l.pause(0.4)
        XCTAssertEqual(l.state.look, s0.look, "the edit changed under the crop")
    }

    /// R-24 (variations)
    func test_R24_variationsOwnTheKeyboard() {
        inEdit(); let s0 = l.state
        l.command("{\"keyDown\":\"v\"}"); l.pause(0.35); XCTAssertEqual(l.state.overlay, "variations")
        for k in ["x", "r", "a"] { l.key(k); l.pause(0.04) }
        l.esc(); l.command("{\"keyUp\":\"v\"}"); l.pause(0.5)
        XCTAssertEqual(l.state.keep, s0.keep); XCTAssertEqual(l.state.look, s0.look); XCTAssertNil(l.state.overlay)
    }

    /// R-25
    func test_R25_escBacksOutOneLayer() {
        inEdit(); l.key("z"); l.pause(0.3); l.key("h"); l.pause(0.3)
        XCTAssertGreaterThan(l.state.zoom, 1); XCTAssertEqual(l.state.overlay, "focus")
        l.esc(); l.pause(0.3); XCTAssertGreaterThan(l.state.zoom, 1, "first esc should only leave focus"); XCTAssertNil(l.state.overlay)
        l.esc(); l.pause(0.3); XCTAssertEqual(l.state.zoom, 1, accuracy: 0.01)
        for (name, open) in [("help", { self.l.key("/", .shift) }), ("crop", { self.l.key("c") }), ("zoom", { self.l.key("z") }), ("focus", { self.l.key("h") })] as [(String, () -> Void)] {
            open(); l.pause(0.35); var n = 0
            while (l.state.overlay != nil || abs(l.state.zoom - 1) > 0.01) && n < 4 { l.esc(); l.pause(0.25); n += 1 }
            XCTAssertLessThanOrEqual(n, 3, "\(name) needed \(n) esc"); XCTAssertNil(l.state.overlay, "stuck in \(name)")
        }
    }

    /// R-27
    func test_R27_cmdZInEdit_undoesTheEditNotTheDecision() {
        inEdit(); let c = l.state.cur!, k = l.state.keep[c], look0 = l.state.look
        l.key("."); l.pause(0.25); XCTAssertNotEqual(l.state.look, look0)
        l.cmd("z"); l.pause(0.4)
        XCTAssertEqual(l.state.look, look0); XCTAssertEqual(l.state.keep[c], k)
    }

    /// R-33
    func test_R33_enterRhythmNeverSaves_pausedEnterDoes() {
        inEdit(); for _ in 0..<60 { l.right(); l.pause(0.01) }
        var reached = false
        for _ in 0..<8 { l.enter(); l.pause(0.55); if l.state.step == "save" { reached = true } }
        XCTAssertTrue(reached); XCTAssertNil(l.state.saved, "the ⏎ rhythm saved")
        l.pause(1.3); l.enter(); l.pause(0.4)
        XCTAssertNotNil(l.state.saved, "a deliberate ⏎ after a pause didn’t save")
    }

    /// R-35
    func test_R35_cmdS_isPredictable() {
        inEdit(); l.key("."); l.pause(0.3); let before = l.state.saved?.sig
        l.cmd("s"); l.pause(0.6)
        XCTAssertEqual(l.state.step, "save"); XCTAssertEqual(l.state.saved?.sig, before, "⌘S in Edit saved")
        l.cmd("s"); l.pause(0.5); XCTAssertNotEqual(l.state.saved?.sig, before)
    }

    /// R-26
    func test_R26_hintsMatchBehaviour() {
        inEdit(); l.key("/", .shift); l.pause(0.3)
        let text = l.el("edit.help").staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
            + l.app.descendants(matching: .any).allElementsBoundByIndex.compactMap { $0.value as? String }.joined(separator: " ")
        XCTAssertNil(text.range(of: #"(^|\n)T\s*\n"#, options: .regularExpression), "help still lists T")
        XCTAssertFalse(text.contains("T tries"))
        XCTAssertNil(text.range(of: #"(^|\n)R( · ⇧R)?\s*\n\s*turn 90"#, options: .regularExpression), "help lists R as rotate")
        l.esc()
    }
}
