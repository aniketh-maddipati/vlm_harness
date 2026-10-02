import XCTest
import CoreGraphics
@testable import LuminaCore

// The design's "Lumina Stress Test.dc.html" (keys & state, layout, loading, storage, import,
// export, connectors, load) and the load half of "Lumina Controls Test.dc.html", headless: a
// `Harness` on the virtual clock, no window, no disk, no sound. Every storm has a fixed seed and a
// fixed count, and checks the invariants after every event, so a failure names the event that
// broke them. Times are printed and held only to generous ceilings (debug build, any Mac).
//
// The shared helpers at the top (`SuiteRNG`, `Harness.problems()`, `layoutPass()`, `brokenCopy()`)
// are used by NewbieSuiteTests and ControlsSuiteTests too.
//
// UI-only (they need the real window, its pixels or its focus), they stay in the XCUITests:
//   layout     five window sizes × four steps, no sideways scroll, nothing clipped → LuminaUITests/LayoutAndSizingTests (test_R50…, R51)
//   labels     every control labelled                                            → LuminaUITests/LayoutAndSizingTests/test_R52_everyControlLabelled
//   tokens     no "undefined" / "NaN" on screen (the model's words are checked here, `brokenCopy`) → LuminaUITests/LayoutAndSizingTests/test_R53_noBrokenCopy
//   buttons    every safe button double-clicked                                  → LuminaUITests/FlowAndFailureTests/test_clickEverySafeButtonTwice
//   anim       nothing stuck mid-animation                                       → LuminaUITests/FlowAndFailureTests/test_R61_nothingStuckMidAnimation
//   imgfail    the "Couldn’t open {file}" view itself (the state is checked here) → LuminaUITests/FlowAndFailureTests/test_R44_photoFailsToLoad_saysSo
//   blur       real window focus loss (the model's `windowBlurred` is checked here) → LuminaUITests/KeysAndStateTests/test_R24_blurWhileHoldingV_closesGrid
//   load       XCTMetric timings on a release build                             → LuminaUITests/LoadTests

// MARK: - Shared helpers

/// SplitMix64: the same events on every run and every Mac.
struct SuiteRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &self)] }
    mutating func int(_ r: Range<Int>) -> Int { Int.random(in: r, using: &self) }
    mutating func double(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

/// The p-th percentile (0…1) of `a`.
func suitePercentile(_ a: [Double], _ p: Double) -> Double {
    let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))]
}

@MainActor
extension Harness {
    /// Every key the storms press: each layer's bindings, the chords, and keys bound to nothing.
    static let stormKeys = [
        "r", "x", "u", "left", "right", "up", "down", "return", "escape", "z", "h", "\\", "v", "c", "s", "a",
        ",", ".", "shift+.", "shift+,", "[", "]", "0", "shift+0", "=", "w", "t", "?", "q", "shift+q", "shift+r",
        "alt+left", "alt+right", "alt+up", "alt+down", "shift+left", "shift+right", "alt+shift+up",
        "cmd+1", "cmd+2", "cmd+3", "cmd+4", "cmd+z", "cmd+shift+z", "cmd+y", "cmd+=", "cmd+-", "cmd+0",
        "cmd+c", "cmd+v", "cmd+s", "cmd+o", "cmd+q", "space", "tab", "delete", "1", "9", "j", "home", "pagedown",
    ]

    /// What the canvas view does: report the canvas it laid out when that size changes (and when
    /// it first appears), never otherwise (`EditCanvas`'s `onChange(of: geo.size)`). Headless there
    /// is no view, so the storms call this after every event.
    func layoutPass(backingScale: CGFloat = 2) {
        guard model.step == .edit else { return }
        let e = model.edit
        let c = EditLayout.frames(window: model.windowSize, focus: e.focus, controlsHidden: e.controlsHidden, controlsCollapsed: e.controlsCollapsed).canvas
        guard model.canvas.size != c || model.canvas.backingScale != backingScale else { return }
        model.canvasResized(c, backingScale: backingScale)
    }

    /// 1:1 for the Edit photo as it is now (its crop, the canvas), worked out afresh: the oracle
    /// for `edit.oneToOne`, which the model only measures at certain moments.
    var measuredOneToOne: Double? {
        let m = model
        guard let p = m.current, let fit = m.editFitRect else { return nil }
        let box = CropBox(m.currentLook)
        var px = m.pixelSize(of: p)
        if box.turns % 2 == 1 { px = CGSize(width: px.height, height: px.width) }
        let k = CropBox.coverScale(angle: box.angle, aspect: box.frameAspect(p.aspect))
        px = CGSize(width: px.width * box.w / k, height: px.height * box.h / k)
        return EditLayout.oneToOne(pixels: px, fit: fit.size, backingScale: m.canvas.backingScale)
    }

    /// The window was resized to `w` × `h` (the shell sets the size, the canvas view measures).
    func resize(_ w: Double, _ h: Double) {
        model.windowSize = CGSize(width: w, height: h)
        layoutPass()
    }

    /// The part of the Edit photo inside the canvas, in canvas coordinates.
    var photoOnScreen: CGRect? {
        guard let fit = model.editFitRect else { return nil }
        let r = EditLayout.zoomedRect(fit: fit, zoom: model.edit.zoom, pan: model.edit.pan)
        let i = r.intersection(CGRect(origin: .zero, size: model.canvasSize))
        return i.isNull ? .zero : i
    }

