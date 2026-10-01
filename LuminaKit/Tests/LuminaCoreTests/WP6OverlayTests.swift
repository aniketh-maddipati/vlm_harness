import XCTest
@testable import LuminaCore

/// WP-6, headless: Variations, Help, the intro, the scene grid, the toast and Esc unwinding
/// (R-06, R-20, R-21, R-23…R-26), on a virtual clock through the same keys the app receives.
@MainActor
final class WP6OverlayTests: XCTestCase {
    /// Six keepers, in Edit on the first one.
    private func inEdit(keep n: Int = 6) -> Harness {
        let h = Harness(); h.startCulling(); h.keepN(n); h.wait(0.3); h.go(3, settle: 1.3)
        XCTAssertEqual(h.state.step, "edit"); XCTAssertNotNil(h.state.cur)
        h.model.overlays.intro = .memory()               // never the test process’s UserDefaults
        return h
    }
    private func look(_ h: Harness, _ id: String) -> Look { h.model.edits.look(id, decisions: h.model.decisions) }

    // MARK: R-06

    func test_R06_holdV_switchPhoto_release_newPhotoUntouched() {
        let h = inEdit(), c0 = h.state.cur!
        h.hold("v"); h.wait(0.35)
        XCTAssertEqual(h.state.overlay, "variations")
        h.key("right")                                   // highlight +¼ EV
        XCTAssertEqual(h.state.cur, c0, "the arrow belongs to the grid")
        h.model.editMove(1)                              // a click on the filmstrip, a swipe
        let c1 = h.state.cur!
        XCTAssertNotEqual(c1, c0); XCTAssertNil(h.state.overlay, "the grid closes when the photo changes")
        h.release("v"); h.wait(0.7)
        XCTAssertEqual(look(h, c1), [:], "R-06 variation landed on the next photo")
        XCTAssertEqual(look(h, c0), [:], "nothing was chosen for the first photo either")
        XCTAssertNil(h.state.overlay)
    }

    func test_R06_photoSwitchInsideThe120msWindow_cancelsTheApply() {
        let h = inEdit(), c0 = h.state.cur!
        h.hold("v"); h.wait(0.35); h.key("right"); h.release("v")
        XCTAssertEqual(look(h, c0), [:], "applied before the 120 ms window ended")
        XCTAssertEqual(h.state.overlay, "variations")
        h.wait(0.06)
        h.model.showEditPhoto(h.model.keptIDs[1])        // inside the window
        let c1 = h.state.cur!
        h.wait(0.5)
        XCTAssertEqual(look(h, c1), [:], "R-06"); XCTAssertEqual(look(h, c0), [:], "the apply was not cancelled")
    }

    func test_R06_photoSwitchedBehindTheGrid_neverApplies() {
        // Even if the photo changes without `showEditPhoto` (another work package's path), the apply checks.
        let h = inEdit(), c0 = h.state.cur!
        h.hold("v"); h.wait(0.35); h.key("right"); h.release("v"); h.wait(0.05)
        h.model.editCur = h.model.keptIDs[2]
        h.wait(0.5)
        XCTAssertEqual(look(h, h.model.keptIDs[2]), [:]); XCTAssertEqual(look(h, c0), [:]); XCTAssertNil(h.state.overlay)
    }

    func test_R06_asTheUITestDrivesIt() {
        let h = inEdit(), c0 = h.state.cur!
        h.hold("v"); h.wait(0.35); h.key("right"); h.release("v"); h.wait(0.3)
        XCTAssertEqual(look(h, c0)["ev"] ?? .nan, 0.25, accuracy: 1e-9, "release after a hold applies the highlighted cell")
        h.key("right"); let c1 = h.state.cur!, l1 = h.state.look
        h.wait(0.7)
        XCTAssertNotEqual(c1, c0, "photo didn’t switch"); XCTAssertEqual(h.state.look, l1); XCTAssertEqual(l1, [:])
    }

    // MARK: tap, hold, arrows

    func test_tapOpensWithoutApplying_thenArrowsAndReturnApply() {
        let h = inEdit(), c0 = h.state.cur!
        h.hold("v"); h.wait(0.1); h.release("v"); h.wait(0.5)
        XCTAssertEqual(h.state.overlay, "variations", "a tap leaves the grid open")
        XCTAssertTrue(h.model.edit.variationSticky); XCTAssertEqual(h.state.look, [:], "a tap applied something")
        XCTAssertEqual(h.model.edit.variationKey, "ev"); XCTAssertEqual(h.model.edit.variationIndex, 1)
        h.key("left"); XCTAssertEqual(h.model.edit.variationIndex, 0)
        h.key("left"); XCTAssertEqual(h.model.edit.variationIndex, 0, "clamped")
        h.key("up"); h.key("down"); XCTAssertEqual(h.model.edit.variationIndex, 0, "three cells have no rows")
        h.model.handle(KeyEvent("return")); h.model.handle(KeyEvent("return", phase: .up))
        XCTAssertEqual(h.state.look, [:], "applied inside the 120 ms window")
        h.wait(0.2)
        XCTAssertNil(h.state.overlay); XCTAssertEqual(h.state.look["ev"] ?? .nan, -0.25, accuracy: 1e-9)
        XCTAssertEqual(h.model.toast?.text, "Exposure −¼ EV · ⌘Z undoes")
        h.key("cmd+z"); XCTAssertEqual(look(h, c0), [:], "one undo step")
        h.key("cmd+shift+z"); XCTAssertEqual(look(h, c0)["ev"] ?? .nan, -0.25, accuracy: 1e-9)
    }

