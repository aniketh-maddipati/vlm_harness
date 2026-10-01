import XCTest
@testable import LuminaCore

/// WP-5, headless: the Edit rules the controls column owns (R-03, R-07, R-08, R-20, R-22, R-27,
/// R-28, R-86) and what its keys and pointer gestures do. A model on a virtual clock, read through
/// `debug.state`, as the UI tests read it.
@MainActor
final class WP5EditTests: XCTestCase {
    /// Copied, `n` kept, in Edit.
    private func inEdit(_ n: Int = 6, card: String = "demo117", store: (any PersistenceStore)? = nil) -> Harness {
        let h = Harness(card: card, store: store)
        h.startCulling(); h.keepN(n); h.wait(0.3); h.go(3, settle: 1.2)
        return h
    }
    private var toast: (Harness) -> String { { $0.model.toast?.text ?? "" } }

    // MARK: rules

    func test_R03_enterOnTheLastPhoto_landsOnSave_doesNotSave() {
        let h = inEdit()
        for _ in 0..<40 { h.key("right", settle: 0.02) }
        XCTAssertEqual(h.state.cur, h.model.keptIDs.last)
        for i in 0..<6 { h.key("return", settle: 0.03, isRepeat: i > 0) }
        h.wait(0.6)
        XCTAssertEqual(h.state.step, "save"); XCTAssertNil(h.state.saved, "R-03 held ⏎ saved")
        // Six separate presses 30 ms apart don't save either: Save's own ⏎ guard holds.
        let g = inEdit()
        for _ in 0..<40 { g.key("right", settle: 0.02) }
        for _ in 0..<6 { g.key("return", settle: 0.03) }
        g.wait(0.6)
        XCTAssertEqual(g.state.step, "save"); XCTAssertNil(g.state.saved, "R-03 ⏎ mash saved")
        XCTAssertTrue(g.model.edits.done.contains(g.model.edits.key(for: g.model.keptIDs.last!, decisions: g.model.decisions)), "⏎ marks the photo done")
    }

    func test_R03_enterMarksDoneAndMovesOn() {
        let h = inEdit()
        let first = h.state.cur!
        h.key("return")
        XCTAssertEqual(h.state.step, "edit"); XCTAssertEqual(h.state.cur, h.model.keptIDs[1])
        XCTAssertTrue(h.model.edits.done.contains(h.model.edits.key(for: first, decisions: h.model.decisions)))
    }

    func test_R07_editThenLeaveWithin50ms_isInTheStore() throws {
        let store = MemoryPersistence()
        let h = inEdit(4, store: store)
        let before = h.state.look
        for _ in 0..<3 { h.key(".", settle: 0.015) }
        let after = h.state.look, cur = h.state.cur!
        XCTAssertNotEqual(after, before, "harness: nudge did nothing")
        h.key("cmd+2", settle: 0.01)
        let snap = try XCTUnwrap(store.load(shootKey: h.model.shoot.key))
        XCTAssertEqual(snap.looks[cur], after, "R-07 the edit made just before ⌘2 isn't stored")
        // Relaunch on the same store.
        let again = Harness(store: store)
        again.go(3, settle: 1.2)
        XCTAssertEqual(again.state.cur, cur); XCTAssertEqual(again.state.look, after, "R-07 edit lost over a relaunch")
    }

    func test_R07_dragInProgress_isFlushedOnLeave() throws {
        let store = MemoryPersistence()
        let h = inEdit(4, store: store), m = h.model, cur = h.state.cur!
        m.sliderDragBegan("con"); m.sliderDragMoved(by: 0.2)
        let mid = h.state.look
        XCTAssertEqual(mid["con"], 40)
        XCTAssertNil(try store.load(shootKey: m.shoot.key)?.looks[cur]?["con"], "a drag's writes are debounced")
        h.key("cmd+2", settle: 0.01)     // 10 ms later, not the 250 ms of the debounce
        XCTAssertEqual(try store.load(shootKey: m.shoot.key)?.looks[cur], mid, "R-07 the drag wasn't flushed on leaving Edit")
        XCTAssertNil(m.edit.draggingKey); XCTAssertNil(m.editControls.drag)
        // The pointer is still down when the step changed: later moves do nothing.
        m.sliderDragMoved(by: 0.2); m.sliderDragEnded()
        XCTAssertEqual(m.edits.looks[cur], mid)
    }