    /// What must hold after any event, on any step, whatever came before. Empty = all good.
    func problems() -> [String] {
        let m = model, d = m.decisions
        var p: [String] = []
        let keptNow = d.keep.values.filter { $0 }.count, outNow = d.keep.count - keptNow
        if keptNow != d.keptCount || outNow != d.outCount { p.append("counts say \(d.keptCount) kept / \(d.outCount) out, decisions hold \(keptNow) / \(outNow)") }
        if d.keptCount + d.outCount > m.total { p.append("\(d.keptCount + d.outCount) decisions for \(m.total) photos") }
        if let id = d.keep.keys.first(where: { m.shoot.photo($0) == nil }) { p.append("a decision for \(id), which the shoot doesn't have") }
        if ErrorFunnel.count != 0 { p.append("\(ErrorFunnel.count) unexpected error(s): \(ErrorFunnel.last ?? "?")") }
        if m.copied < 0 || m.copied > m.total { p.append("copied \(m.copied) of \(m.total)") }
        if let c = m.cullCur, m.shoot.photo(c) == nil { p.append("Cull's photo \(c) isn't in the shoot") }
        if m.edits.undoCount > EditStore.depth { p.append("Edit's undo holds \(m.edits.undoCount) steps") }
        let e = m.edit
        switch m.step {
        case .cull:
            let shown = m.shoot.local ? m.total : min(m.copied, m.total)
            if shown > 0, (m.shoot.position(m.cullCur) ?? Int.max) >= shown { p.append("Cull's photo \(m.cullCur ?? "nil") isn't one of the \(shown) on screen") }
        case .edit:
            let kept = m.keptIDs
            if let c = m.editCur {
                if !kept.contains(c) { p.append("Edit shows \(c), which isn't a keeper") }
            } else if !kept.isEmpty { p.append("Edit shows nothing with \(kept.count) keepers") }
            let hi = max(1, 2 * e.oneToOne)
            if !(e.zoom >= 0.25 - 1e-9 && e.zoom <= hi + 1e-9) { p.append("zoom \(e.zoom) outside 0.25…\(hi) (R-46)") }
            if let o = measuredOneToOne, e.zoom > max(1, 2 * o) + 0.002 { p.append("zoom \(e.zoom) past 2× of the photo's real 1:1 \(o) (R-46; edit.oneToOne says \(e.oneToOne))") }
            if abs(e.zoom - 1) <= 0.001, e.pan != .zero { p.append("pan \(e.pan) at Fit") }
            if abs(e.zoom - 1) > 0.001, let fit = m.editFitRect {
                let c = m.canvasSize
                let want = EditLayout.clampPan(e.pan, fit: fit.size, zoom: e.zoom, canvas: c, padding: EditLayout.padding(canvas: c))
                if abs(want.width - e.pan.width) > 0.5 || abs(want.height - e.pan.height) > 0.5 { p.append("pan \(e.pan) past its limit \(want) (R-43)") }
            }
            if (e.overlay == .variations) != (e.variationKey != nil) { p.append("overlay \(e.overlay?.rawValue ?? "nil") with variations on \(e.variationKey ?? "nil")") }
            if (e.overlay == .crop) != (e.cropDraft != nil) { p.append("overlay \(e.overlay?.rawValue ?? "nil") with a crop draft \(e.cropDraft != nil)") }
            if (e.draggingKey != nil) != (m.editControls.drag != nil) { p.append("dragging \(e.draggingKey ?? "nil") but the drag is \(m.editControls.drag == nil ? "over" : "on")") }
        case .open, .save:
            break
        }
        if m.step != .edit {
            if e.overlay != nil || e.focus || e.typingKey != nil || e.draggingKey != nil || e.cropDraft != nil || e.zoom != 1 || e.pan != .zero || e.variationKey != nil {
                p.append("Edit's layers left up on \(m.step): overlay \(e.overlay?.rawValue ?? "nil"), focus \(e.focus), zoom \(e.zoom), typing \(e.typingKey ?? "nil"), dragging \(e.draggingKey ?? "nil")")
            }
        }
        return p
    }

    /// `problems()` as one test failure naming `what` (the event that broke them). False = stop the storm.
    @discardableResult
    func checkInvariants(_ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let p = problems()
        guard !p.isEmpty else { return true }
        XCTFail("\(what()): " + p.joined(separator: " · "), file: file, line: line)
        return false
    }

    /// Every word the model hands the screens right now: the messages, Open's card and rows, the
    /// top bar, Edit's header, Save's whole presentation.
    var shownCopy: [String] {
        let m = model, s = m.savePresentation
        var a: [String] = [m.openCardName, m.openCardDetails, m.openCardButton, m.openRecentTitle, m.openRecentDetails, m.openRecentAction,
                           m.openStartOverTitle, m.shellShootTitle, m.shellCopyStatus, m.editTitle, m.editTag]
        a += [s.summary, s.behind, s.description, s.destination, s.editsSubline, s.buttonLabel, s.note]
        let maybe: [String?] = [m.toast?.text, m.imports.message, m.openImportProgress, m.save.message, m.edit.warning, s.savedTitle, s.savedHint, m.current?.cullDetails]
        a += maybe.compactMap { $0 }
        if m.openShowsReopen { a += [m.openReopenTitle, m.openReopenDetails] }
        return a
    }