    func test_tapThreshold_isThePrototypes280ms() {
        XCTAssertEqual(Variations.tapThreshold, 0.28); XCTAssertEqual(Variations.applyWindow, 0.12)
        for (held, sticky) in [(0.27, true), (0.29, false)] {
            let h = inEdit()
            h.hold("v"); h.wait(held); h.release("v")
            XCTAssertEqual(h.model.edit.variationSticky, sticky, "\(held) s")
            h.wait(0.3)
            XCTAssertEqual(h.state.overlay, sticky ? "variations" : nil, "\(held) s")
            XCTAssertEqual(h.state.look, [:], "the highlighted cell is “now”: nothing changes either way")
        }
    }

    func test_holdAndReleaseWithoutChoosing_keepsThePhotoAsItWas() {
        let h = inEdit()
        h.hold("v"); h.wait(0.5); h.release("v"); h.wait(0.2)
        XCTAssertNil(h.state.overlay); XCTAssertEqual(h.state.look, [:])
        XCTAssertEqual(h.model.toast?.text, "Kept as it was.")
        XCTAssertFalse(h.model.edits.canUndo, "no empty undo step")
    }

    func test_freshVCloses_heldRepeatsDoNot() {
        let h = inEdit()
        h.hold("v"); h.wait(0.1)
        for _ in 0..<5 { h.model.handle(KeyEvent("v", isRepeat: true)); h.wait(0.05) }
        XCTAssertEqual(h.state.overlay, "variations", "the held key’s repeats closed the grid")
        h.release("v"); h.wait(0.3)
        XCTAssertEqual(h.state.overlay, nil, "held 350 ms: applied (now)")
        h.key("v"); XCTAssertEqual(h.state.overlay, "variations"); h.key("right")
        h.key("v"); h.wait(0.3)
        XCTAssertNil(h.state.overlay, "a fresh V closes"); XCTAssertEqual(h.state.look, [:], "closing changed the photo")
        XCTAssertEqual(h.model.toast?.text, "Closed. Nothing changed.")
        XCTAssertNil(h.model.edit.variationKey); XCTAssertNil(h.model.edit.variationPhoto)
    }

    func test_clickAppliesTheCell_hoverSelects() {
        let h = inEdit()
        h.key("v")
        h.model.variationsSelect(2); XCTAssertEqual(h.model.edit.variationIndex, 2)
        h.model.variationsSelect(9); XCTAssertEqual(h.model.edit.variationIndex, 2, "out of range")
        h.model.variationsPick(0); h.wait(0.2)
        XCTAssertNil(h.state.overlay); XCTAssertEqual(h.state.look["ev"] ?? .nan, -0.25, accuracy: 1e-9)
    }

    func test_chosenCellIsFrozenDuringItsWindow() {
        let h = inEdit()
        h.key("v"); h.key("right")
        h.model.handle(KeyEvent("return")); h.wait(0.03)
        h.model.handle(KeyEvent("left")); h.model.handle(KeyEvent("left")); h.model.handle(KeyEvent("return"))
        h.wait(0.3)
        XCTAssertEqual(h.state.look["ev"] ?? .nan, 0.25, accuracy: 1e-9); XCTAssertEqual(h.model.edits.canUndo, true)
        h.key("cmd+z"); XCTAssertEqual(h.state.look, [:], "a second ⏎ applied twice")
    }

    func test_targetIsTheSettingUnderThePointer_orTheSectionsMain() {
        let h = inEdit()
        for (section, key) in [(EditSection.light, "ev"), (.curve, "cMid"), (.colour, "sat_red"), (.effects, "vig")] {
            h.model.edit.section = section; h.model.edit.hoverKey = nil
            h.key("v"); XCTAssertEqual(h.model.edit.variationKey, key); XCTAssertEqual(h.model.overlays.spec?.key, key)
            h.key("escape"); XCTAssertNil(h.model.edit.variationKey)
        }
        h.model.edit.section = .light; h.model.edit.hoverKey = "con"
        h.key("v"); XCTAssertEqual(h.model.edit.variationKey, "con"); h.key("escape")
        h.model.edit.hoverKey = "wb"
        h.key("v"); XCTAssertEqual(h.model.overlays.spec?.kind, .three); XCTAssertEqual(h.model.overlays.spec?.cells.map(\.label), ["cooler", "now", "warmer"]); h.key("escape")
        h.model.edit.hoverKey = "tint"
        h.key("v"); XCTAssertEqual(h.model.overlays.spec?.kind, .grid); XCTAssertEqual(h.model.edit.variationKey, "wb"); h.key("escape")
        h.model.edit.hoverKey = nil; h.model.edit.pickingWhite = true
        h.key("v"); XCTAssertEqual(h.model.overlays.spec?.kind, .grid); XCTAssertFalse(h.model.edit.pickingWhite, "the grid replaces the picker"); h.key("escape")
        h.model.edit.hoverKey = "not-a-setting"
        h.key("v"); XCTAssertEqual(h.model.edit.variationKey, "ev", "falls back to the section’s main setting")
    }