    func test_R07_dragWritesAreCoalesced_thenWritten() throws {
        let store = MemoryPersistence()
        let h = inEdit(4, store: store), m = h.model, cur = h.state.cur!
        let r0 = m.revision
        m.sliderDragBegan("sh")
        for _ in 0..<20 { m.sliderDragMoved(by: 0.01) }
        XCTAssertEqual(m.revision, r0, "every tick of a drag announced a change")
        h.wait(0.3)
        XCTAssertEqual(m.revision, r0 + 1, "a long drag is written while it goes")
        XCTAssertEqual(try store.load(shootKey: m.shoot.key)?.looks[cur]?["sh"], 40)
        m.sliderDragMoved(by: 0.05); m.sliderDragEnded()
        XCTAssertEqual(try store.load(shootKey: m.shoot.key)?.looks[cur]?["sh"], 50, "the end of a drag writes at once")
    }

    func test_R08_outInEdit_undoInCull_doesNotRevive() {
        let h = inEdit()
        let c = h.state.cur!
        h.key("x", settle: 0.15)
        XCTAssertEqual(h.state.keep[c], false); XCTAssertEqual(h.state.cur, h.model.keptIDs.first, "X moves to the next keeper")
        h.go(2, settle: 0.5); h.key("cmd+z", settle: 0.3)
        XCTAssertEqual(h.state.keep[c], false, "R-08 Cull ⌘Z brought back a photo taken out in Edit")
        XCTAssertEqual(h.state.kept, 5)
    }

    func test_R20_rInEdit_changesNothing_andExplains() {
        let h = inEdit()
        h.key(".")
        let s0 = h.state
        for _ in 0..<4 { h.key("r") }
        XCTAssertEqual(h.state.look, s0.look); XCTAssertEqual(h.state.cur, s0.cur); XCTAssertEqual(h.state.keep, s0.keep)
        XCTAssertEqual(toast(h), KeyRouter.rExplanation)
        XCTAssertTrue(toast(h).contains("R keeps photos in Cull"))
    }

    func test_R22_typingAValue_noShortcutFires() {
        let h = inEdit(), m = h.model
        XCTAssertEqual(m.beginTyping("ev"), "0")
        XCTAssertEqual(m.edit.typingKey, "ev")
        let s0 = h.state
        for k in ["r", "x", "z", "v", "0", "right", "left", ".", ",", "a", "=", "w", "c", "h", "return", "escape", "shift+/"] { h.key(k) }
        let s1 = h.state
        XCTAssertEqual(s1.cur, s0.cur, "photo switched"); XCTAssertEqual(s1.zoom, s0.zoom, "zoomed")
        XCTAssertEqual(s1.keep, s0.keep, "keep changed"); XCTAssertEqual(s1.look, s0.look, "look changed")
        XCTAssertNil(s1.overlay); XCTAssertEqual(s1.step, "edit")
        XCTAssertEqual(m.edit.typingKey, "ev", "the field is still up: the field itself ends typing")
        m.cancelTyping()
        XCTAssertNil(m.edit.typingKey); XCTAssertEqual(h.state.look, s0.look)
        h.key("."); XCTAssertEqual(h.state.look["ev"] ?? 0, 0.05, accuracy: 0.001, "shortcuts work again after typing")
    }

    func test_R27_cmdZInEdit_undoesTheEdit_notTheDecision() {
        let h = inEdit(30)
        let c = h.state.cur!, k = h.state.keep[c], look0 = h.state.look, kept = h.state.kept
        h.key(".", settle: 0.25); XCTAssertNotEqual(h.state.look, look0)
        h.key("cmd+z", settle: 0.4)
        XCTAssertEqual(h.state.look, look0); XCTAssertEqual(h.state.keep[c], k); XCTAssertEqual(h.state.kept, kept)
        // With nothing left to undo, ⌘Z still never reaches Cull's decisions.
        h.key("cmd+z"); h.key("cmd+z")
        XCTAssertEqual(h.state.kept, kept, "R-27 Edit's ⌘Z undid a Cull decision"); XCTAssertEqual(toast(h), "Nothing to undo")
        h.key("cmd+shift+z"); XCTAssertEqual(h.state.look["ev"] ?? 0, 0.05, accuracy: 0.001, "redo")
    }