    /// The words that show something broken (R-53): "undefined", "NaN", "{{", "[object", "nil", "Optional(".
    func brokenCopy() -> [String] {
        shownCopy.filter { $0.range(of: #"undefined|NaN|\{\{|\[object|\bnil\b|Optional\("#, options: .regularExpression) != nil }
    }

    /// The four tabs still answer (the soak's "app still answers").
    func tabsStillWork(file: StaticString = #filePath, line: UInt = #line) {
        for (n, name) in [(2, "cull"), (3, "edit"), (4, "save"), (1, "open")] {
            key("cmd+\(n)", settle: 0.6)
            XCTAssertEqual(model.step.rawValue, name, "⌘\(n) didn’t reach \(name)", file: file, line: line)
        }
    }
}

// MARK: - The suite

@MainActor
final class StressSuiteTests: XCTestCase {
    override func tearDown() async throws { Faults.shared.clearAll() }

    /// Copied, `n` kept, in Edit past the ⏎ guard.
    private func inEdit(_ n: Int = 9, card: String = "demo117", store: (any PersistenceStore)? = nil) -> Harness {
        let h = Harness(card: card, store: store)
        h.startCulling(); h.keepN(n); h.wait(0.3); h.go(3, settle: 1.2)
        return h
    }

    // MARK: keys & state, in one session (the HTML suite's order, state carried over)

    func test_stressRun_keysAndState_inOneSession() {
        let h = Harness()
        // enter: six fast ⏎ (some held) start culling and never reach Save (R-01).
        for i in 0..<6 { h.key("return", settle: 0.03, isRepeat: i > 1 && i < 5) }
        h.wait(0.5)
        XCTAssertEqual(h.state.step, "cull", "enter"); XCTAssertNil(h.state.saved, "enter")
        h.wait(1)                                                                 // the HTML waits for 60 copied
        XCTAssertGreaterThanOrEqual(h.state.copied, 60)

        // mark: 10 R + 10 held repeats → 10; 10 × ⌘Z → 0; 3 × ⇧⌘Z → 3 (R-04).
        for _ in 0..<10 { h.key("r", settle: 0.04); h.key("r", settle: 0.01, isRepeat: true) }
        let a = h.state.kept
        for _ in 0..<10 { h.key("cmd+z", settle: 0.03) }
        let b = h.state.kept
        for _ in 0..<3 { h.key("cmd+shift+z", settle: 0.03) }
        XCTAssertEqual([a, b, h.state.kept], [10, 0, 3], "mark: keeps after marking, undo, redo")

        // simul: R and X in the same instant, 20 times: every decision clean, counts add up (R-05).
        for _ in 0..<20 { h.key("r", settle: 0); h.key("x", settle: 0.025) }
        h.wait(0.3)
        let s = h.state
        XCTAssertEqual(s.kept + s.out + s.undecided, s.total, "simul")
        XCTAssertEqual(s.keep.count, s.kept + s.out, "simul: a decision that is neither keep nor out")
        h.checkInvariants("simul")
        for _ in 0..<6 { h.key("r", settle: 0.04) }
        h.wait(0.2)

        // spam: 40 random ⌘1–4, 15 ms apart: the last press wins (R-02).
        var rng = SuiteRNG(seed: 0x5BA4), last = 1
        for _ in 0..<40 { last = rng.int(1..<5); h.key("cmd+\(last)", settle: 0.015) }
        h.wait(0.9)
        XCTAssertEqual(h.state.step, ["open", "cull", "edit", "save"][last - 1], "spam")

        h.go(3, settle: 1.2)
        for _ in 0..<5 { h.key("r", settle: 0.04) }                              // R in Edit: explained, nothing else
        XCTAssertEqual(h.state.looksCount, 0)

        // vrace: hold V, pick +, let go, switch photo inside the 120 ms window: nothing lands (R-06).
        let c0 = h.state.cur
        h.hold("v"); h.wait(0.12)
        XCTAssertEqual(h.state.overlay, "variations", "vrace: harness, the grid didn’t open")
        h.wait(0.23); h.key("right", settle: 0.06)
        h.release("v"); h.wait(0.02)
        h.model.editMove(1); h.wait(0.01)
        let c1 = h.state.cur
        h.wait(0.7)
        XCTAssertNotEqual(c1, c0, "vrace: the photo didn’t switch")
        XCTAssertEqual(h.state.look, [:], "vrace: the variation landed on \(c1 ?? "nil") after the switch")
        XCTAssertEqual(h.state.looksCount, 0, "vrace: the variation landed somewhere")

        // blur: leave the window while holding V: the grid closes, nothing applies (R-24).
        h.hold("v"); h.wait(0.2)
        XCTAssertEqual(h.state.overlay, "variations", "blur: harness")
        h.model.windowBlurred(); h.wait(0.25)
        XCTAssertNil(h.state.overlay, "blur: the grid stayed open")
        h.release("v"); h.wait(0.2)
        XCTAssertEqual(h.state.looksCount, 0, "blur: a variation applied")

        // flush: three nudges, then ⌘2 straight away: the edit is in the store (R-07).
        h.wait(0.4)
        for _ in 0..<3 { h.key(".", settle: 0.015) }
        let after = h.state.look
        XCTAssertNotEqual(after, [:], "flush: harness, the nudge changed nothing")
        h.key("cmd+2", settle: 0)
        let stored = (try? h.store.load(shootKey: h.model.shoot.key))?.looks.values.contains(after) ?? false
        XCTAssertTrue(stored, "flush: the edit on \(c1 ?? "nil") was lost")

        // outUndo: Out in Edit, ⌘Z in Cull: still out (R-08).
        h.go(3, settle: 1.0)
        let out = h.state.cur
        h.key("x", settle: 0.15)
        h.go(2, settle: 0.5)
        h.key("cmd+z", settle: 0.3)
        XCTAssertEqual(out.flatMap { h.state.keep[$0] }, false, "outUndo: Cull's ⌘Z brought \(out ?? "nil") back")

        // enterLast: ⏎ held on the last photo lands on Save and doesn't save (R-03).
        h.go(3, settle: 1.0)
        for _ in 0..<40 { h.key("right", settle: 0.02) }
        h.wait(0.3)
        h.key("return", settle: 0.03)
        for _ in 0..<5 { h.key("return", settle: 0.03, isRepeat: true) }
        h.wait(0.12); h.key("return", settle: 0.6)
        XCTAssertEqual(h.state.step, "save", "enterLast"); XCTAssertNil(h.state.saved, "enterLast: it saved")
        XCTAssertEqual(h.model.save.message, KeyRouter.saveGuard)

        // errors: none across the run (R-73).
        h.checkInvariants("end of the run")
        XCTAssertEqual(h.state.errors, 0)
        XCTAssertTrue(h.brokenCopy().isEmpty, "broken words: \(h.brokenCopy())")
    }

    // MARK: storms

    /// 3,000 seeded keys across all four steps (the copy running at first), some held across
    /// other keys, at rhythms from "same instant" to "after the guards": every invariant after
    /// every key.
    func test_keyStorm_3000SeededKeys_everyStep_invariantsAfterEachKey() {
        let h = Harness()
        var rng = SuiteRNG(seed: 0xC0FFEE), held: Set<String> = [], steps: Set<String> = []
        let rhythm: [TimeInterval] = [0, 0, 0.01, 0.03, 0.05, 0.12, 0.3, 0.6, 1.6]
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<3000 {
            let k = rng.pick(Harness.stormKeys)
            if (k == "v" || k == "\\"), rng.chance(0.3) { h.hold(k); held.insert(k) }
            else { h.key(k, settle: rng.pick(rhythm), isRepeat: rng.chance(0.08)) }
            if let r = held.first, rng.chance(0.2) { h.release(r); held.remove(r) }
            if rng.chance(0.02) { h.model.windowBlurred(); held.removeAll() }
            h.layoutPass()
            steps.insert(h.model.step.rawValue)
            guard h.checkInvariants("key \(i): \(k) on \(h.model.step)") else { return }
            if i % 250 == 0 { XCTAssertEqual(h.brokenCopy(), [], "key \(i)") }
        }
        for k in held { h.release(k) }
        print(String(format: "Stress keyStorm: 3000 keys in %.2f s, steps visited %@, %d kept, %d out, %d looks", CFAbsoluteTimeGetCurrent() - t0,
                     steps.sorted().joined(separator: ","), h.state.kept, h.state.out, h.state.looksCount))
        XCTAssertEqual(steps.count, 4, "the storm should visit every step")
        XCTAssertEqual(h.state.errors, 0)
        h.tabsStillWork()
    }

    /// 1,000 ⌘1–4 presses at rhythms down to 0 ms, some held: every non-held press lands on its
    /// step, and each step arrives consistent (R-02).
    func test_stepSwitchStorm_1000Presses_lastPressWins_everyArrivalConsistent() {
        let h = Harness(); h.startCulling(); h.keepN(12); h.go(3, settle: 1.2); h.key("."); h.key("right"); h.key("z")
        var rng = SuiteRNG(seed: 0x57E9), want = h.model.step
        for i in 0..<1000 {
            let n = rng.int(1..<5), held = rng.chance(0.1)
            h.key("cmd+\(n)", settle: rng.pick([0, 0, 0.005, 0.015, 0.05, 0.3]), isRepeat: held)
            if !held { want = Step.allCases[n - 1] }
            h.layoutPass()
            guard h.model.step == want else { XCTFail("press \(i): ⌘\(n)\(held ? " (held)" : "") ended on \(h.model.step), want \(want)"); return }
            guard h.checkInvariants("press \(i): ⌘\(n)") else { return }
        }
        XCTAssertEqual(h.state.kept, 12, "switching steps changed decisions")
        XCTAssertEqual(h.state.looksCount, 1, "switching steps changed edits")
        XCTAssertNil(h.state.saved, "a step switch saved")
    }

    /// Seeded R / X / moves / ⌘Z / ⇧⌘Z / ⌘Y in Cull, checked against a reference history after
    /// every key: undo and redo are exact, 200 deep (R-04).
    func test_cullUndoRedoStorm_matchesAReferenceHistory() {
        let h = Harness(); h.startCulling()
        var rng = SuiteRNG(seed: 0xDEC1DE)
        var states = [h.model.decisions.keep], at = 0
        let keys = ["r", "x", "r", "x", "r", "x", "cmd+z", "cmd+z", "cmd+z", "cmd+shift+z", "cmd+y", "left", "right", "u", "up", "down"]
        for i in 0..<1500 {
            let k = rng.pick(keys), before = h.model.decisions.keep
            let id = h.model.cullCur ?? h.model.shoot.photos[0].id
            h.key(k, settle: 0)
            var want = before
            switch k {
            case "r", "x":
                want[id] = k == "r"
                states.removeSubrange((at + 1)...); states.append(want); at += 1
                if at > DecisionStore.depth { states.removeFirst(); at -= 1 }
            case "cmd+z": if at > 0 { at -= 1 }; want = states[at]
            case "cmd+shift+z", "cmd+y": if at < states.count - 1 { at += 1 }; want = states[at]
            default: break
            }
            guard h.model.decisions.keep == want else { XCTFail("key \(i) \(k): decisions differ from the reference history"); return }
            guard h.model.decisions.canUndo == (at > 0), h.model.decisions.canRedo == (at < states.count - 1) else {
                XCTFail("key \(i) \(k): undo \(h.model.decisions.canUndo) / redo \(h.model.decisions.canRedo), reference \(at) / \(states.count - 1 - at)"); return
            }
            guard h.checkInvariants("key \(i): \(k)") else { return }
        }
        XCTAssertGreaterThan(states.count, 50, "harness: the storm should build a history")
    }

    /// Seeded nudges, resets, Auto, =, copy / paste, X, moves, ⌘Z / ⇧⌘Z in Edit, checked against
    /// a reference history of (looks, decisions) after every key: one undo step per change, Edit's
    /// ⌘Z never touches a Cull decision it didn't make (R-27, R-28).
    func test_editUndoRedoStorm_matchesAReferenceHistory() {
        struct Snap: Equatable { var looks: [String: Look]; var keep: [String: Bool] }
        let h = inEdit(40)
        var rng = SuiteRNG(seed: 0xED17)
        func snap() -> Snap { Snap(looks: h.model.edits.looks, keep: h.model.decisions.keep) }
        var states = [snap()], at = 0
        let keys = [".", ",", "shift+.", ".", ",", "[", "]", "0", "shift+0", "a", "a", "=", "cmd+c", "cmd+v", "x", "left", "right", "up", "down",
                    "cmd+z", "cmd+z", "cmd+z", "cmd+shift+z", "cmd+y"]
        for i in 0..<600 {
            let k = rng.pick(keys), before = snap()
            h.key(k, settle: rng.pick([0, 0.01, 0.3]))
            let now = snap()
            switch k {
            case "cmd+z":
                if at > 0 { at -= 1 }
                guard now == states[at] else { XCTFail("key \(i) ⌘Z: not the state before the last change"); return }
            case "cmd+shift+z", "cmd+y":
                if at < states.count - 1 { at += 1 }
                guard now == states[at] else { XCTFail("key \(i) \(k): not the state the undo left"); return }
            default:
                if now != before {
                    states.removeSubrange((at + 1)...); states.append(now); at += 1
                    if at > EditStore.depth { states.removeFirst(); at -= 1 }
                }
            }
            guard h.model.edits.undoCount == at, h.model.edits.canRedo == (at < states.count - 1) else {
                XCTFail("key \(i) \(k): Edit's history holds \(h.model.edits.undoCount) undo steps, the reference \(at): a change without a step, or two steps for one"); return
            }
            guard h.checkInvariants("key \(i): \(k)") else { return }
        }
        XCTAssertGreaterThan(states.count, 30, "harness: the storm should build a history")
        XCTAssertEqual(h.state.step, "edit")
    }

    // MARK: layout and zoom (R-43, R-46)

    /// zoomresize: zoomed in, then three resizes; then a seeded storm of 300 sizes from phone to
    /// 4K-ish with zoom, focus and photo changes mixed in: the photo stays in the canvas and the
    /// zoom in range after every one.
    func test_R43_resizeStormWhileZoomed_photoStaysVisible_zoomInRange() {
        let h = inEdit()
        h.layoutPass(); h.key("z", settle: 0.3)
        XCTAssertGreaterThan(h.state.zoom, 1)
        for (w, ht) in [(800.0, 600.0), (1300.0, 820.0), (1100.0, 760.0)] {
            h.resize(w, ht)
            let r = h.photoOnScreen ?? .zero
            XCTAssertGreaterThanOrEqual(min(r.width, r.height), 40, "zoomresize at \(w)×\(ht): photo \(r.size)")
            h.checkInvariants("zoomresize \(w)×\(ht)")
        }
        h.key("cmd+0"); XCTAssertEqual(h.state.zoom, 1)

        var rng = SuiteRNG(seed: 0x51E5)
        let shapes: [(Double, Double)] = [(480, 800), (375, 812), (1024, 1366), (1920, 1080), (2560, 1440), (3000, 600), (700, 560), (860, 600), (1440, 900)]
        for i in 0..<300 {
            if rng.chance(0.08) { h.key(rng.pick(["z", "cmd+=", "cmd+-", "h", "right", "left", "cmd+0"]), settle: 0.02) }
            let (w, ht) = rng.chance(0.3) ? rng.pick(shapes) : (rng.double(480...2560).rounded(), rng.double(420...1440).rounded())
            h.resize(w, ht)
            guard h.checkInvariants("resize \(i) to \(w)×\(ht)") else { return }
            let fit = h.model.editFitRect ?? .zero, r = h.photoOnScreen ?? .zero, z = h.model.edit.zoom
            let need: Double = min(40, Double(fit.width) * z, Double(fit.height) * z) - 0.5
            guard Double(r.width) >= need, Double(r.height) >= need else {
                XCTFail("resize \(i) to \(w)×\(ht) at zoom \(h.model.edit.zoom): only \(r.size) of the photo on screen"); return
            }
        }
        XCTAssertEqual(h.state.errors, 0)
    }

    /// zoomstorm: 200 seeded pinches anywhere on the photo (and a few nonsense magnifications):
    /// the zoom stays between ¼× of Fit and 2× of 1:1, the photo in the canvas (R-46).
    func test_R46_pinchStorm_200Pinches_zoomStaysInRange() {
        let h = inEdit(); h.layoutPass()
        var rng = SuiteRNG(seed: 0x9124)
        let cw = Double(h.model.canvasSize.width) / 2, ch = Double(h.model.canvasSize.height) / 2
        for i in 0..<200 {
            let z0 = h.model.edit.zoom
            var mag = rng.double(0.2...4)
            if i % 37 == 0 { mag = [Double.nan, .infinity, 0, -3][(i / 37) % 4] }
            let anchor = CGPoint(x: rng.double(-cw...cw), y: rng.double(-ch...ch))
            for step in 1...4 { h.model.zoom(to: z0 * (1 + (mag - 1) * Double(step) / 4), anchor: anchor) }   // one pinch, four updates
            if i % 50 == 49 { h.key("right", settle: 0.01) }
            guard h.checkInvariants("pinch \(i) ×\(mag)") else { return }
        }
        let z = h.state.zoom
        XCTAssertTrue(z >= 0.25 && z <= max(1, 2 * h.model.edit.oneToOne), "zoom ended at \(z)")
        h.key("cmd+0"); XCTAssertEqual(h.state.zoom, 1)
    }

    /// Failed before the fix in this change: ⇧⌘Z put a crop back on a canvas zoomed to 2× of the
    /// whole frame's 1:1. The crop has fewer pixels, so 1:1 got smaller, but `edit.oneToOne` was
    /// not measured again and the zoom stayed at the old 2:1, past R-46's limit (the canvas view
    /// only reports size changes, so nothing else corrected it). The same for Reset all taking a
    /// crop away under a zoomed, panned photo: the pan stayed past R-43's limit. `refitZoom()`
    /// after Edit's undo / redo and after a look change that moves the crop fixes both.
    func test_R46_undoRedoOrResetOfACropWhileZoomed_keepsZoomAndPanInRange() {
        let h = inEdit(); h.layoutPass()
        let whole = h.model.edit.oneToOne
        h.key("c"); for _ in 0..<14 { h.key("down", settle: 0.01) }; h.key("return")
        XCTAssertNil(h.state.overlay, "harness: crop kept")
        XCTAssertNotNil(h.model.currentLook[CropKey.w], "harness: crop kept")
        XCTAssertLessThan(h.model.edit.oneToOne, whole * 0.6, "harness: a smaller crop has fewer pixels")
        h.key("cmd+z")                                                            // the whole frame again
        XCTAssertNil(h.model.currentLook[CropKey.w])
        h.key("z"); h.key("cmd+=")                                                // 1:1, then 2:1 of the whole frame
        XCTAssertEqual(h.state.zoom, 2 * whole, accuracy: 0.01, "harness: at 2:1 of the whole frame")
        h.key("cmd+shift+z")                                                      // the crop comes back while zoomed
        XCTAssertNotNil(h.model.currentLook[CropKey.w], "harness: the crop is back")
        let o = h.measuredOneToOne ?? 0
        XCTAssertLessThanOrEqual(h.state.zoom, max(1, 2 * o) + 0.002, "R-46: zoom \(h.state.zoom) past 2× of 1:1 (\(o)) after redoing a crop")
        h.checkInvariants("after ⇧⌘Z of a crop while zoomed")
        let r = h.photoOnScreen ?? .zero
        XCTAssertGreaterThanOrEqual(min(r.width, r.height), 40, "R-43: photo \(r.size) on screen")

        // Turned a quarter (portrait now), zoomed into a corner, then Reset all (⇧0) takes the crop
        // and the turn away: the photo is landscape again, with a shorter reach downwards.
        h.key("c"); h.key("r"); h.key("return")
        XCTAssertEqual(h.model.currentLook[CropKey.turns], 1, "harness: turned")
        let turned = h.measuredOneToOne ?? 1
        h.model.zoom(to: 2 * turned, anchor: CGPoint(x: 100, y: 200))
        h.model.panBy(CGSize(width: 5000, height: 5000))
        XCTAssertGreaterThan(h.model.edit.pan.height, 0, "harness: panned")
        h.checkInvariants("zoomed into a corner of the turned crop")
        h.key("shift+0")
        XCTAssertNil(h.model.currentLook[CropKey.w], "harness: Reset all took the crop away")
        XCTAssertNil(h.model.currentLook[CropKey.turns], "harness: Reset all took the turn away")
        h.checkInvariants("after Reset all took the crop away under a zoomed, panned photo")
        XCTAssertEqual(h.state.errors, 0)
    }

    // MARK: loading, storage, import, export, connectors

    /// imgfail: the Edit photo fails to load: Edit says so (state `failed`, the file named) and
    /// refuses edits and Variations with a reason; Retry brings it back (R-44). Failed before the
    /// fix in this change: a nudge's own "Exposure +0.05 EV" report replaced the reason, so a
    /// nudge on a photo that didn't load read as if it had worked.
    func test_R44_photoFailsToLoad_editSaysSo_andRefusesEdits() async {
        let h = inEdit()
        Faults.shared.inject(.imageLoadFail)
        let photo = h.model.current
        h.model.photoLoader.show(photo, look: nil, maxPixel: 800, in: h.model)
        await h.model.photoLoader.settle()
        XCTAssertEqual(h.model.edit.photo, .failed, "a failed load must not look like an empty frame")
        XCTAssertEqual(h.model.photoLoader.failedFile, photo?.file)
        h.key(".")
        XCTAssertEqual(h.state.look, [:]); XCTAssertEqual(h.model.toast?.text, "This photo didn’t load. Retry first.")
        h.key("v"); XCTAssertNil(h.state.overlay)
        Faults.shared.clear(.imageLoadFail)
        h.model.photoLoader.retry(in: h.model)
        await h.model.photoLoader.settle()
        XCTAssertEqual(h.model.edit.photo, .loaded, "Retry")
        h.key("."); XCTAssertNotEqual(h.state.look, [:])
        XCTAssertEqual(h.state.errors, 0)
    }

    /// quota: storage full: Edit warns and keeps working in memory; the warning goes once a write lands (R-71).
    func test_R71_storageFull_warns_keepsWorking() {
        let h = inEdit(store: MemoryPersistence())
        Faults.shared.inject(.storageFull)
        h.key(".", settle: 0.03); h.key(".", settle: 0.7)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning)
        XCTAssertNotEqual(h.state.look, [:], "the edit is kept in memory")
        Faults.shared.clear(.storageFull)
        h.key(",", settle: 0.4)
        XCTAssertNil(h.model.edit.warning, "the warning stayed after a write landed")
        XCTAssertEqual(h.state.errors, 0, "storage full is a state, not an error")
    }

    /// resume: relaunched mid-copy (no flush: killed): the copy picks up where the store has it
    /// and finishes; the count never goes backwards (R-1A).
    func test_R1A_relaunchMidCopy_resumes_countOnlyGoesUp() throws {
        let store = MemoryPersistence()
        var h = Harness(store: store)
        h.key("return", settle: 0.5)
        let c1 = try XCTUnwrap(try store.load(shootKey: "card-demo-117")).copied
        XCTAssertGreaterThanOrEqual(c1, 15); XCTAssertLessThan(c1, 100)
        h = Harness(store: store)
        var seen = [h.state.copied]
        for _ in 0..<40 { h.wait(0.1); seen.append(h.state.copied) }
        XCTAssertGreaterThanOrEqual(seen[0], c1, "resumed below what was stored")
        XCTAssertEqual(seen, seen.sorted(), "the count went backwards: \(seen)")
        XCTAssertEqual(seen.last, 117); XCTAssertFalse(h.model.copying)
        XCTAssertEqual(h.model.shellCopyStatus, "All 117 copied and checked")
    }

    /// export: save; save again is a no-op; a format change re-enables it (R-32, R-34).
    func test_R34_saveOnce_repeatIsANoop_formatChangeReenables() async {
        let h = Harness(); h.startCulling(); h.keepN(6); h.go(4, settle: 2)
        h.model.saveNow()
        let s1 = h.state.saved
        XCTAssertNotNil(s1)
        h.key("cmd+s", settle: 0.3)
        XCTAssertEqual(h.state.saved, s1, "repeat changed the save")
        XCTAssertEqual(h.model.save.message, AppModel.alreadySaved)
        h.model.setFormat(.jpeg)
        XCTAssertTrue(h.model.savePresentation.buttonLabel.hasPrefix("Save again"), h.model.savePresentation.buttonLabel)
        XCTAssertTrue(h.model.savePresentation.buttonEnabled)
        h.model.saveNow()
        XCTAssertEqual(h.state.saved?.again, true); XCTAssertEqual(h.state.saved?.fmt, "jpeg")
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.map(\.format), [.xmp, .jpeg])
    }

