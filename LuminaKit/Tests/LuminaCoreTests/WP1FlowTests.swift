import XCTest
@testable import LuminaCore

/// WP-1, headless: step switching (R-01, R-02), the global keys, what the window's event
/// monitor takes and leaves (R-22, R-24), drops (R-17) and the top bar's sizes (R-50, R-54).
@MainActor
final class WP1FlowTests: XCTestCase {

    // MARK: R-01

    func test_R01_sixFastEnters_endOnCull_neverSave_copyStartsOnce() {
        let h = Harness()
        h.wait(1)
        for _ in 0..<6 { h.key("return", settle: 0.015) }
        XCTAssertEqual(h.state.step, "cull")
        XCTAssertNil(h.state.saved)
        XCTAssertTrue(h.model.copying)
        // One copy, not six: the count rises at the copy rate.
        let before = h.model.copied
        h.wait(0.5)
        XCTAssertLessThanOrEqual(h.model.copied - before, 34, "more than one copy is running")
        h.wait(3)
        XCTAssertEqual(h.state.copied, 117)
    }

    func test_R01_enterWithin450msOfAStepChange_doesNothing() {
        let h = Harness()
        h.go(2, settle: 0.1); h.go(1, settle: 0.1)
        h.key("return", settle: 0.1)
        XCTAssertEqual(h.state.step, "open", "⏎ 100 ms after arriving on Open must be ignored")
        XCTAssertEqual(h.state.copied, 0)
        h.wait(0.4)
        h.key("return")
        XCTAssertEqual(h.state.step, "cull")
    }

    func test_R01_heldEnter_isIgnored() {
        let h = Harness()
        h.wait(1)
        h.key("return", isRepeat: true)
        XCTAssertEqual(h.state.step, "open")
    }

    // MARK: R-02

    func test_R02_fortyPresses15msApart_lastPressWins() {
        var rng = SystemRandomNumberGenerator()
        for round in 0..<5 {
            let h = Harness()
            if round % 2 == 1 { h.startCulling(); h.keepN(3) }
            var last = 1
            for _ in 0..<40 { last = Int.random(in: 1...4, using: &rng); h.go(last, settle: 0.015) }
            XCTAssertEqual(h.state.step, Step.allCases[last - 1].rawValue, "round \(round)")
            XCTAssertEqual(h.state.errors, 0)
        }
    }

    func test_R02_goIsIdempotent() {
        let h = Harness()
        h.go(2)
        let at = h.model.stepChangedAt, rev = h.model.revision
        h.model.say("still here")
        h.wait(1)
        h.model.go(.cull); h.go(2)
        XCTAssertEqual(h.model.stepChangedAt, at, "going to the step on screen must not restart the ⏎ guards")
        XCTAssertEqual(h.model.revision, rev, "…or write to the store")
        XCTAssertEqual(h.model.toast?.text, "still here")
    }

    func test_R02_heldDigit_doesNotRepeat() {
        let h = Harness()
        h.go(2)
        h.model.handle(KeyEvent("1", .command, isRepeat: true))
        XCTAssertEqual(h.state.step, "cull")
    }

    func test_stepChange_stampsTheGuards_andClearsTheMessage() {
        let h = Harness()
        h.startCulling(); h.keepN(2)
        h.model.say("a message")
        h.wait(2)
        h.go(4, settle: 0)
        XCTAssertEqual(h.model.sinceStepChange, 0, accuracy: 0.001)
        XCTAssertNil(h.model.toast)
        // R-33's first half rides on the same stamp: ⏎ right after arriving does not save.
        h.key("return")
        XCTAssertNil(h.state.saved)
    }

    func test_leavingEdit_andComingBack_keepsEditsPlace() {
        let h = Harness()
        h.startCulling(); h.keepN(4)
        h.go(3); h.key("right")
        let cur = h.state.cur
        h.go(2); h.go(3)
        XCTAssertEqual(h.state.cur, cur)
        XCTAssertNil(h.state.overlay)
    }

    // MARK: global keys

    func test_cmdDigits_reachEveryStep_fromEveryStep() {
        let h = Harness()
        h.startCulling(); h.keepN(2)
        for from in 1...4 { for to in 1...4 {
            h.go(from); h.go(to)
            XCTAssertEqual(h.state.step, Step.allCases[to - 1].rawValue, "⌘\(from) then ⌘\(to)")
        } }
    }

