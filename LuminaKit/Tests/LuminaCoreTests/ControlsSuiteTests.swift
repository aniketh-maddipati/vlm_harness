import XCTest
import CoreGraphics
@testable import LuminaCore

// The design's "Lumina Controls Test.dc.html", controls half, headless: one meaning per key,
// the layers that own the keyboard, Esc, undo scope, the ⏎ and ⌘S guards (R-20…R-28, R-33,
// R-35), plus the conflicts between a slider under the pointer and the keyboard. Each check is a
// function; every test prepares the model the way the HTML run does (the card copied, 30 kept,
// in Edit) and runs one check, and `test_controlsRun_inOneSession` runs them all in the HTML's
// order on one model, state carried over, ending with "no errors" (cErrors).
// Shared helpers are in StressSuiteTests.swift. The Controls suite's load half (ingest,
// ingestKeys, cullAll, editBig, editMany, exportBig, reloadBig) is StressSuiteTests/test_load5000_….
//
// UI-only (they need the real window, its pixels or its focus), they stay in the XCUITests:
//   typing   a real NSTextField holding the keyboard (here: the model's text-field layer and
//            `windowKey(typing:)`)               → LuminaUITests/ControlsConflictTests/test_R22_typingAValue_doesNotTriggerShortcuts
//   hints    tooltips on the real controls (Help's words are checked here)
//                                                → LuminaUITests/ControlsConflictTests/test_R26_hintsMatchBehaviour
//   esc      "controls shown / hidden" as drawn  → LuminaUITests/ControlsConflictTests/test_R25_escBacksOutOneLayer

@MainActor
final class ControlsSuiteTests: XCTestCase {
    override func tearDown() async throws { Faults.shared.clearAll() }

    /// The HTML run's preparation: the card copied, 30 R presses, then Edit.
    private func prepared(store: (any PersistenceStore)? = nil) -> Harness {
        let h = Harness(store: store)
        h.startCulling()
        for _ in 0..<30 { h.key("r", settle: 0.03) }
        h.wait(0.3)
        h.go(3, settle: 1.2)
        XCTAssertEqual(h.state.kept, 30); XCTAssertEqual(h.state.step, "edit")
        return h
    }

    // MARK: the checks (each starts and ends in Edit)

    /// rEdit: R in Edit doesn't turn or change the photo; it says what R does (R-20).
    private func rEdit(_ h: Harness, line: UInt = #line) {
        let before = h.model.debugStateJSON, c = h.state.cur
        h.key("r", settle: 0.4)
        XCTAssertEqual(h.model.debugStateJSON, before, "rEdit: R changed something", line: line)
        XCTAssertEqual(h.state.cur, c, line: line)
        XCTAssertNil(h.model.currentLook[CropKey.turns], "rEdit: R turned the photo", line: line)
        XCTAssertEqual(h.model.toast?.text, KeyRouter.rExplanation, "rEdit: no explanation shown", line: line)
    }

    /// xSame: X is Out in Cull and in Edit, and ⌘Z brings the previous decision back in each (R-28).
    private func xSame(_ h: Harness, line: UInt = #line) {
        h.go(2, settle: 0.5)
        guard let c = h.model.cullCur else { return XCTFail("xSame: no photo in Cull", line: line) }
        let a0 = h.model.decisions.keep[c]
        h.key("x", settle: 0.3); let a = h.model.decisions.keep[c]
        h.key("cmd+z", settle: 0.3); let a2 = h.model.decisions.keep[c]
        h.go(3, settle: 1.2)
        guard let e = h.model.editCur else { return XCTFail("xSame: no photo in Edit", line: line) }
        let e0 = h.model.decisions.keep[e]
        h.key("x", settle: 0.7); let b = h.model.decisions.keep[e]
        h.key("cmd+z", settle: 0.7); let b2 = h.model.decisions.keep[e]
        XCTAssertEqual(a, false, "xSame: X in Cull", line: line); XCTAssertEqual(a2, a0, "xSame: ⌘Z in Cull", line: line)
        XCTAssertEqual(b, false, "xSame: X in Edit", line: line); XCTAssertEqual(b2, e0, "xSame: ⌘Z in Edit", line: line)
        XCTAssertEqual(h.state.cur, e, "xSame: Edit's ⌘Z goes back to the photo", line: line)
    }