    /// twowin: the same shoot in two windows: an edit in one warns the other (R-72).
    func test_R72_twoWindows_anEditWarnsTheOther() {
        let store = MemoryPersistence()
        let a = Harness(store: store); a.startCulling(); a.keepN(4); a.go(3, settle: 1.1); a.model.flushPersistence()
        let b = Harness(store: store)
        XCTAssertNil(b.model.edit.warning)
        a.key(".", settle: 0.03); a.key(".", settle: 0.9)
        XCTAssertEqual(b.model.edit.warning, AppModel.otherWindowWarning, "the second window showed no warning")
        XCTAssertNil(a.model.edit.warning, "the window that edited warned itself")
    }

    // MARK: load (117 photos)

    /// loadEdit: 300 photo switches in Edit, 95th under 50 ms (R-81); loadCull: the whole shoot
    /// marked at full speed, counts exact (R-82).
    func test_R81_R82_switch300InEdit_markTheWholeShoot() {
        let h = inEdit(30)
        var ms: [Double] = []
        for i in 0..<300 {
            let t = CFAbsoluteTimeGetCurrent()
            h.model.handle(KeyEvent(i % 3 == 2 ? "left" : "right"))
            ms.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            if i % 20 == 0 { h.wait(0) }
        }
        h.checkInvariants("after 300 switches")
        print(String(format: "Stress loadEdit: median %.2f ms · 95th %.2f ms per switch", suitePercentile(ms, 0.5), suitePercentile(ms, 0.95)))
        XCTAssertLessThan(suitePercentile(ms, 0.95), 50, "R-81")

        h.go(2, settle: 0.6)
        for _ in 0..<130 { h.model.handle(KeyEvent("left")) }
        h.wait(0.2)
        for i in 0..<130 { h.key(i % 2 == 1 ? "x" : "r", settle: 0.004) }
        h.wait(0.5)
        let s = h.state
        XCTAssertEqual(s.undecided, 0, "\(s.kept + s.out) of 117 decided"); XCTAssertEqual(s.kept + s.out, 117)
        h.checkInvariants("after marking the shoot")
    }