    func test_whiteBalanceGrid_arrowsMoveInTwoAxes_applyIsOneUndoStep() {
        let h = inEdit(), c0 = h.state.cur!
        h.model.edit.hoverKey = "tint"
        h.key("v")
        XCTAssertEqual(h.model.edit.variationIndex, 4, "opens on the middle: now")
        h.key("up"); XCTAssertEqual(h.model.edit.variationIndex, 1)
        h.key("up"); XCTAssertEqual(h.model.edit.variationIndex, 1)
        h.key("right"); XCTAssertEqual(h.model.edit.variationIndex, 2)
        h.key("right"); XCTAssertEqual(h.model.edit.variationIndex, 2)
        h.key("down"); h.key("down"); h.key("down"); XCTAssertEqual(h.model.edit.variationIndex, 8)
        h.key("left"); h.key("left"); h.key("left"); XCTAssertEqual(h.model.edit.variationIndex, 6)
        h.key("up"); h.key("up"); h.key("right"); h.key("right")          // top right: warmer, tint +20
        h.key("return"); h.wait(0.2)
        XCTAssertEqual(look(h, c0), ["wb": 5820, "tint": 20])
        XCTAssertEqual(h.model.toast?.text, "Temperature 5820 K · tint +20")
        h.key("cmd+z"); XCTAssertEqual(look(h, c0), [:], "temperature and tint are one undo step")
        // Only tint differs (the middle column): still one step, and an earlier edit is not folded into it.
        h.model.edit.hoverKey = nil; h.key("."); let ev = look(h, c0)
        XCTAssertEqual(ev.count, 1)
        h.model.edit.hoverKey = "tint"
        h.key("v"); h.key("up"); h.key("return"); h.wait(0.2)
        XCTAssertEqual(look(h, c0)["tint"], 20); XCTAssertNil(look(h, c0)["wb"])
        h.key("cmd+z"); XCTAssertEqual(look(h, c0), ev, "undo took the earlier nudge with it")
    }

    func test_vignette_twoCells() {
        let h = inEdit(), c0 = h.state.cur!
        h.model.edit.section = .effects
        h.key("v")
        XCTAssertEqual(h.model.overlays.spec?.cells.map(\.label), ["none", "−30"]); XCTAssertEqual(h.model.edit.variationIndex, 0)
        h.key("right"); h.key("right"); XCTAssertEqual(h.model.edit.variationIndex, 1)
        h.key("return"); h.wait(0.2)
        XCTAssertEqual(look(h, c0), ["vig": -30]); XCTAssertEqual(h.model.toast?.text, "Vignette −30 · ⌘Z undoes")
        h.key("v")
        XCTAssertEqual(h.model.overlays.spec?.cells.map(\.label), ["−30", "none"], "with a vignette on, the other cell removes it")
        h.key("right"); h.key("return"); h.wait(0.2)
        XCTAssertEqual(look(h, c0), [:])
    }

    // MARK: cells per setting

    func test_cellValuesPerSetting() {
        func cells(_ k: String, _ look: Look = [:]) -> [(String, Double)] { Variations.spec(key: k, look: look)!.cells.map { ($0.label, $0.values[k]!) } }
        func check(_ k: String, _ want: [(String, Double)], _ look: Look = [:], line: UInt = #line) {
            let got = cells(k, look)
            XCTAssertEqual(got.map(\.0), want.map(\.0), k, line: line)
            for (g, w) in zip(got, want) { XCTAssertEqual(g.1, w.1, accuracy: 1e-9, k, line: line) }
        }
        check("ev", [("−¼ EV", -0.25), ("now", 0), ("+¼ EV", 0.25)])
        check("ev", [("−¼ EV", 0.45), ("now", 0.7), ("+¼ EV", 0.95)], ["ev": 0.7])
        check("ev", [("−¼ EV", 4.65), ("now", 4.9), ("+¼ EV", 5)], ["ev": 4.9])
        check("wb", [("cooler", 4890), ("now", 5200), ("warmer", 5510)])
        check("wb", [("cooler", 2500), ("now", 2600), ("warmer", 2760)], ["wb": 2600])
        check("tint", [("−10", -10), ("now", 0), ("+10", 10)])
        check("hl", [("−13", -13), ("now", 0), ("+13", 13)])
        check("sh", [("−13", -13), ("now", 0), ("+13", 13)])
        check("con", [("−10", -10), ("now", 0), ("+10", 10)])
        check("sat", [("−10", 30), ("now", 40), ("+10", 50)], ["sat": 40])
        for k in ["cDark", "cMid", "cLight"] { check(k, [("−8", -8), ("now", 0), ("+8", 8)]) }
        check("cMid", [("−8", 41), ("now", 48), ("+8", 50)], ["cMid": 48])
        for k in ["hue_red", "sat_orange", "lum_magenta"] { check(k, [("−10", -10), ("now", 0), ("+10", 10)]) }
        check("vMid", [("−8", 43), ("now", 50), ("+8", 58)])
        check("vRound", [("−13", -13), ("now", 0), ("+13", 13)])
        check("vFeather", [("−8", 43), ("now", 50), ("+8", 58)])
        check("vHl", [("−13", 0), ("now", 0), ("+13", 13)])
        check("shp", [("−15", 25), ("now", 40), ("+15", 55)])
        check("nr", [("−10", 0), ("now", 0), ("+10", 10)])
        check("vig", [("none", 0), ("−30", -30)])
        check("vig", [("+12", 12), ("none", 0)], ["vig": 12])
        XCTAssertNil(Variations.spec(key: "cropX", look: [:]), "crop is not a slider")

        // Every slider has a grid, opens on the cell that changes nothing, and stays in range.
        for s in EditSetting.all {
            let spec = Variations.spec(key: s.key, look: [:])!
            XCTAssertEqual(spec.cells.count, s.key == "vig" ? 2 : 3, s.key); XCTAssertEqual(spec.columns, spec.cells.count, s.key)
            XCTAssertTrue(spec.cells[spec.initial].isNow, s.key); XCTAssertEqual(spec.cells.filter(\.isNow).count, 1, s.key)
            XCTAssertEqual(spec.cells[spec.initial].values[s.key], s.def, s.key)
            for c in spec.cells { XCTAssertTrue((s.min...s.max).contains(c.values[s.key]!), "\(s.key) \(c.label)"); XCTAssertEqual(c.values.count, 1) }
            XCTAssertTrue(spec.title.hasPrefix("Variations · "), s.key)
        }
        XCTAssertEqual(Variations.spec(key: "sat_red", look: [:])!.title, "Variations · Red saturation")
        XCTAssertEqual(Variations.spec(key: "ev", look: [:])!.title, "Variations · Exposure")
    }