    /// tGone: T does nothing (R-21).
    private func tGone(_ h: Harness, line: UInt = #line) {
        let before = h.model.debugStateJSON
        h.key("t", settle: 0.3)
        XCTAssertNil(h.state.overlay, "tGone: T opened something", line: line)
        XCTAssertEqual(h.model.debugStateJSON, before, "tGone: T did something", line: line)
    }

    /// typing: with a number field open, R X Z V → 0 type into it: no keep, no out, no zoom, no
    /// grid, no photo switch (R-22).
    private func typing(_ h: Harness, line: UInt = #line) {
        let c = h.state.cur, z = h.state.zoom, k = h.state.keep, l = h.state.look
        let text = h.model.beginTyping("ev")
        XCTAssertFalse(text.isEmpty, "typing: the field opened empty", line: line)
        XCTAssertEqual(h.model.edit.typingKey, "ev", line: line)
        for key in ["r", "x", "z", "v", "right", "0"] {
            XCTAssertFalse(h.model.windowKey(KeyEvent(key), typing: true), "typing: \(key) was taken from the field", line: line)
            h.model.windowKey(KeyEvent(key, phase: .up), typing: true)
            XCTAssertEqual(h.model.handle(KeyEvent(key)).action, .typing, "typing: \(key) reached Lumina", line: line)
            h.model.handle(KeyEvent(key, phase: .up))
            h.wait(0.03)
        }
        h.wait(0.4)
        XCTAssertEqual(h.state.cur, c, "typing: photo switched", line: line); XCTAssertEqual(h.state.zoom, z, "typing: zoomed", line: line)
        XCTAssertNil(h.state.overlay, "typing: variations opened", line: line); XCTAssertEqual(h.state.keep, k, "typing: keep changed", line: line)
        XCTAssertEqual(h.state.look, l, "typing: the photo changed", line: line)
        h.model.cancelTyping()                                                    // Esc in the field: nothing changes
        XCTAssertNil(h.model.edit.typingKey, line: line); XCTAssertEqual(h.state.look, l, line: line)
    }

    /// help: with the key list open, X R → . do nothing; Esc closes only the list (R-23).
    private func help(_ h: Harness, line: UInt = #line) {
        h.key("?", settle: 0.3)
        XCTAssertEqual(h.state.overlay, "help", "help: didn’t open", line: line)
        let c = h.state.cur, k = h.state.keep, l = h.state.look
        for key in ["x", "r", "right", "."] { h.key(key, settle: 0.04) }
        h.wait(0.4)
        XCTAssertEqual(h.state.cur, c, line: line); XCTAssertEqual(h.state.keep, k, line: line); XCTAssertEqual(h.state.look, l, "help: keys reached the photo", line: line)
        XCTAssertEqual(h.state.overlay, "help", line: line)
        h.key("escape", settle: 0.3)
        XCTAssertNil(h.state.overlay, "help: esc didn’t close it", line: line); XCTAssertEqual(h.state.cur, c, line: line)
    }

    /// crop: while cropping, X A 0 . , don't act on the photo underneath; Esc cancels (R-24).
    private func crop(_ h: Harness, line: UInt = #line) {
        guard let c = h.state.cur else { return XCTFail("crop: no photo", line: line) }
        let l = h.state.look, k = h.state.keep[c]
        h.key("c", settle: 0.35)
        XCTAssertEqual(h.state.overlay, "crop", line: line)
        for key in ["x", "a", "0", ".", ","] { h.key(key, settle: 0.04) }
        h.wait(0.4)
        XCTAssertEqual(h.state.keep[c], k, "crop: X took it out", line: line); XCTAssertEqual(h.state.cur, c, "crop: photo switched", line: line)
        XCTAssertEqual(h.model.toast?.text, KeyRouter.cropSwallow, "crop: a stray key should say how to leave", line: line)
        h.key("escape", settle: 0.4)
        XCTAssertNil(h.state.overlay, line: line); XCTAssertEqual(h.state.look, l, "crop: the edit changed under the crop", line: line)
    }