    func test_cmdS_goesToSave_thenSaves_once() {
        let h = Harness()
        h.startCulling(); h.keepN(3)
        h.key("cmd+s")
        XCTAssertEqual(h.state.step, "save"); XCTAssertNil(h.state.saved, "⌘S from Cull must not save")
        h.model.handle(KeyEvent("s", .command, isRepeat: true))
        XCTAssertNil(h.state.saved, "a held ⌘S must not save")
        h.key("cmd+s")
        XCTAssertEqual(h.state.saved?.n, 3)
        h.go(3); h.key("cmd+s")
        XCTAssertEqual(h.state.step, "save")
        XCTAssertEqual(h.state.saved?.again, false, "⌘S from Edit goes to Save without saving (R-35)")
    }

    func test_cmdO_asksForAFolder_onEveryStep() {
        let h = Harness()
        var asked = 0
        h.model.hooks.pickFolder = { asked += 1 }
        h.startCulling(); h.keepN(1)
        for n in 1...4 { h.go(n); h.key("cmd+o") }
        XCTAssertEqual(asked, 4)
        h.model.handle(KeyEvent("o", .command, isRepeat: true))
        XCTAssertEqual(asked, 4)
    }

    func test_globalKeys_workUnderAnOverlay() {
        let h = Harness()
        h.startCulling(); h.keepN(2); h.go(3)
        h.model.edit.overlay = .help
        h.key("cmd+2")
        XCTAssertEqual(h.state.step, "cull")
    }

    // MARK: the window's event monitor

    func test_R22_aFocusedTextField_types() {
        let h = Harness()
        h.startCulling()
        let before = h.model.debugStateJSON
        for k in ["r", "x", "u", "left", "right", "return", "escape", "0", "z", "v"] {
            XCTAssertFalse(h.model.windowKey(KeyEvent(k), typing: true), "\(k) was taken from the text field")
            XCTAssertFalse(h.model.windowKey(KeyEvent(k, phase: .up), typing: true))
        }
        // The field's own chords too.
        for k in ["a", "c", "v", "x", "z"] { XCTAssertFalse(h.model.windowKey(KeyEvent(k, .command), typing: true)) }
        XCTAssertEqual(h.model.debugStateJSON, before)
        XCTAssertTrue(h.model.heldKeys.isEmpty)
    }

    func test_R22_globalChords_leaveTheTextField_first() {
        let h = Harness()
        h.startCulling(); h.keepN(2)
        var order: [String] = []
        let took = h.model.windowKey(KeyEvent("4", .command), typing: true) { order.append("end typing on \(h.model.step.rawValue)") }
        XCTAssertTrue(took)
        XCTAssertEqual(order, ["end typing on cull"], "the field commits before the step changes")
        XCTAssertEqual(h.state.step, "save")
        // A held repeat is swallowed and leaves the field alone.
        var ended = false
        XCTAssertTrue(h.model.windowKey(KeyEvent("1", .command, isRepeat: true), typing: true) { ended = true })
        XCTAssertFalse(ended); XCTAssertEqual(h.state.step, "save")
    }

    func test_unboundChords_goToTheMenus_boundKeysDoNot() {
        let h = Harness()
        h.startCulling(); h.keepN(2)
        for k in ["q", "w", "m", ",", "h"] { XCTAssertFalse(h.model.windowKey(KeyEvent(k, .command)), "⌘\(k) never reached the menus") }
        XCTAssertFalse(h.model.windowKey(KeyEvent("f", [.command, .control])))
        XCTAssertTrue(h.model.windowKey(KeyEvent("r")))
        XCTAssertTrue(h.model.windowKey(KeyEvent("z", .command)))
        XCTAssertTrue(h.model.windowKey(KeyEvent("3", .command)))
        // T is bound to nothing on purpose (R-21): taken, so it can't fall through.
        XCTAssertTrue(h.model.windowKey(KeyEvent("t")))
        // Tab and Space belong to AppKit (keyboard focus).
        XCTAssertFalse(h.model.windowKey(KeyEvent("tab")))
        XCTAssertFalse(h.model.windowKey(KeyEvent("space")))
    }