    func test_whiteBalanceGridCells() {
        let g = Variations.spec(key: "tint", whiteBalance: true, look: [:])!
        XCTAssertEqual(g.kind, .grid); XCTAssertEqual(g.key, "wb"); XCTAssertEqual(g.columns, 3); XCTAssertEqual(g.rows, 3); XCTAssertEqual(g.initial, 4)
        XCTAssertEqual(g.title, "White balance"); XCTAssertEqual(g.step, "±12% · ±20")
        XCTAssertEqual(g.cells.map(\.label), ["4640K +20", "5200K +20", "5820K +20", "4640K 0", "5200K 0", "5820K 0", "4640K −20", "5200K −20", "5820K −20"])
        XCTAssertEqual(g.cells.map { $0.values["wb"]! }, [4640, 5200, 5820, 4640, 5200, 5820, 4640, 5200, 5820])
        XCTAssertEqual(g.cells.map { $0.values["tint"]! }, [20, 20, 20, 0, 0, 0, -20, -20, -20])
        XCTAssertEqual(g.cells.map(\.isNow), [false, false, false, false, true, false, false, false, false])
        let edge = Variations.spec(key: "wb", whiteBalance: true, look: ["wb": 9800, "tint": 145])!
        XCTAssertEqual(edge.cells[2].values, ["wb": 10000, "tint": 150], "clamped to the sliders’ ranges")
        XCTAssertEqual(g.moved(from: 4, dx: 1, dy: -1), 2); XCTAssertEqual(g.moved(from: 0, dx: -1, dy: -1), 0); XCTAssertEqual(g.moved(from: 8, dx: 1, dy: 1), 8)
    }

    // MARK: R-20, R-21

    func test_R20_rExplainsInTheToast_andTheToastGoesAfterAWhile() {
        let h = inEdit(), s0 = h.state
        h.key("r")
        XCTAssertEqual(h.model.toast?.text, KeyRouter.rExplanation)
        XCTAssertEqual(h.state.look, s0.look); XCTAssertEqual(h.state.cur, s0.cur); XCTAssertEqual(h.state.keep, s0.keep)
        h.model.toastScheduleExpiry()                    // what the overlay view does when a toast goes up
        h.wait(3.0); XCTAssertNotNil(h.model.toast, "gone too soon (the UI test reads it after 0.4 s)")
        h.wait(0.6); XCTAssertNil(h.model.toast, "a toast stays 3.5 s")
        // A newer toast is not taken down by the older one’s timer.
        h.key("r"); h.model.toastScheduleExpiry(); h.wait(3.0)
        h.model.say("later"); h.model.toastScheduleExpiry(); h.wait(1.0)
        XCTAssertEqual(h.model.toast?.text, "later")
        h.wait(3.0); XCTAssertNil(h.model.toast)
        // Cull’s message line is not Edit’s toast: the timer leaves it alone.
        h.model.say("x"); h.model.toastScheduleExpiry(); h.go(2); h.model.say("cull message"); h.wait(5)
        XCTAssertEqual(h.model.toast?.text, "cull message")
    }

    func test_R21_tDoesNothingAnywhere() {
        let h = inEdit()
        func snapshot() -> String { h.model.debugStateJSON + "|\(h.model.edit)|\(h.model.toast?.text ?? "-")" }
        let opens: [(String, () -> Void, () -> Void)] = [
            ("edit", {}, {}),
            ("help", { h.key("shift+/") }, { h.key("escape") }),
            ("variations", { h.key("v"); h.model.toast = nil }, { h.key("escape"); h.model.toast = nil }),
            ("crop", { h.key("c") }, { h.key("escape"); h.model.toast = nil }),
            ("intro", { h.model.edit.overlay = .intro }, { h.key("escape") }),
            ("sceneGrid", { h.model.sceneGridOpen() }, { h.key("escape") }),
            ("focus", { h.key("h") }, { h.key("escape") }),
        ]
        for (name, open, close) in opens {
            open()
            let before = snapshot()
            for m in [KeyModifiers(), .shift] {
                let r = h.model.handle(KeyEvent("t", m)); h.model.handle(KeyEvent("t", m, phase: .up)); h.wait(0.3)
                if name != "crop" { XCTAssertEqual(r.action, .none, "R-21 T in \(name)") }
            }
            if name == "crop" { h.model.toast = nil }    // Crop says why it swallowed the key; nothing else may change
            XCTAssertEqual(snapshot(), before, "R-21 T changed something in \(name)")
            close()
        }
        for step in 1...4 {
            h.go(step); let before = h.model.debugStateJSON
            h.key("t"); h.wait(0.3)
            XCTAssertEqual(h.model.debugStateJSON, before, "R-21 T did something on step \(step)")
        }
    }

    // MARK: R-23