    // MARK: load (5,000 photos, minimal footprint: no window, no files, no pictures)

    /// The Controls suite's load run on `demo:5000`: copy the card (count exact and only going
    /// up, keys quick while it runs), decide every photo by keyboard, switch 100 photos in Edit,
    /// edit 300 (nudge + ⏎; stored edits small), save (fast, repeat no-op, format change
    /// re-enables), and relaunch (fast, nothing lost). Numbers are printed; ceilings are the
    /// rules' own, far above what the model needs.
    func test_load5000_copyDecideEditSaveRelaunch_countsExact_footprintSmall() async {
        let store = MemoryPersistence()
        var h = Harness(card: "demo:5000", copyRate: 5000, store: store)
        let total = h.model.total
        XCTAssertGreaterThan(total, 4900)
        func timed(_ k: KeyEvent) -> Double { let t = CFAbsoluteTimeGetCurrent(); h.model.handle(k); return (CFAbsoluteTimeGetCurrent() - t) * 1000 }

        // ingest + ingestKeys. Note: the clock never moves 3.2 s past the decisions below, so the
        // 5,000 message timers they leave are never run (the virtual clock would only spend time on them).
        h.key("return", settle: 0.05)
        var seen = [h.model.copied], keyMs: [Double] = []
        for i in 0..<60 { keyMs.append(timed(KeyEvent(i % 4 == 3 ? "r" : "right"))); h.wait(0.01); seen.append(h.model.copied) }
        XCTAssertTrue(h.model.copying, "harness: keys should run while the card copies")
        for _ in 0..<10 { h.wait(0.05); seen.append(h.model.copied) }
        XCTAssertEqual(seen, seen.sorted(), "ingest: the count went backwards")
        XCTAssertEqual(h.model.copied, total); XCTAssertFalse(h.model.copying)
        XCTAssertEqual(h.model.shellCopyStatus, "All \(total) copied and checked"); XCTAssertEqual(h.model.openCardButton, "Continue culling")
        XCTAssertLessThan(suitePercentile(keyMs, 0.95), 100, "R-80 ingestKeys")

        // cullAll: from the first photo, R / X across the whole shoot.
        for _ in 0..<(total + 5) { h.model.handle(KeyEvent("left")) }
        var t = CFAbsoluteTimeGetCurrent()
        for i in 0..<total { h.model.handle(KeyEvent(i % 2 == 0 ? "r" : "x")) }
        let decideS = CFAbsoluteTimeGetCurrent() - t
        var s = h.state
        XCTAssertEqual(s.undecided, 0); XCTAssertEqual(s.kept, (total + 1) / 2); XCTAssertEqual(s.out, total / 2)
        XCTAssertLessThan(decideS, 60, "R-82")
        h.checkInvariants("cullAll")

        // editBig: 100 photo switches.
        h.go(3, settle: 1.2)
        var switchMs: [Double] = []
        for i in 0..<100 { switchMs.append(timed(KeyEvent(i % 5 == 4 ? "left" : "right"))) }
        XCTAssertLessThan(suitePercentile(switchMs, 0.95), 60, "R-81 at 5,000")

        // editMany: nudge and ⏎ through 300 photos.
        var touched = Set<String>(), stepMs: [Double] = []
        for _ in 0..<300 {
            if let c = h.model.editCur { touched.insert(c) }
            h.model.handle(KeyEvent("."))
            stepMs.append(timed(KeyEvent("return")))
        }
        XCTAssertEqual(h.state.step, "edit")
        XCTAssertEqual(touched.count, 300)
        XCTAssertTrue(touched.allSatisfy { h.model.edits.isEdited($0, decisions: h.model.decisions) }, "editMany: an edit was lost")
        s = h.state
        XCTAssertGreaterThan(s.looksCount, 0); XCTAssertLessThanOrEqual(s.looksCount, 300, "bursts share one look")
        XCTAssertLessThan(s.lookBytes, 2 * 1024 * 1024, "R-86")
        XCTAssertLessThan(s.lookBytes, 40 * s.looksCount, "only what differs from the defaults is stored")
        h.checkInvariants("editMany")

        // exportBig.
        h.go(4, settle: 0.1)
        _ = h.model.savePresentation
        t = CFAbsoluteTimeGetCurrent()
        h.model.saveNow()
        let saveMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        let s1 = h.state.saved
        XCTAssertEqual(s1?.n, h.model.keptIDs.count); XCTAssertEqual(s1?.ne, h.model.keptLooks.count)
        XCTAssertGreaterThanOrEqual(s1?.ne ?? 0, touched.count, "every edited keeper is in the save")
        XCTAssertLessThan(saveMs, 500, "R-83")
        h.key("cmd+s", settle: 0)
        XCTAssertEqual(h.state.saved, s1, "exportBig: repeat changed the save")
        h.model.setFormat(.jpeg)
        XCTAssertTrue(h.model.savePresentation.buttonLabel.hasPrefix("Save again"))
        h.model.setFormat(.xmp)
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.count, 1); XCTAssertEqual(h.exporter.jobs.first?.items.count, s1?.n)

        // reloadBig.
        let keep = h.model.decisions.keep, looks = h.model.edits.looks
        h.model.flushPersistence()
        t = CFAbsoluteTimeGetCurrent()
        h = Harness(card: "demo:5000", copyRate: 5000, store: store)
        let reopenS = CFAbsoluteTimeGetCurrent() - t
        XCTAssertEqual(h.model.decisions.keep, keep, "reloadBig: decisions changed")
        XCTAssertEqual(h.model.edits.looks, looks, "reloadBig: edits changed")
        XCTAssertEqual(h.state.step, "save"); XCTAssertEqual(h.state.saved?.sig, s1?.sig)
        XCTAssertLessThan(reopenS, 4, "R-84")
        XCTAssertEqual(h.state.errors, 0)

        print(String(format: "Stress load5000: %d photos · keys while copying 95th %.2f ms · %d decided in %.2f s · Edit switch 95th %.2f ms · ⏎ 95th %.2f ms · %d looks, %d KB · save %.1f ms · relaunch %.2f s",
                     total, suitePercentile(keyMs, 0.95), total, decideS, suitePercentile(switchMs, 0.95), suitePercentile(stepMs, 0.95),
                     s.looksCount, s.lookBytes / 1024, saveMs, reopenS))
    }
}