    func test_R28_xIsOutInEdit_undoRestoresThePhotoAndItsDecision() {
        let h = inEdit(30)
        let e = h.state.cur!, e0 = h.state.keep[e]
        h.key("x", settle: 0.7)
        XCTAssertEqual(h.state.keep[e], false); XCTAssertNotEqual(h.state.cur, e)
        XCTAssertTrue(toast(h).contains("⌘Z brings it back"))
        h.key("cmd+z", settle: 0.7)
        XCTAssertEqual(h.state.keep[e], e0); XCTAssertEqual(h.state.cur, e, "⌘Z brings the photo back on screen")
        h.key("cmd+shift+z", settle: 0.3)
        XCTAssertEqual(h.state.keep[e], false, "redo takes it out again"); XCTAssertEqual(h.state.cur, h.model.keptIDs.first)
        h.key("cmd+z")
        // An edit and an Out undo in order.
        h.key("."); h.key("x"); h.key("cmd+z"); XCTAssertEqual(h.state.keep[e], true); XCTAssertEqual(h.state.look["ev"] ?? 0, 0.05, accuracy: 0.001)
        h.key("cmd+z"); XCTAssertEqual(h.state.look, [:])
    }

    func test_xOnTheOnlyKeeper_leavesEditEmpty_andUndoBringsItBack() {
        let h = inEdit(1)
        let c = h.state.cur!
        h.key("x")
        XCTAssertNil(h.state.cur); XCTAssertEqual(h.state.kept, 0)
        for k in [".", "a", "=", "0", "shift+0", "return", "x", "w", "cmd+c", "cmd+v"] { h.key(k) }   // nothing to act on: no crash, no change
        XCTAssertEqual(h.state.step, "edit"); XCTAssertEqual(h.state.looksCount, 0)
        h.key("cmd+z")
        XCTAssertEqual(h.state.cur, c); XCTAssertEqual(h.state.kept, 1)
        XCTAssertEqual(h.state.errors, 0)
    }

    func test_R86_300EditedPhotos_under2MB() {
        let h = inEdit(1500, card: "demo:1500")
        XCTAssertEqual(h.state.kept, 1500)
        for _ in 0..<300 { h.key(".", settle: 0.01); h.key("return", settle: 0.01) }
        h.wait(1.2)
        // Kept burst frames share one edit, so there are fewer stored looks than edited photos.
        XCTAssertTrue(h.model.keptIDs.prefix(300).allSatisfy { h.model.edits.isEdited($0, decisions: h.model.decisions) }, "every photo of the 300 is edited")
        XCTAssertGreaterThan(h.state.looksCount, 100)
        XCTAssertLessThan(h.state.lookBytes, 2 * 1024 * 1024, "R-86 edits use \(h.state.lookBytes / 1024) KB")
        XCTAssertLessThan(h.state.lookBytes, 40 * h.state.looksCount, "only what differs from the defaults is stored")
        // 300 heavy edits (every setting moved) still fit.
        let e = EditStore(shoot: h.model.shoot), d = h.model.decisions
        var heavy: Look = [:]; for s in EditSetting.all { heavy[s.key] = s.clamp(s.def + s.step * 7) }
        for id in h.model.keptIDs.prefix(300) { e.setLook(heavy, on: id, decisions: d) }
        XCTAssertLessThan(e.lookBytes, 2 * 1024 * 1024, "R-86 300 full edits use \(e.lookBytes / 1024) KB")
    }

    // MARK: the store

    func test_store_onlyNonDefaultsAreKept() {
        let e = EditStore(shoot: .demo117), d = DecisionStore(ids: e.shoot.photos.map(\.id)), id = e.shoot.photos[0].id
        e.setLook(["ev": 0, "wb": EditSetting.asShotKelvin, "shp": 40, "vMid": 50, "con": 12, "nr": .nan], on: id, decisions: d)
        XCTAssertEqual(e.looks[id], ["con": 12])
        e.set("con", 0, on: id, decisions: d)
        XCTAssertNil(e.looks[id], "an edit with nothing in it isn't stored"); XCTAssertEqual(e.looks.count, 0)
        XCTAssertFalse(e.isEdited(id, decisions: d))
    }