    func test_R23_helpBlocksThePhoto_escClosesOnlyHelp() {
        let h = inEdit()
        h.key("."); h.key("z"); h.key("h")               // an edit, zoomed, focus mode
        let zoom = h.state.zoom; XCTAssertGreaterThan(zoom, 1)
        h.key("shift+/"); XCTAssertEqual(h.state.overlay, "help")
        let s0 = h.state, edit0 = h.model.edit
        for k in ["x", "r", ".", ",", "shift+.", "left", "right", "up", "down", "return", "a", "0", "shift+0", "=", "w", "c", "s", "z", "h", "v", "[", "]", "\\", "t",
                  "cmd+z", "cmd+shift+z", "cmd+c", "cmd+v", "cmd+=", "cmd+-", "cmd+0"] {
            h.key(k)
            XCTAssertEqual(h.state.overlay, "help", "\(k) closed Help")
        }
        h.wait(0.5)
        XCTAssertEqual(h.state.cur, s0.cur); XCTAssertEqual(h.state.keep, s0.keep); XCTAssertEqual(h.state.look, s0.look)
        XCTAssertEqual(h.state.zoom, s0.zoom); XCTAssertEqual(h.model.edit, edit0, "something moved under Help")
        XCTAssertNil(h.model.toast.flatMap { $0.text == KeyRouter.rExplanation ? $0 : nil }, "R reached Edit under Help")
        h.key("escape")
        XCTAssertNil(h.model.edit.overlay, "Esc closes Help"); XCTAssertTrue(h.model.edit.focus, "Esc closed more than Help")
        XCTAssertEqual(h.state.zoom, zoom); XCTAssertEqual(h.state.cur, s0.cur)
        h.key("shift+/"); XCTAssertEqual(h.state.overlay, "help"); h.key("shift+/"); XCTAssertNil(h.model.edit.overlay, "? closes Help too")
        // The step keys still work from under Help.
        h.key("shift+/"); h.go(2); XCTAssertEqual(h.state.step, "cull"); h.go(3, settle: 1.3); XCTAssertNil(h.state.overlay)
    }

    func test_helpOpensOnlyOverThePlainEditScreen() {
        let h = inEdit()
        h.key("v"); h.key("shift+/"); XCTAssertEqual(h.state.overlay, "variations"); h.key("escape")
        h.key("c"); h.key("shift+/"); XCTAssertEqual(h.state.overlay, "crop"); h.key("escape")
        h.go(2); h.key("shift+/"); XCTAssertNil(h.model.edit.overlay, "Help is Edit’s")
    }

    // MARK: R-24

    func test_R24_variationsOwnTheKeyboard() {
        let h = inEdit(), s0 = h.state
        h.hold("v"); h.wait(0.35); XCTAssertEqual(h.state.overlay, "variations")
        for k in ["x", "r", "a", "0", "shift+0", ".", ",", "=", "w", "c", "s", "z", "h", "t", "\\", "[", "]", "shift+/", "cmd+z", "cmd+v", "cmd+c", "cmd+0"] {
            h.key(k, settle: 0.04)
            XCTAssertEqual(h.state.overlay, "variations", "\(k) closed the grid")
        }
        XCTAssertEqual(h.state.keep, s0.keep); XCTAssertEqual(h.state.look, s0.look); XCTAssertEqual(h.state.cur, s0.cur); XCTAssertEqual(h.state.zoom, s0.zoom)
        XCTAssertFalse(h.model.edit.focus); XCTAssertFalse(h.model.edit.before)
        h.key("escape"); h.release("v"); h.wait(0.5)
        XCTAssertEqual(h.state.keep, s0.keep); XCTAssertEqual(h.state.look, s0.look); XCTAssertNil(h.state.overlay)
    }

    func test_R24_blurClosesTheGrid_andNothingApplies() {
        let h = inEdit()
        h.hold("v"); h.wait(0.25); XCTAssertEqual(h.state.overlay, "variations")
        h.key("right")
        h.model.windowBlurred(); h.wait(0.25)
        XCTAssertNil(h.state.overlay, "R-24 the grid stayed open after the window lost focus")
        XCTAssertTrue(h.model.heldKeys.isEmpty); XCTAssertNil(h.model.edit.variationKey)
        h.release("v"); h.wait(0.5)
        XCTAssertEqual(h.state.look, [:], "the release after a blur applied the cell"); XCTAssertNil(h.state.overlay)
        // Blur inside the apply window cancels it too.
        h.hold("v"); h.wait(0.4); h.key("right"); h.release("v"); h.wait(0.05)
        h.model.windowBlurred(); h.wait(0.5)
        XCTAssertEqual(h.state.look, [:]); XCTAssertNil(h.state.overlay)
        // And a sticky grid closes as well.
        h.key("v"); XCTAssertEqual(h.state.overlay, "variations"); h.model.windowBlurred(); XCTAssertNil(h.state.overlay)
    }

    func test_gridClosesWhenLeavingEdit_andALateReleaseDoesNothing() {
        let h = inEdit()
        h.hold("v"); h.wait(0.4); h.key("right")
        h.go(2); XCTAssertNil(h.model.edit.overlay)
        h.release("v"); h.wait(0.5); h.go(3, settle: 1.3)
        XCTAssertNil(h.state.overlay); XCTAssertEqual(h.state.look, [:])
        h.hold("v"); h.wait(0.4); h.key("right"); h.release("v"); h.go(4); h.wait(0.5); h.go(3, settle: 1.3)
        XCTAssertEqual(h.state.look, [:], "an apply still pending when Edit was left landed later")
    }

    func test_variationsNeedAPhoto() {
        let h = Harness(); h.startCulling(); h.go(3, settle: 1.3)
        h.hold("v"); h.wait(0.4); XCTAssertNil(h.state.overlay, "no keepers: no grid"); h.release("v")
        let k = inEdit()
        k.model.edit.photo = .failed
        k.key("v"); XCTAssertNil(k.state.overlay); XCTAssertEqual(k.model.toast?.text, "This photo didn’t load. Retry first.")
    }

    // MARK: R-25