    func test_unboundChords_goToTheMenus_evenUnderCrop() {
        let h = Harness()
        h.startCulling(); h.keepN(2); h.go(3)
        h.model.edit.overlay = .crop
        h.model.toast = nil
        XCTAssertFalse(h.model.windowKey(KeyEvent("q", .command)))
        XCTAssertNil(h.model.toast, "⌘Q under Crop must not be explained away")
        // A single unbound key is still Crop's to swallow.
        XCTAssertTrue(h.model.windowKey(KeyEvent("j")))
        XCTAssertEqual(h.model.toast?.text, KeyRouter.cropSwallow)
    }

    func test_heldGlobalChord_isTaken_andDoesNothing() {
        let h = Harness()
        h.startCulling(); h.keepN(2); h.go(4, settle: 2)
        XCTAssertTrue(h.model.windowKey(KeyEvent("s", .command, isRepeat: true)), "a held ⌘S fell through to the menu")
        XCTAssertNil(h.state.saved)
    }

    func test_chords_areNeverLeftHeld() {
        let h = Harness()
        h.startCulling(); h.keepN(2); h.go(3)
        // macOS sends no key-up for these.
        h.model.windowKey(KeyEvent("v", .command)); h.model.windowKey(KeyEvent("2", .command)); h.model.windowKey(KeyEvent("3", .command))
        XCTAssertTrue(h.model.heldKeys.isEmpty, "\(h.model.heldKeys)")
        // A real hold is tracked until its key-up.
        h.model.windowKey(KeyEvent("v"))
        XCTAssertEqual(h.model.heldKeys, ["v"])
        h.model.windowKey(KeyEvent("v", phase: .up))
        XCTAssertTrue(h.model.heldKeys.isEmpty)
    }

    func test_R24_blur_forgetsHeldKeys_andClosesVariations() {
        let h = Harness()
        h.startCulling(); h.keepN(2); h.go(3)
        h.model.windowKey(KeyEvent("v"))
        XCTAssertEqual(h.state.overlay, "variations")
        h.model.windowBlurred()
        XCTAssertNil(h.state.overlay)
        XCTAssertTrue(h.model.heldKeys.isEmpty)
        XCTAssertEqual(h.state.step, "edit")
    }

    // MARK: R-17

    func test_R17_drop_alwaysClearsTheOverlay_andStaysOnTheStep() {
        let h = Harness()
        h.startCulling(); h.keepN(1)
        for n in 1...4 {
            h.go(n)
            let before = h.state
            h.model.dropHover(true)
            XCTAssertTrue(h.model.imports.dropTargeted)
            // Not files: text, a web link.
            h.model.dropFiles([URL(string: "https://example.com/a.jpg")!])
            XCTAssertFalse(h.model.imports.dropTargeted, "overlay stuck after a drop of non-files")
            XCTAssertEqual(h.state.step, before.step); XCTAssertEqual(h.state.total, before.total)
            h.model.dropHover(true)
            h.model.dropFiles([])
            XCTAssertFalse(h.model.imports.dropTargeted)
            h.model.dropHover(true); h.model.dropHover(false)
            XCTAssertFalse(h.model.imports.dropTargeted, "overlay stuck after the drag left")
            XCTAssertEqual(h.state.step, before.step)
        }
        XCTAssertEqual(h.state.errors, 0)
    }

    // MARK: the top bar

    func test_topBar_heightsPaddingAndBreakpoints() {
        func bar(_ w: CGFloat, _ h: CGFloat) -> TopBarLayout { TopBarLayout(window: CGSize(width: w, height: h), scale: LayoutScale.scale(for: CGSize(width: w, height: h))) }
        XCTAssertEqual(bar(1100, 759).height, 38); XCTAssertEqual(bar(1100, 760).height, 42); XCTAssertEqual(bar(1100, 900).height, 48)
        XCTAssertEqual(bar(699, 700).leading, 10); XCTAssertEqual(bar(700, 700).leading, 20); XCTAssertEqual(bar(700, 700).trailing, 20)
        XCTAssertEqual(bar(559, 700).tabWidth, 60); XCTAssertEqual(bar(560, 700).tabWidth, 72); XCTAssertEqual(bar(760, 700).tabWidth, 88)
        XCTAssertFalse(bar(699, 700).showsWordmark); XCTAssertTrue(bar(700, 700).showsWordmark)
        XCTAssertFalse(bar(759, 700).showsHints); XCTAssertTrue(bar(760, 700).showsHints)
        XCTAssertFalse(bar(899, 700).showsMeta); XCTAssertTrue(bar(900, 700).showsMeta)
        XCTAssertEqual(bar(1100, 760).tabHeight, 24); XCTAssertEqual(bar(1100, 760).copySlot, 118)
        XCTAssertEqual(bar(1100, 760).thumbOffset(.save), 3 * 88)
    }