    func test_store_undoRedo_200Deep() {
        let e = EditStore(shoot: .demo117), d = DecisionStore(ids: e.shoot.photos.map(\.id)), id = e.shoot.photos[0].id
        for i in 1...250 { e.set("tint", Double(i % 100 + 1), on: id, decisions: d) }
        var n = 0; while e.canUndo { e.undo(); n += 1 }
        XCTAssertEqual(n, EditStore.depth)
        XCTAssertEqual(e.look(id, decisions: d)["tint"], 51, "undo stops 200 steps back")
        n = 0; while e.canRedo { e.redo(); n += 1 }
        XCTAssertEqual(n, 200); XCTAssertEqual(e.look(id, decisions: d)["tint"], 51)
        e.undo(); e.set("tint", 5, on: id, decisions: d); XCTAssertFalse(e.canRedo, "a new edit clears redo")
    }

    func test_store_burstFramesShareOneEdit_onlyWhenTwoAreKept() {
        let e = EditStore(shoot: .demo117), g = e.shoot.bursts.first!
        let d = DecisionStore(ids: e.shoot.photos.map(\.id))
        d.mark(g.ids[0], keep: true)
        XCTAssertEqual(e.key(for: g.ids[0], decisions: d), g.ids[0], "one kept frame keeps its own edit")
        e.set("ev", 1, on: g.ids[0], decisions: d)
        XCTAssertNil(e.look(g.ids[1], decisions: d)["ev"])
        d.mark(g.ids[1], keep: true)
        XCTAssertEqual(e.key(for: g.ids[0], decisions: d), g.id); XCTAssertEqual(e.sharedBy(g.ids[0], decisions: d), 2)
        e.set("ev", 0.5, on: g.ids[0], decisions: d)
        XCTAssertEqual(e.look(g.ids[1], decisions: d)["ev"], 0.5)
        XCTAssertEqual(e.looks.keys.filter { $0 == g.id }.count, 1)
    }

    func test_store_aDragIsOneUndoStep() {
        let e = EditStore(shoot: .demo117), d = DecisionStore(ids: e.shoot.photos.map(\.id)), id = e.shoot.photos[0].id
        e.set("ev", 0.5, on: id, decisions: d)                     // a nudge
        e.beginCoalescing()
        for v in [10.0, 20, 30] { e.set("con", v, on: id, decisions: d, coalesce: true) }
        e.endCoalescing()
        e.beginCoalescing()
        for v in [40.0, 50] { e.set("con", v, on: id, decisions: d, coalesce: true) }
        e.endCoalescing()
        XCTAssertEqual(e.undoCount, 3, "nudge, drag, drag")
        e.undo(); XCTAssertEqual(e.look(id, decisions: d), ["ev": 0.5, "con": 30])
        e.undo(); XCTAssertEqual(e.look(id, decisions: d), ["ev": 0.5], "the drag never folds into the step before it")
        e.undo(); XCTAssertEqual(e.look(id, decisions: d), [:])
    }

    // MARK: keys

    func test_nudges_stepsAndCoarse_andTemperatureBy2Percent() {
        let h = inEdit()
        h.key("."); h.key("."); h.key(".")
        XCTAssertEqual(h.state.look, ["ev": 0.15]); XCTAssertEqual(toast(h), "Exposure +0.15 EV")
        h.key(","); XCTAssertEqual(h.state.look, ["ev": 0.1])
        h.key("shift+."); XCTAssertEqual(h.state.look, ["ev": 0.35])
        h.key("shift+,"); h.key(","); h.key(",")
        XCTAssertEqual(h.state.look, [:], "back at the default: nothing stored")
        h.key("]"); XCTAssertEqual(h.model.edit.activeKey, "wb"); XCTAssertEqual(toast(h), "Temperature")
        h.key("."); XCTAssertEqual(h.state.look, ["wb": 5300]); XCTAssertEqual(toast(h), "Temperature 5300 K")
        h.key("cmd+z"); h.key("shift+."); XCTAssertEqual(h.state.look, ["wb": 5720])
        h.key("["); h.key("["); XCTAssertEqual(h.model.edit.activeKey, "sat", "[ wraps around the section")
        h.key("."); XCTAssertEqual(h.state.look["sat"], 1)
        // The setting under the pointer wins over the chosen one.
        h.model.edit.hoverKey = "hl"
        h.key(","); XCTAssertEqual(h.state.look["hl"], -1); XCTAssertEqual(toast(h), "Highlights −1")
        // The ends hold.
        for _ in 0..<60 { h.key("shift+,", settle: 0.01) }
        XCTAssertEqual(h.state.look["hl"], -100)
        h.model.edit.hoverKey = nil
    }