    func test_R25_everyModeIsBackToNormalInAtMostThreeEsc() {
        func normal(_ h: Harness) -> Bool {
            let e = h.model.edit
            return e.overlay == nil && abs(e.zoom - 1) < 0.01 && !e.focus && !e.controlsHidden && !e.before && !e.pickingWhite && !e.straightening
        }
        func unwind(_ h: Harness, _ name: String, line: UInt = #line) {
            var n = 0
            while !normal(h) && n < 6 { h.key("escape", settle: 0.25); n += 1 }
            XCTAssertTrue(normal(h), "stuck in \(name)", line: line)
            XCTAssertLessThanOrEqual(n, 3, "R-25 \(name) needed \(n) esc", line: line)
            XCTAssertEqual(h.model.escapeDepth, 0, line: line)
        }
        let h = inEdit(), c0 = h.state.cur
        let modes: [(String, () -> Void)] = [
            ("help", { h.key("shift+/") }), ("crop", { h.key("c") }), ("zoom", { h.key("z") }), ("focus", { h.key("h") }),
            ("before", { h.key("\\") }), ("variations held", { h.hold("v"); h.wait(0.4) }), ("variations tapped", { h.key("v") }),
            ("intro", { h.model.edit.overlay = .intro }), ("scene grid", { h.model.sceneGridOpen() }),
            ("picker", { h.model.edit.pickingWhite = true }), ("picker overlay", { h.model.edit.overlay = .picker }),
            ("large", { h.model.edit.controlsHidden = true }), ("straighten", { h.model.edit.straightening = true }),
            ("zoom + focus", { h.key("z"); h.key("h") }), ("zoom + focus + before", { h.key("z"); h.key("h"); h.key("\\") }),
            ("zoom + focus + help", { h.key("z"); h.key("h"); h.key("shift+/") }),
            ("zoom + focus + variations", { h.key("z"); h.key("h"); h.key("v") }),
            ("zoom + focus + crop", { h.key("z"); h.key("h"); h.key("c") }),
        ]
        for (name, open) in modes {
            open(); XCTAssertFalse(normal(h), "\(name) didn’t open")
            unwind(h, name); h.release("v")
            XCTAssertEqual(h.state.cur, c0, "\(name): Esc moved the photo"); XCTAssertEqual(h.state.look, [:], "\(name): Esc edited the photo")
        }
        // Every combination of the layers Esc itself unwinds, however they came to be up together.
        for bits in 1..<64 {
            h.model.edit.focus = bits & 1 != 0; h.model.edit.zoom = bits & 2 != 0 ? 2 : 1; h.model.edit.before = bits & 4 != 0
            h.model.edit.overlay = bits & 8 != 0 ? .sceneGrid : nil; h.model.edit.pickingWhite = bits & 16 != 0; h.model.edit.straightening = bits & 32 != 0
            XCTAssertEqual(h.model.escapeDepth, min(3, bits.nonzeroBitCount))
            unwind(h, "combination \(bits)")
        }
    }

    func test_R25_oneLayerAtATime_inKeymapOrder() {
        let h = inEdit()
        h.key("z"); h.key("h")
        XCTAssertGreaterThan(h.state.zoom, 1); XCTAssertEqual(h.state.overlay, "focus")
        h.key("escape"); XCTAssertGreaterThan(h.state.zoom, 1, "first esc should only leave focus"); XCTAssertNil(h.state.overlay)
        h.key("escape"); XCTAssertEqual(h.state.zoom, 1, accuracy: 0.01)
        // zoom → before → scene grid, one each.
        h.key("z"); h.model.sceneGridOpen(); h.model.edit.before = true
        h.key("escape"); XCTAssertEqual(h.state.zoom, 1, accuracy: 0.01); XCTAssertTrue(h.model.edit.before); XCTAssertEqual(h.state.overlay, "sceneGrid")
        h.key("escape"); XCTAssertFalse(h.model.edit.before); XCTAssertEqual(h.state.overlay, "sceneGrid")
        h.key("escape"); XCTAssertNil(h.state.overlay)
        // scene grid before picker.
        h.model.edit.overlay = .sceneGrid; h.model.edit.pickingWhite = true
        h.key("escape"); XCTAssertNil(h.state.overlay); XCTAssertTrue(h.model.edit.pickingWhite)
        h.key("escape"); XCTAssertFalse(h.model.edit.pickingWhite); XCTAssertEqual(h.model.toast?.text, "Picker off")
        // Esc with nothing open does nothing.
        let before = h.model.debugStateJSON; h.key("escape"); XCTAssertEqual(h.model.debugStateJSON, before)
    }

    // MARK: R-26