    /// spec: with Variations open (V held), X R A don't reach the photo; Esc closes it, nothing applies (R-24).
    private func spec(_ h: Harness, line: UInt = #line) {
        let c = h.state.cur, l = h.state.look, k = h.state.keep
        h.hold("v"); h.wait(0.35)
        XCTAssertEqual(h.state.overlay, "variations", "spec: didn’t open", line: line)
        for key in ["x", "r", "a"] { h.key(key, settle: 0.04) }
        h.key("escape", settle: 0.06); h.release("v"); h.wait(0.5)
        XCTAssertEqual(h.state.keep, k, "spec: keep changed", line: line); XCTAssertEqual(h.state.look, l, "spec: edit changed", line: line)
        XCTAssertEqual(h.state.cur, c, "spec: photo switched", line: line); XCTAssertNil(h.state.overlay, "spec: grid stuck open", line: line)
    }

    /// esc: zoom, then focus; the first Esc leaves focus only, the second goes back to Fit (R-25).
    private func esc(_ h: Harness, line: UInt = #line) {
        h.key("z", settle: 0.3); h.key("h", settle: 0.3); h.layoutPass()
        let z0 = h.state.zoom
        XCTAssertGreaterThan(z0, 1, line: line); XCTAssertTrue(h.model.edit.focus, line: line)
        h.key("escape", settle: 0.3); h.layoutPass()
        XCTAssertFalse(h.model.edit.focus, "esc: first esc should leave focus", line: line); XCTAssertGreaterThan(h.state.zoom, 1, "esc: first esc also left zoom", line: line)
        h.key("escape", settle: 0.3)
        XCTAssertEqual(h.state.zoom, 1, "esc: second esc should fit", line: line)
    }

    /// undoScope: ⌘Z in Edit undoes the edit, not a Cull decision (R-27).
    private func undoScope(_ h: Harness, line: UInt = #line) {
        guard let c = h.state.cur else { return XCTFail("undoScope: no photo", line: line) }
        let k = h.state.keep[c], l0 = h.state.look
        h.key(".", settle: 0.25); let l1 = h.state.look
        h.key("cmd+z", settle: 0.4)
        XCTAssertNotEqual(l1, l0, "undoScope: harness, the nudge did nothing", line: line)
        XCTAssertEqual(h.state.look, l0, "undoScope: ⌘Z didn’t undo the edit", line: line)
        XCTAssertEqual(h.state.keep[c], k, "undoScope: ⌘Z changed the Cull decision", line: line)
    }

    /// enterRhythm: ⏎ every 550 ms through the last photo lands on Save without saving; a
    /// deliberate ⏎ after a pause saves (R-03, R-33).
    private func enterRhythm(_ h: Harness, line: UInt = #line) {
        h.go(3, settle: 1.1)
        for _ in 0..<60 { h.key("right", settle: 0.01) }
        h.wait(0.3)
        let before = h.state.saved?.sig
        var reached = false
        for _ in 0..<8 { h.key("return", settle: 0.55); if h.state.step == "save" { reached = true } }
        XCTAssertTrue(reached, "enterRhythm: never reached Save", line: line)
        XCTAssertEqual(h.state.saved?.sig, before, "enterRhythm: the ⏎ rhythm saved", line: line)
        h.wait(1.3); h.key("return", settle: 0.4)
        XCTAssertNotNil(h.state.saved, "enterRhythm: a deliberate ⏎ after a pause didn’t save", line: line)
        XCTAssertNotEqual(h.state.saved?.sig, before, line: line)
    }