    func test_nudge_actsOnTheOpenSection() {
        let h = inEdit(), m = h.model
        m.setSection(.effects)
        XCTAssertEqual(m.targetKey, "vig")
        h.key("."); XCTAssertEqual(h.state.look, ["vig": 1], "a nudge never moves a setting that isn't on screen")
        m.setSection(.colour); XCTAssertEqual(m.targetKey, "sat_red")
        h.key("]"); XCTAssertEqual(m.targetKey, "sat_orange")
        m.setColourAxis("hue"); XCTAssertEqual(m.targetKey, "hue_orange", "the chosen colour stays chosen")
        h.key("."); XCTAssertEqual(h.state.look["hue_orange"], 1); XCTAssertEqual(toast(h), "Orange hue +1")
        XCTAssertEqual(m.visibleSettings.count, 8)
        m.setSection(.curve); XCTAssertEqual(m.visibleSettings.map(\.key), ["cDark", "cMid", "cLight"])
        XCTAssertEqual(m.changedCount(.colour), 1); XCTAssertEqual(m.changedCount(.effects), 1); XCTAssertEqual(m.changedCount(.light), 0)
    }

    func test_reset_andResetAll() {
        let h = inEdit()
        h.key("."); h.key("]"); h.key(".")
        XCTAssertEqual(h.state.look, ["ev": 0.05, "wb": 5300])
        h.key("0"); XCTAssertEqual(h.state.look, ["ev": 0.05]); XCTAssertEqual(toast(h), "Temperature reset")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, ["ev": 0.05, "wb": 5300])
        h.key("shift+0"); XCTAssertEqual(h.state.look, [:]); XCTAssertEqual(toast(h), "As shot"); XCTAssertEqual(h.model.editTag, "As shot")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, ["ev": 0.05, "wb": 5300], "reset all is one undo step")
        h.model.setSection(.light); h.model.resetSection()
        XCTAssertEqual(h.state.look, [:]); XCTAssertEqual(toast(h), "Light reset")
    }

    func test_auto_pressingAgainUndoesIt() {
        let h = inEdit(), m = h.model
        h.key(".")
        let before = h.state.look
        h.key("a")
        let auto = h.state.look
        XCTAssertNotEqual(auto, before); XCTAssertEqual(auto["hl"], -22); XCTAssertEqual(auto["sh"], 18); XCTAssertEqual(auto["wb"], 5600)
        XCTAssertEqual(m.editTag, "Auto"); XCTAssertTrue(m.autoCanUndo); XCTAssertEqual(toast(h), "Auto applied. Press A again to undo.")
        h.key("a")
        XCTAssertEqual(h.state.look, before, "A again undoes Auto"); XCTAssertEqual(m.editTag, "Edited"); XCTAssertEqual(toast(h), "Auto undone")
        h.key("a"); XCTAssertEqual(h.state.look, auto)
        h.key(","); XCTAssertEqual(m.editTag, "Edited"); XCTAssertFalse(m.autoCanUndo)
        let moved = h.state.look
        h.key("a"); XCTAssertEqual(h.state.look["hl"], -22, "after another change, A applies Auto again")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, moved, "Auto is one undo step")
        // A held down is one press.
        h.key("a", isRepeat: true); XCTAssertEqual(h.state.look, moved)
        // Auto is the same for the same photo.
        XCTAssertEqual(AutoLook.make(for: m.current!), AutoLook.make(for: m.current!))
    }

    func test_sameAsLast() {
        let h = inEdit()
        h.key("="); XCTAssertEqual(h.state.look, [:]); XCTAssertEqual(toast(h), "Nothing to repeat yet. Edit a photo first.")
        h.key("."); h.key("."); h.model.setValue("con", 20)
        let look = h.state.look
        h.key("right"); XCTAssertEqual(h.state.look, [:], "the next photo starts as shot")
        h.key("="); XCTAssertEqual(h.state.look, look); XCTAssertEqual(toast(h), "Same as last"); XCTAssertEqual(h.model.editTag, "Edited")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, [:], "one undo step")
        // Reset all isn't an edit to repeat.
        h.key("."); h.key("shift+0"); h.key("=")
        XCTAssertEqual(h.state.look, ["ev": 0.05])
    }

    func test_copyPaste_keepsTheTargetsCrop() {
        let h = inEdit(), m = h.model
        h.key("cmd+v"); XCTAssertEqual(toast(h), "Copy an edit first"); XCTAssertEqual(h.state.look, [:])
        m.setValue("ev", 0.5); m.setValue("sat", -20)
        m.edits.setLook(m.currentLook.merging([CropKey.w: 0.5, CropKey.angle: 2]) { $1 }, on: m.editCur!, decisions: m.decisions)
        h.key("cmd+c"); XCTAssertEqual(toast(h), "Copied 2 settings"); XCTAssertEqual(m.editControls.clipboard, ["ev": 0.5, "sat": -20])
        h.key("right")
        m.edits.setLook([CropKey.x: 0.1, "tint": 9], on: m.editCur!, decisions: m.decisions)
        h.key("cmd+v")
        XCTAssertEqual(h.state.look, ["ev": 0.5, "sat": -20, CropKey.x: 0.1], "paste replaces the settings and leaves the crop"); XCTAssertEqual(toast(h), "Pasted")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, [CropKey.x: 0.1, "tint": 9])
    }

    func test_pickWhite() {
        let h = inEdit(), m = h.model
        m.pickWhite(at: CGPoint(x: 0.5, y: 0.5)); XCTAssertEqual(h.state.look, [:], "a click does nothing unless the picker is on")
        m.setValue("tint", 30)
        h.key("w"); XCTAssertTrue(m.edit.pickingWhite); XCTAssertEqual(toast(h), "Click something that should be neutral grey.")
        h.key("w"); XCTAssertFalse(m.edit.pickingWhite); XCTAssertEqual(toast(h), "Picker off")
        h.key("w"); m.pickWhite(at: CGPoint(x: 0.3, y: 0.5))
        XCTAssertFalse(m.edit.pickingWhite); XCTAssertEqual(h.state.look, ["wb": 5600], "sets temperature, clears tint"); XCTAssertEqual(toast(h), "White set · 5600 K")
        h.key("cmd+z"); XCTAssertEqual(h.state.look, ["tint": 30], "one undo step")
        h.key("w"); h.key("escape"); XCTAssertFalse(m.edit.pickingWhite, "Esc switches the picker off")
        h.key("w"); h.go(2); XCTAssertFalse(m.edit.pickingWhite, "leaving Edit switches the picker off")
    }

    // MARK: the pointer

    func test_typedValue_clampsAndIgnoresJunk() {
        let h = inEdit(), m = h.model
        func type(_ key: String, _ text: String) { m.beginTyping(key); m.commitTyping(text) }
        type("ev", "1.23"); XCTAssertEqual(h.state.look["ev"], 1.25, "onto the step")
        XCTAssertNil(m.edit.typingKey)
        type("ev", "99"); XCTAssertEqual(h.state.look["ev"], 5); XCTAssertEqual(toast(h), "Exposure: max +5.00 EV. Set to the limit.")
        type("ev", "−7"); XCTAssertEqual(h.state.look["ev"], -5); XCTAssertEqual(toast(h), "Exposure: min −5.00 EV. Set to the limit.")
        type("ev", "abc"); XCTAssertEqual(h.state.look["ev"], -5, "junk is ignored"); XCTAssertEqual(toast(h), "Type a number, like −5.00 EV.")
        type("ev", ""); XCTAssertEqual(h.state.look["ev"], -5)
        type("ev", "nan"); type("ev", "inf"); type("ev", "--3"); type("ev", "K"); XCTAssertEqual(h.state.look["ev"], -5)
        type("ev", "+0.5 EV"); XCTAssertEqual(h.state.look["ev"], 0.5, "units are fine")
        type("wb", "6504 K"); XCTAssertEqual(h.state.look["wb"], 6500)
        type("wb", "100"); XCTAssertEqual(h.state.look["wb"], 2500)
        type("wb", "99999"); XCTAssertEqual(h.state.look["wb"], 10000)
        type("shp", "-20"); XCTAssertEqual(h.state.look["shp"], 0)
        type("con", "250"); XCTAssertEqual(h.state.look["con"], 100)
        type("con", "0"); XCTAssertNil(h.state.look["con"], "typing the default clears the setting")
        XCTAssertEqual(m.beginTyping("wb"), "10000"); m.cancelTyping()
        XCTAssertEqual(m.beginTyping("ev"), "0.5"); m.cancelTyping(); XCTAssertEqual(h.state.look["ev"], 0.5, "Esc changes nothing")
        // One typed value is one undo step.
        type("tint", "12"); h.key("cmd+z"); XCTAssertNil(h.state.look["tint"])
        for (_, v) in h.state.look { XCTAssertTrue(v.isFinite) }
    }

    func test_drag_isOneUndoStep_snapsToTheDefault_escCancels() {
        let h = inEdit(), m = h.model
        m.setValue("con", 10)
        let n0 = m.edits.undoCount
        m.sliderDragBegan("con")
        XCTAssertEqual(m.edit.draggingKey, "con")
        XCTAssertEqual(m.edits.undoCount, n0, "pointer down alone changes nothing")
        for _ in 0..<10 { m.sliderDragMoved(by: 0.02) }
        XCTAssertEqual(h.state.look["con"], 50); XCTAssertEqual(m.edits.undoCount, n0 + 1)
        m.sliderDragEnded()
        XCTAssertNil(m.edit.draggingKey); XCTAssertEqual(toast(h), "Contrast +50")
        h.key("cmd+z"); XCTAssertEqual(h.state.look["con"], 10, "one ⌘Z undoes the whole drag, and only the drag")
        h.key("cmd+shift+z"); XCTAssertEqual(h.state.look["con"], 50)

        // ⇧ a quarter of the speed, ⌥ a tenth.
        m.sliderDragBegan("con"); m.sliderDragMoved(by: 0.2, fine: true); XCTAssertEqual(h.state.look["con"], 60)
        m.sliderDragMoved(by: 0.2, finer: true); XCTAssertEqual(h.state.look["con"], 64); m.sliderDragEnded()

        // Within 1.2 % of the default it snaps there.
        m.sliderDragBegan("con"); m.sliderDragMoved(by: -0.315)
        XCTAssertNil(h.state.look["con"], "snapped to the default"); XCTAssertEqual(m.editControls.drag?.snapped, true)
        m.sliderDragMoved(by: -0.02); XCTAssertEqual(h.state.look["con"], -3); XCTAssertEqual(m.editControls.drag?.snapped, false)
        // The ends hold however far the pointer goes.
        m.sliderDragMoved(by: -5); XCTAssertEqual(h.state.look["con"], -100); m.sliderDragMoved(by: 9); XCTAssertEqual(h.state.look["con"], 100)
        m.sliderDragEnded()

        // Esc: the start value comes back and no undo step is left behind.
        let n1 = m.edits.undoCount, look1 = h.state.look
        m.sliderDragBegan("ev"); m.sliderDragMoved(by: 0.3); XCTAssertNotEqual(h.state.look, look1)
        XCTAssertTrue(m.cancelSliderDrag())
        XCTAssertEqual(h.state.look, look1, "Esc restores the start value"); XCTAssertEqual(m.edits.undoCount, n1); XCTAssertEqual(toast(h), "Exposure unchanged")
        XCTAssertNil(m.edit.draggingKey); XCTAssertFalse(m.cancelSliderDrag())
        m.sliderDragMoved(by: 0.3); XCTAssertEqual(h.state.look, look1, "moves after the cancel do nothing")
    }

    func test_drag_temperatureIsOnALogScale() {
        let wb = EditSetting.byKey["wb"]!
        XCTAssertEqual(SliderScale.position(wb, 2500), 0); XCTAssertEqual(SliderScale.position(wb, 10000), 1)
        XCTAssertEqual(SliderScale.position(wb, 5000), 0.5, accuracy: 0.0001, "the geometric middle is the middle of the track")
        XCTAssertEqual(SliderScale.value(wb, at: 0.5), 5000); XCTAssertEqual(SliderScale.value(wb, at: 0.25), 3540)
        let ev = EditSetting.byKey["ev"]!
        XCTAssertEqual(SliderScale.position(ev, 0), 0.5); XCTAssertEqual(SliderScale.value(ev, at: 0.515), 0.15)
        for s in EditSetting.all { for q in stride(from: 0.0, through: 1.0, by: 0.05) {
            let v = SliderScale.value(s, at: q)
            XCTAssertTrue(v >= s.min && v <= s.max, s.key); XCTAssertEqual(SliderScale.position(s, v), q, accuracy: 0.03, s.key)
        } }
        let h = inEdit(), m = h.model
        m.sliderDragBegan("wb"); m.sliderDragMoved(by: 0.25); m.sliderDragEnded()
        XCTAssertEqual(h.state.look["wb"], 7350, "a quarter of the track above 5200 K")
    }

    func test_swipe_adjusts_oneUndoStepPerSwipe() {
        let h = inEdit(), m = h.model
        m.sliderSwipe("sh", by: 10); XCTAssertNil(h.state.look["sh"], "under 16pt: not a step yet")
        m.sliderSwipe("sh", by: 10); XCTAssertEqual(h.state.look["sh"], 1)
        m.sliderSwipe("sh", by: 50); XCTAssertEqual(h.state.look["sh"], 4)
        m.sliderSwipe("sh", by: -42); XCTAssertEqual(h.state.look["sh"], 2)
        h.wait(0.6)
        m.sliderSwipe("sh", by: 32); XCTAssertEqual(h.state.look["sh"], 4)
        h.key("cmd+z"); XCTAssertEqual(h.state.look["sh"], 2, "the second swipe is its own step")
        h.key("cmd+z"); XCTAssertNil(h.state.look["sh"], "the first swipe was one step")
    }

    func test_tagsAndTitle() {
        let h = inEdit(), m = h.model
        XCTAssertEqual(m.editTag, "As shot"); XCTAssertEqual(m.editTitle, m.current!.file)
        h.key("."); XCTAssertEqual(m.editTag, "Edited")
        h.key("cmd+z"); XCTAssertEqual(m.editTag, "As shot"); XCTAssertNil(m.edits.tags[m.editCur!])
        h.key("a"); XCTAssertEqual(m.editTag, "Auto"); h.key("cmd+z"); XCTAssertEqual(m.editTag, "As shot")
        XCTAssertFalse(m.editIsLast); XCTAssertTrue(m.editIsFirst)
        m.editNext(); XCTAssertEqual(h.state.cur, m.keptIDs[1])
        for _ in 0..<10 { h.key("right") }
        XCTAssertTrue(m.editIsLast)
        m.editNext(); XCTAssertEqual(h.state.step, "edit", "the Next button stays in Edit on the last photo"); XCTAssertEqual(toast(h), "Last photo · Save when you’re ready (⌘S)")
        // Kept burst frames share one edit, and the title says so.
        let g = Harness(); g.startCulling()
        let b = g.model.shoot.bursts.first!
        for id in b.ids.prefix(2) { g.model.decisions.mark(id, keep: true) }
        g.go(3, settle: 1.2)
        XCTAssertEqual(g.model.editTitle, "\(b.ids[0]) · burst ×2")
        g.key("."); XCTAssertEqual(g.model.toast?.text, "Exposure +0.05 EV · burst ×2")
        g.key("right"); XCTAssertEqual(g.state.look, ["ev": 0.05]); XCTAssertEqual(g.state.looksCount, 1)
    }

    func test_formatting_neverShowsBrokenNumbers() {
        XCTAssertEqual(EditFormat.value("ev", 0), "0.00 EV"); XCTAssertEqual(EditFormat.value("ev", 0.15), "+0.15 EV"); XCTAssertEqual(EditFormat.value("ev", -1.5), "−1.50 EV")
        XCTAssertEqual(EditFormat.value("wb", 5200), "5200 K"); XCTAssertEqual(EditFormat.value("con", 12), "+12"); XCTAssertEqual(EditFormat.value("con", -8), "−8")
        XCTAssertEqual(EditFormat.value("con", 0), "0"); XCTAssertEqual(EditFormat.value("shp", 40), "40"); XCTAssertEqual(EditFormat.value("ev", -0.001), "0.00 EV")
        XCTAssertEqual(EditFormat.hint("ev"), "Exposure — drag · ⇧ fine · double-click resets · click the number to type · hold V for variations")
        XCTAssertEqual(EditFormat.label("lum_aqua"), "Aqua luminance")
        for s in EditSetting.all { for v in [s.min, s.def, s.max, .nan, .infinity] {
            let t = EditFormat.value(s.key, v) + " " + EditFormat.editable(s.key, v.isFinite ? v : s.def)
            for bad in ["nan", "NaN", "inf", "nil", "Optional("] { XCTAssertFalse(t.contains(bad), "\(s.key): \(t)") }
            XCTAssertFalse(EditFormat.hint(s.key).contains("Optional(")); XCTAssertFalse(EditFormat.label(s.key).isEmpty)
        } }
    }

    func test_failedPhoto_isNotEdited() {
        let h = inEdit(), m = h.model
        m.edit.photo = .failed
        for k in [".", "a", "=", "cmd+v", "shift+0"] { h.key(k) }
        XCTAssertEqual(h.state.look, [:]); XCTAssertEqual(toast(h), "This photo didn’t load. Retry first.")
    }
}