    func test_R54_topBarScalesOnBigWindows() {
        let big = CGSize(width: 2560, height: 1440), b = TopBarLayout(window: big, scale: LayoutScale.scale(for: big))
        XCTAssertEqual(b.height, 60); XCTAssertEqual(b.tabWidth, 110); XCTAssertEqual(b.tabHeight, 30); XCTAssertEqual(b.leading, 25)
        // R-59: no jumps on the way there.
        var prev: TopBarLayout?
        for w in stride(from: 1440.0, through: 2560, by: 20) {
            let size = CGSize(width: w, height: w * 900 / 1440), l = TopBarLayout(window: size, scale: LayoutScale.scale(for: size))
            if let p = prev {
                XCTAssertLessThanOrEqual(abs(l.tabHeight - p.tabHeight), 2, "tab height jumps at \(w)")
                XCTAssertLessThanOrEqual(abs(l.height - p.height), 2, "bar height jumps at \(w)")
            }
            prev = l
        }
    }

    func test_R50_tabsFitWhole_fromTheNarrowestWindow_besideTheTrafficLights() {
        for lights in [0.0, 61, 69, 78, 92] {
            for w in stride(from: 320.0, through: 3000, by: 7) {
                for h in [420.0, 480, 760, 900, 1440] {
                    let size = CGSize(width: w, height: h), s = LayoutScale.scale(for: size)
                    let l = TopBarLayout(window: size, scale: s, trafficLights: lights)
                    let tag = "\(Int(w))×\(Int(h)), lights \(Int(lights))"
                    XCTAssertLessThanOrEqual(l.leading + l.tabsWidth + l.trailing, w, "\(tag): tabs cut off")
                    if lights > 0 { XCTAssertGreaterThanOrEqual(l.leading, lights + 8, "\(tag): tabs under the traffic lights") }
                    XCTAssertGreaterThanOrEqual(l.tabHeight, 24 * s - 0.5, "\(tag): tabs under 24pt × S")
                    XCTAssertGreaterThanOrEqual(l.tabWidth, TopBarLayout.minTabWidth, tag)
                    XCTAssertGreaterThanOrEqual(l.height, l.tabHeight + 2 * l.trackPadding, tag)
                    // From 400 wide the segments are at their spec width whatever the window has.
                    if w >= 400 { XCTAssertEqual(l.tabWidth, LayoutScale.px(Breakpoints(size).tabWidth, s), tag) }
                }
            }
        }
    }

    // MARK: shoot meta

    func test_shootMeta_wording() {
        let h = Harness()
        XCTAssertEqual(h.model.shellShootTitle, "No shoot open"); XCTAssertEqual(h.model.shellCopyStatus, ""); XCTAssertFalse(h.model.shellIsCopying)
        h.key("return", settle: 0)
        h.wait(0.6)
        let n = h.model.copied
        XCTAssertTrue((1..<117).contains(n), "the copy should be under way, at \(n)")
        XCTAssertEqual(h.model.shellCopyStatus, "Copying \(n)/117"); XCTAssertTrue(h.model.shellIsCopying)
        XCTAssertEqual(h.model.shellShootTitle, "0 keepers · 5 scenes")
        h.wait(3); h.keepN(12)
        XCTAssertEqual(h.model.shellCopyStatus, "All 117 copied and checked"); XCTAssertFalse(h.model.shellIsCopying)
        XCTAssertEqual(h.model.shellShootTitle, "12 keepers · 5 scenes")
    }

    func test_tabs_hintsAndTooltips() {
        XCTAssertEqual(Step.allCases.map(\.tabHint), ["⌘1", "⌘2", "⌘3", "⌘4"])
        XCTAssertEqual(Step.allCases.map(\.title), ["Open", "Cull", "Edit", "Save"])
        XCTAssertNil(Step.open.tabTooltip); XCTAssertNil(Step.cull.tabTooltip)
        XCTAssertEqual(Step.edit.tabTooltip, "Optional · nothing changes unless you move a setting")
        XCTAssertEqual(Step.save.tabTooltip, "Available any time · ⌘4")
    }
}