    /// cmdS: ⌘S in Edit opens Save without saving; ⌘S on Save saves (R-35).
    private func cmdS(_ h: Harness, line: UInt = #line) {
        h.go(3, settle: 1.1)
        h.key(".", settle: 0.3)
        let before = h.state.saved?.sig
        h.key("cmd+s", settle: 0.6)
        XCTAssertEqual(h.state.step, "save", "cmdS: ⌘S in Edit", line: line); XCTAssertEqual(h.state.saved?.sig, before, "cmdS: ⌘S in Edit saved", line: line)
        h.key("cmd+s", settle: 0.5)
        XCTAssertNotNil(h.state.saved, line: line); XCTAssertNotEqual(h.state.saved?.sig, before, "cmdS: ⌘S on Save didn’t save", line: line)
    }

    /// hints: Help and the intro never mention T, and list R only as a turn inside Crop (R-26).
    private func hints(line: UInt = #line) {
        let rows = HelpContent.groups.flatMap(\.rows)
        for r in rows {
            let keys = r.keys.components(separatedBy: CharacterSet(charactersIn: " ·,")).filter { !$0.isEmpty }
            XCTAssertFalse(keys.contains("T"), "hints: Help lists T (\(r.keys): \(r.text))", line: line)
            if keys.contains("R") || keys.contains("⇧R") { XCTAssertTrue(r.keys.hasPrefix("C, then"), "hints: R listed outside Crop (\(r.keys): \(r.text))", line: line) }
            XCTAssertNil(r.text.range(of: #"\bT tries|\bT\b.{0,4}(picker|again)"#, options: .regularExpression), "hints: \(r.text)", line: line)
        }
        for c in IntroContent.cards { XCTAssertNil(c.text.range(of: #"\bT\b"#, options: .regularExpression), "hints: intro mentions T: \(c.text)", line: line) }
        XCTAssertEqual(KeyRouter.route(KeyEvent("t"), layers: [.step(.edit)]).action, Action.none, line: line)
        XCTAssertEqual(KeyRouter.route(KeyEvent("r"), layers: [.step(.edit)]).action, .explain(KeyRouter.rExplanation), line: line)
        XCTAssertEqual(KeyRouter.route(KeyEvent("r"), layers: [.step(.edit), .crop]).action, .rotate(1), line: line)
    }

    // MARK: one check per test

    func test_R20_rInEdit_doesNotTurn_explains() { rEdit(prepared()) }
    func test_R28_xIsOutEverywhere_undoRestoresInEach() { xSame(prepared()) }
    func test_R21_tDoesNothing() { tGone(prepared()) }
    func test_R22_typingAValue_noShortcutLeaks() { typing(prepared()) }
    func test_R23_helpHoldsTheKeyboard_escClosesOnlyHelp() { help(prepared()) }
    func test_R24_cropOwnsTheKeyboard_escCancels() { crop(prepared()) }
    func test_R24_variationsOwnTheKeyboard() { spec(prepared()) }
    func test_R25_escBacksOutOneLayer() { esc(prepared()) }
    func test_R27_cmdZUndoesTheEdit_notTheDecision() { undoScope(prepared()) }
    func test_R33_enterRhythmNeverSaves_pausedEnterDoes() { enterRhythm(prepared()) }
    func test_R35_cmdSIsPredictable() { cmdS(prepared()) }
    func test_R26_hintsMatchTheKeys() { hints() }

    /// The HTML run: every check in its order on one model, state carried over; then no errors (cErrors, R-73).
    func test_controlsRun_inOneSession() {
        let h = prepared()
        rEdit(h); xSame(h); tGone(h); typing(h); help(h); crop(h); spec(h); esc(h); undoScope(h); enterRhythm(h); cmdS(h); hints()
        h.checkInvariants("end of the controls run")
        XCTAssertEqual(h.state.errors, 0, "cErrors")
        XCTAssertEqual(h.brokenCopy(), [])
    }

    // MARK: a slider and the keyboard

    /// Esc during a slider drag cancels the drag and nothing else: focus and zoom stay, the value
    /// goes back, no undo step is left (KEYMAP "Drag · Esc cancels", R-25).
    func test_sliderDrag_escCancelsOnlyTheDrag() {
        let h = prepared()
        h.key("z", settle: 0.2); h.key("h", settle: 0.2); h.layoutPass()
        let z = h.state.zoom, l0 = h.state.look, steps = h.model.edits.undoCount
        h.model.sliderDragBegan("con"); h.model.sliderDragMoved(by: 0.2); h.wait(0.05)
        XCTAssertNotEqual(h.state.look["con"], l0["con"], "harness: the drag moved contrast")
        XCTAssertEqual(h.model.edit.draggingKey, "con")
        h.key("escape", settle: 0.1)
        XCTAssertNil(h.model.edit.draggingKey, "the drag is still on")
        XCTAssertEqual(h.state.look, l0, "Esc left the dragged value")
        XCTAssertEqual(h.model.edits.undoCount, steps, "a cancelled drag left an undo step")
        XCTAssertTrue(h.model.edit.focus, "Esc closed focus as well as the drag"); XCTAssertEqual(h.state.zoom, z, "Esc changed the zoom as well")
        XCTAssertTrue(h.model.toast?.text.hasSuffix("unchanged") == true, h.model.toast?.text ?? "nil")
        h.key("escape"); XCTAssertFalse(h.model.edit.focus, "the next Esc is the layer below")
    }

    /// ⌘Z during a drag undoes the whole drag (one step), and ⇧⌘Z brings it back (R-27).
    func test_sliderDrag_cmdZDuringTheDrag_undoesTheWholeDrag() {
        let h = prepared()
        let l0 = h.state.look, steps = h.model.edits.undoCount
        h.model.sliderDragBegan("ev")
        for _ in 0..<3 { h.model.sliderDragMoved(by: 0.04); h.wait(0.03) }
        let dragged = h.state.look
        XCTAssertNotEqual(dragged, l0)
        h.key("cmd+z", settle: 0.1)
        XCTAssertNil(h.model.edit.draggingKey); XCTAssertEqual(h.state.look, l0, "⌘Z left part of the drag")
        XCTAssertEqual(h.model.edits.undoCount, steps)
        h.key("cmd+shift+z", settle: 0.1)
        XCTAssertEqual(h.state.look, dragged, "⇧⌘Z didn’t bring the whole drag back")
        h.checkInvariants("after ⌘Z / ⇧⌘Z of a drag")
    }

    /// → during a drag: the drag stays with the photo it started on; moving on never edits the
    /// next photo (the slider's R-06).
    func test_sliderDrag_photoSwitchMidDrag_newPhotoUntouched() {
        let h = prepared()
        guard let first = h.state.cur else { return XCTFail("no photo") }
        h.model.sliderDragBegan("ev"); h.model.sliderDragMoved(by: 0.1)
        let dragged = h.state.look
        XCTAssertNotEqual(dragged, [:])
        h.key("right", settle: 0.05)
        let second = h.state.cur
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(h.state.look, [:], "harness: the next photo starts as shot")
        h.model.sliderDragMoved(by: 0.1); h.model.sliderDragMoved(by: -0.3); h.model.sliderDragEnded()
        XCTAssertEqual(h.state.look, [:], "the drag edited \(second ?? "nil"), not the photo it started on")
        XCTAssertNil(h.model.edit.draggingKey)
        h.key("left", settle: 0.05)
        XCTAssertEqual(h.state.cur, first); XCTAssertEqual(h.state.look, dragged, "the first photo lost its drag")
        h.checkInvariants("after a photo switch mid-drag")
    }

    /// ⌘2 during a drag: the drag ends and is written at once (R-07); back in Edit it is there.
    func test_sliderDrag_leavingEditMidDrag_writesTheDrag() throws {
        let store = MemoryPersistence()
        let h = prepared(store: store)
        h.model.sliderDragBegan("sat"); h.model.sliderDragMoved(by: 0.15)
        let l = h.state.look
        XCTAssertNotEqual(l, [:])
        h.key("cmd+2", settle: 0)
        XCTAssertNil(h.model.editControls.drag); XCTAssertNil(h.model.edit.draggingKey)
        let stored = try XCTUnwrap(try store.load(shootKey: h.model.shoot.key))
        XCTAssertTrue(stored.looks.values.contains(l), "the drag in progress wasn’t written when Edit was left")
        h.go(3, settle: 1.2)
        XCTAssertEqual(h.state.look, l)
        h.checkInvariants("back in Edit")
    }

    /// A number field and a drag never hold the keyboard together: starting a drag ends typing,
    /// opening a field ends the drag (written, one step each).
    func test_sliderDrag_andTyping_neverBothHold() {
        let h = prepared()
        let steps = h.model.edits.undoCount
        h.model.beginTyping("ev")
        h.model.sliderDragBegan("con")
        XCTAssertNil(h.model.edit.typingKey, "typing stayed on under a drag"); XCTAssertEqual(h.model.edit.draggingKey, "con")
        XCTAssertEqual(h.model.layers.contains(.textField), false)
        h.model.sliderDragMoved(by: 0.1)
        let con = h.state.look["con"]
        XCTAssertNotNil(con)
        h.model.beginTyping("tint")
        XCTAssertNil(h.model.edit.draggingKey, "the drag stayed on under a field"); XCTAssertEqual(h.model.edit.typingKey, "tint")
        h.model.commitTyping("12")
        XCTAssertEqual(h.state.look["tint"], 12); XCTAssertEqual(h.state.look["con"], con, "typing lost the drag")
        XCTAssertEqual(h.model.edits.undoCount, steps + 2, "one step for the drag, one for the typed value")
        h.key("cmd+z"); XCTAssertNil(h.state.look["tint"]); XCTAssertEqual(h.state.look["con"], con)
        h.key("cmd+z"); XCTAssertNil(h.state.look["con"])
        // A swipe over a slider while a field is open does nothing.
        h.model.beginTyping("ev")
        h.model.sliderSwipe("ev", by: 80)
        XCTAssertNil(h.state.look["ev"], "a swipe edited under an open field")
        h.model.cancelTyping()
    }

    /// R and X during a drag: R only explains (the drag goes on); X ends the drag (written on
    /// that photo), takes the photo out, and ⌘Z brings it back with its edit (R-20, R-28).
    func test_sliderDrag_rAndXMidDrag() {
        let h = prepared()
        guard let id = h.state.cur else { return XCTFail("no photo") }
        h.model.sliderDragBegan("ev"); h.model.sliderDragMoved(by: 0.1)
        let l = h.state.look
        h.key("r", settle: 0.05)
        XCTAssertEqual(h.model.toast?.text, KeyRouter.rExplanation)
        XCTAssertEqual(h.model.edit.draggingKey, "ev", "R ended the drag"); XCTAssertEqual(h.state.look, l)
        h.key("x", settle: 0.05)
        XCTAssertNil(h.model.edit.draggingKey); XCTAssertEqual(h.state.keep[id], false); XCTAssertNotEqual(h.state.cur, id)
        h.model.sliderDragMoved(by: 0.3)
        XCTAssertEqual(h.state.look, [:], "the ended drag reached the next photo")
        h.key("cmd+z", settle: 0.05)
        XCTAssertEqual(h.state.cur, id); XCTAssertEqual(h.state.keep[id], true); XCTAssertEqual(h.state.look, l, "the photo came back without its edit")
        h.checkInvariants("after X mid-drag and ⌘Z")
    }

    /// Nudges act on the setting under the pointer, else on the one [ ] chose; the pointer
    /// leaving gives the keyboard's choice back.
    func test_nudges_pointerBeatsTheKeyboardsChoice_thenGivesItBack() {
        let h = prepared()
        h.key("]")                                                                // ev → wb
        XCTAssertEqual(h.model.activeSettingKey, "wb")
        h.model.edit.hoverKey = "sat"
        h.key(".")
        XCTAssertEqual(h.state.look["sat"], 1); XCTAssertNil(h.state.look["wb"], "the keyboard's choice moved under the pointer")
        h.model.edit.hoverKey = nil
        h.key(".")
        XCTAssertNotNil(h.state.look["wb"], "with no pointer, the nudge goes to the chosen setting"); XCTAssertEqual(h.state.look["sat"], 1)
        h.key("0")
        XCTAssertNil(h.state.look["wb"], "0 resets the chosen setting"); XCTAssertEqual(h.state.look["sat"], 1)
        h.checkInvariants("after the nudges")
    }

    /// A seeded storm of slider gestures and keys together (drags, swipes, typed values, nudges,
    /// Esc, ⌘Z, photo switches, V, C, Help): after every event the drag, the field and the
    /// overlays agree, and nothing is left half-done.
    func test_slidersAndKeysStorm_seeded_noHalfStates() {
        let h = prepared(); h.layoutPass()
        var rng = SuiteRNG(seed: 0x511D)
        let keys = [",", ".", "shift+.", "[", "]", "0", "escape", "cmd+z", "cmd+shift+z", "right", "left", "v", "c", "?", "x", "r", "a", "z", "h", "return", "\\"]
        for i in 0..<800 {
            let setting = h.model.visibleSettings.isEmpty ? "ev" : rng.pick(h.model.visibleSettings.map(\.key))
            let what: String
            switch rng.int(0..<10) {
            case 0: h.model.sliderDragBegan(setting); what = "drag \(setting)"
            case 1: h.model.sliderDragMoved(by: rng.double(-0.2...0.2), fine: rng.chance(0.3), finer: rng.chance(0.1)); what = "drag moves"
            case 2: h.model.sliderDragEnded(cancel: rng.chance(0.2)); what = "drag ends"
            case 3: h.model.sliderSwipe(setting, by: rng.double(-40...40)); what = "swipe \(setting)"
            case 4: h.model.beginTyping(setting); what = "type into \(setting)"
            case 5:
                if h.model.edit.typingKey != nil { h.model.commitTyping(rng.pick(["5", "-20", "x", "999"])); what = "commit typing" }
                else { h.model.edit.hoverKey = rng.chance(0.5) ? setting : nil; what = "pointer over \(h.model.edit.hoverKey ?? "nothing")" }
            case 6: h.model.setSection(rng.pick(EditSection.allCases)); what = "section"
            default:
                let k = rng.pick(keys)
                if h.model.edit.typingKey != nil, !k.contains("+"), rng.chance(0.7) {
                    // What the window's key monitor does while the field has the keyboard.
                    h.model.windowKey(KeyEvent(k), typing: true) { h.model.cancelTyping() }; what = "\(k) typed in the field"
                }
                else { h.key(k, settle: rng.pick([0, 0.01, 0.3])); what = "key \(k)" }
            }
            if rng.chance(0.3) { h.wait(rng.pick([0.05, 0.3])) }
            h.layoutPass()
            if h.model.step != .edit { h.go(3, settle: 1.2); h.layoutPass() }
            guard h.checkInvariants("event \(i): \(what)") else { return }
            if h.model.edit.typingKey != nil, h.model.editControls.drag != nil { return XCTFail("event \(i): \(what): a field and a drag both hold the keyboard") }
        }
        h.model.sliderDragEnded(); h.model.cancelTyping()
        XCTAssertEqual(h.state.errors, 0)
    }
}