    func test_R26_helpMatchesTheKeymap() {
        let groups = HelpContent.groups
        XCTAssertEqual(groups.map(\.title), ["Essentials", "Move", "Edit", "Look", "Trackpad"], "five groups")
        // What the UI test reads: each key and each description is its own text, one after the other.
        let text = groups.flatMap { [$0.title] + $0.rows.flatMap { [$0.keys, $0.text] } }.joined(separator: "\n")
        XCTAssertNil(text.range(of: #"(^|\n)T\s*\n"#, options: .regularExpression), "help still lists T")
        XCTAssertFalse(text.contains("T tries"))
        XCTAssertNil(text.range(of: #"(^|\n)R( · ⇧R)?\s*\n\s*turn 90"#, options: .regularExpression), "help lists R as rotate")
        let keys = groups.flatMap { $0.rows.map(\.keys) }
        XCTAssertFalse(keys.contains { $0.split(whereSeparator: { " ·,".contains($0) }).contains("T") }, "T is a key in Help")
        XCTAssertFalse(keys.contains { $0 == "R" || $0.hasPrefix("R ") }, "R is listed as a key outside Crop")
        XCTAssertTrue(groups.flatMap(\.rows).contains { $0.keys == "C, then R" && $0.text.contains("in Crop") }, "the turn is only reachable through Crop")
        // Every key of KEYMAP.md's Edit table is there.
        let all = keys.joined(separator: "  ")
        for k in ["⏎", "← →", "↑ ↓", "⌘Z · ⇧⌘Z", "\\ hold", "V hold", "C", "S", "A", ", .", "[ ]", "0 · ⇧0", "=", "W", "X", "⌘C · ⌘V", "Z · click", "⌘+ ⌘− ⌘0", "H", "esc", "?", "⌥ drag ↕"] {
            XCTAssertTrue(keys.contains(k), "Help is missing \(k) (\(all))")
        }
        // …and every key Help lists does what it says: it is bound in Edit (single keys only).
        for k in ["return", "left", "right", "up", "down", "\\", "v", "c", "s", "a", ",", ".", "[", "]", "0", "=", "w", "x", "z", "h", "escape"] {
            let r = KeyRouter.route(KeyEvent(k), layers: [.step(.edit)])
            XCTAssertEqual(r.handler, .step(.edit), k); XCTAssertNotEqual(r.action, .none, "Help lists \(k) but Edit ignores it")
        }
        for row in groups.flatMap(\.rows) { XCTAssertFalse(row.keys.isEmpty || row.text.isEmpty) }
        for bad in ["undefined", "NaN", "{{", "[object", "Optional(", " nil "] { XCTAssertFalse(text.contains(bad), "R-53") }
    }

    // MARK: intro

    private func freshModel(env: [String: String] = [:], store: URL?) -> (AppModel, TestScheduler) {
        Faults.shared.clearAll()
        let clock = TestScheduler()
        var config = LaunchConfig(arguments: [], environment: ["LUMINA_CARD": "demo117", "LUMINA_COPY_RATE": "66"].merging(env) { _, b in b })
        config.storeDir = store
        let m = AppModel.launch(config: config, services: Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: MemoryPersistence()), clock: clock)
        m.overlays.introForced = env["LUMINA_INTRO"] == "show"       // the test process’s own environment must not matter
        m.handle(KeyEvent("return")); clock.advance(4)
        return (m, clock)
    }
    private func toEdit(_ m: AppModel, _ clock: TestScheduler, keep: Int = 3) {
        m.handle(KeyEvent("2", .command)); clock.advance(0.6)
        for _ in 0..<keep { m.handle(KeyEvent("r")); clock.advance(0.05) }
        m.handle(KeyEvent("3", .command)); clock.advance(1.3)
        m.introOpenIfFirstRun()                                      // the overlay view, when Edit appears
    }

    func test_intro_shownOnce_closedByEscOrReturn_rememberedInTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wp6-intro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let (m, clock) = freshModel(store: dir)
        toEdit(m, clock)
        XCTAssertEqual(m.edit.overlay, .intro, "first visit to Edit shows the intro")
        XCTAssertEqual(m.layers.contains(.intro), true)
        let cur = m.editCur, keep = m.decisions.keep
        for k in ["x", "r", "right", "left", ".", "a", "v", "c", "z", "h", "t", "0"] {
            m.handle(KeyEvent(k)); m.handle(KeyEvent(k, phase: .up)); clock.advance(0.05)
            XCTAssertEqual(m.edit.overlay, .intro, "\(k) got past the intro")
        }
        XCTAssertEqual(m.editCur, cur); XCTAssertEqual(m.decisions.keep, keep); XCTAssertEqual(m.currentLook, [:]); XCTAssertEqual(m.edit.zoom, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(IntroFlag.key).path), "seen before it was closed")
        m.handle(KeyEvent("escape"))
        XCTAssertNil(m.edit.overlay); XCTAssertEqual(m.editCur, cur)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(IntroFlag.key).path), "lumina.edit.intro.v1 not stored")
        // Leaving and coming back in the same window: not again.
        m.handle(KeyEvent("2", .command)); clock.advance(0.6); m.handle(KeyEvent("3", .command)); clock.advance(1.3); m.introOpenIfFirstRun()
        XCTAssertNil(m.edit.overlay)

        // A relaunch on the same store: not again.
        let (m2, clock2) = freshModel(store: dir); toEdit(m2, clock2)
        XCTAssertNil(m2.edit.overlay, "the intro came back after a relaunch")
        // Help can bring it back; ⏎ closes it.
        m2.handle(KeyEvent("/", .shift)); XCTAssertEqual(m2.edit.overlay, .help)
        m2.introShow(); XCTAssertEqual(m2.edit.overlay, .intro)
        m2.handle(KeyEvent("return")); XCTAssertNil(m2.edit.overlay); XCTAssertEqual(m2.step, .edit, "⏎ went on to the next photo or Save")
        XCTAssertEqual(m2.editCur, m2.keptIDs.first, "⏎ on the intro moved the photo")

        // LUMINA_INTRO=show forces it even though it was seen; skip wins over everything.
        let (m3, clock3) = freshModel(env: ["LUMINA_INTRO": "show"], store: dir); toEdit(m3, clock3)
        XCTAssertEqual(m3.edit.overlay, .intro)
        m3.introToHelp(); XCTAssertEqual(m3.edit.overlay, .help, "“All shortcuts” goes from the intro to Help")
        let (m4, clock4) = freshModel(env: ["LUMINA_INTRO": "skip"], store: nil); m4.overlays.intro = .memory(); toEdit(m4, clock4)
        XCTAssertNil(m4.edit.overlay, "LUMINA_INTRO=skip")
    }

    func test_intro_waitsForAPhoto_andIsThreeCards() {
        let (m, clock) = freshModel(store: nil); m.overlays.intro = .memory()
        toEdit(m, clock, keep: 0)
        XCTAssertNil(m.edit.overlay, "no keepers: the empty state, not the intro")
        toEdit(m, clock, keep: 2)
        XCTAssertEqual(m.edit.overlay, .intro)
        XCTAssertFalse(m.overlays.intro.seen); m.introClose(); XCTAssertTrue(m.overlays.intro.seen)
        XCTAssertEqual(IntroContent.cards.map(\.number), ["1", "2", "3"], "README: three numbered cards")
        XCTAssertTrue(IntroContent.subtitle.hasPrefix("Three things"))
        XCTAssertFalse(IntroContent.cards.contains { $0.text.contains("T ") && $0.key == "T" })
    }

    // MARK: scene grid

    func test_sceneGrid_keptPhotosOfTheScene_clickJumps_escCloses() {
        let h = inEdit(keep: 20)                                     // scene 0 has 14 photos, the rest are scene 1
        let scene0 = h.model.keptIDs.filter { h.model.shoot.photo($0)?.scene == 0 }
        h.model.sceneGridOpen()
        XCTAssertEqual(h.state.overlay, "sceneGrid")
        let g = h.model.sceneGrid!
        XCTAssertTrue(g.title.hasPrefix("Scene 09:12 · "), g.title); XCTAssertTrue(g.subtitle.hasSuffix("click a photo to open it"))
        XCTAssertTrue(g.ids.allSatisfy { scene0.contains($0) }); XCTAssertTrue(g.ids.contains(h.state.cur!))
        XCTAssertEqual(Set(g.ids.map { h.model.edits.key(for: $0, decisions: h.model.decisions) }).count, g.ids.count, "kept burst frames share one cell")
        XCTAssertLessThanOrEqual(g.ids.count, 30)
        let target = g.ids.last!
        h.model.sceneGridPick(target)
        XCTAssertEqual(h.state.cur, target); XCTAssertNil(h.state.overlay)
        h.model.sceneGridOpen(); h.model.sceneGridPick("nope"); XCTAssertEqual(h.state.overlay, "sceneGrid", "a photo that isn’t kept")
        h.key("escape"); XCTAssertNil(h.state.overlay); XCTAssertEqual(h.state.cur, target)
        // It does not open over another overlay.
        h.key("shift+/"); h.model.sceneGridOpen(); XCTAssertEqual(h.state.overlay, "help")
    }

    // MARK: KeyRouter sweep

    /// For every layer that owns the keyboard: no unbound single key reaches Edit (or Cull, Open,
    /// Save) underneath; only ⌘1–4, ⌘S and ⌘O pass, to Global (KEYMAP "Layer order").
    func test_keyRouterSweep_owningLayersLetNothingThrough() {
        var keys = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        keys += ["`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "<", ">", ")", "?", "+", "_", "{", "}", "|", ":", "\"", "~", "!", "@", "#", "$", "%", "^", "&", "*", "(", "§", "é", "ü"]
        keys += ["return", "escape", "left", "right", "up", "down", "tab", "delete", "space", "home", "end", "pageup", "pagedown", "\r", "\u{1b}", "A", "R", "X", "V", "T"]
        let mods: [KeyModifiers] = [[], .shift, .option, [.shift, .option], .control, .command, [.command, .shift], [.command, .option]]
        let globals: Set<String> = ["1", "2", "3", "4", "s", "o"]
        for step in Step.allCases {
            for layer in [Layer.textField, .help, .intro, .crop, .variations] {
                for stack in [[.step(step), layer], [layer, .step(step), .control], [.step(step), .rotateHold, layer]] as [[Layer]] {
                    for k in keys { for m in mods { for phase in [KeyEvent.Phase.down, .up] { for rep in [false, true] where !(rep && phase == .up) {
                        let e = KeyEvent(k, m, isRepeat: rep, phase: phase), r = KeyRouter.route(e, layers: stack), at = "\(k) \(m.rawValue) \(phase) repeat:\(rep) under \(layer) on \(step)"
                        if r.handler == .global {
                            XCTAssertTrue(e.modifiers.contains(.command) && globals.contains(e.key) && phase == .down, "\(at): reached Global")
                        } else {
                            XCTAssertEqual(r.handler, layer, "\(at): fell through to \(r.handler) (R-20…R-26)")
                        }
                        if case .step = r.handler { XCTFail("\(at): reached the step") }
                    } } } }
                }
            }
        }
        // What each owning layer does bind, so the sweep above isn’t passing on an empty table.
        XCTAssertEqual(KeyRouter.route(KeyEvent("escape"), layers: [.step(.edit), .help]).action, .helpClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("?"), layers: [.step(.edit), .help]).action, .helpClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("return"), layers: [.step(.edit), .intro]).action, .introClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("escape"), layers: [.step(.edit), .intro]).action, .introClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("return"), layers: [.step(.edit), .variations]).action, .variationApply)
        XCTAssertEqual(KeyRouter.route(KeyEvent("v"), layers: [.step(.edit), .variations]).action, .variationClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("v", isRepeat: true), layers: [.step(.edit), .variations]).action, .none)
        XCTAssertEqual(KeyRouter.route(KeyEvent("v", phase: .up), layers: [.step(.edit), .variations]).action, .variations(down: false))
        XCTAssertEqual(KeyRouter.route(KeyEvent("down"), layers: [.step(.edit), .variations]).action, .variationMove(dx: 0, dy: 1))
        XCTAssertEqual(KeyRouter.route(KeyEvent("x"), layers: [.step(.edit), .variations]).action, .none, "anything else is swallowed")
        XCTAssertEqual(KeyRouter.route(KeyEvent("3", .command), layers: [.step(.edit), .help]).action, .goStep(.edit))
        // Help outranks the intro, the intro outranks Crop and Variations (KEYMAP layer order).
        XCTAssertEqual(KeyRouter.route(KeyEvent("escape"), layers: [.step(.edit), .variations, .crop, .intro, .help]).action, .helpClose)
        XCTAssertEqual(KeyRouter.route(KeyEvent("escape"), layers: [.step(.edit), .variations, .crop, .intro]).action, .introClose)
        // And the model reports the layer for each overlay it can show.
        let h = inEdit()
        for (o, l) in [(Overlay.help, Layer.help), (.intro, .intro), (.crop, .crop), (.variations, .variations)] {
            h.model.edit.overlay = o; XCTAssertTrue(h.model.layers.contains(l), "\(o)")
        }
    }
}
