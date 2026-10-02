import XCTest
import CoreGraphics
@testable import LuminaCore

// The design's "Lumina Newbie Test.dc.html" (wrong files, clumsy, screens and flow, soak),
// headless: what a first-timer does, step by step, and the words they see on the way (the strings
// the model hands the screens: `openCardButton`, `imports.message`, the toast, `savePresentation`…).
// Clicks are the model functions the views call; keys go through `model.handle` as in the app.
// Every random run has a fixed seed and a fixed count. Shared helpers are in StressSuiteTests.swift.
//
// Already headless, rule by rule (not repeated here):
//   mixed, onlyJunk, onlyRaw, empty, dupes, nested, names, shapes, exif, rotated, drop,
//   dropDuring, reconnect, bigImport          → WP2ImportTests (test_R10…R1D, R17, R18, R19, R85)
//   reloadEvery (every step, deep)            → WP8PersistenceTests/test_R70_relaunchOnEveryStep_comesBackTheSame
//
// UI-only (they need the real window, its pixels or its focus), they stay in the XCUITests:
//   names / stretch: nothing pushes the layout sideways, tabs and main action visible
//                                             → LuminaUITests/FirstTimerTests/test_R1B_oddNames_importAndLayoutHolds,
//                                               LuminaUITests/LayoutAndSizingTests/test_R50_everyWindowShape_noSidewaysScroll_tabsAndMainActionVisible
//   shapes / rotated: true shape on screen    → LuminaUITests/FirstTimerTests/test_R1C_oddShapes_trueAspectInEdit, test_R1D_rotatedPhonePhoto_uprightNotSquashed
//   drop: the browser / window never navigates to the file → LuminaUITests/FirstTimerTests/test_R17_dropOnCull_addsAndStays
//   noKeepEdit: the empty state's words and its button (the view's own text)
//                                             → LuminaUITests/FirstTimerTests/test_R45_straightToEdit_nothingKept_explains
//   monkey / triple / mouseOnly: real clicks anywhere on screen
//                                             → LuminaUITests/FirstTimerTests/test_monkey300RandomClicks, FlowAndFailureTests/test_mouseOnly_openToSave
//   resizeStorm: dragging the real window corner → LuminaUITests/LayoutAndSizingTests/test_resizeStorm_whileEditing
//   soak sDom / sMem: on-screen element count and memory → LuminaUITests/SoakTests/test_R90_R93_soak
//   soak sBig: a big import after the soak    → LuminaUITests/SoakTests/test_R90_R93_soak (headless big import: WP2ImportTests/test_R85…)

private func newbieCopy(_ fixture: URL) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-newbie-\(ProcessInfo.processInfo.processIdentifier)/\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let to = dir.appendingPathComponent(fixture.lastPathComponent)
    try! FileManager.default.copyItem(at: fixture, to: to)
    return to
}

@MainActor
private extension Harness {
    /// One click on something the screen shows right now (the function its view calls).
    func click(_ rng: inout SuiteRNG) -> String {
        let m = model
        if rng.chance(0.08) { let s = rng.pick(Step.allCases); m.go(s); return "tab \(s.title)" }
        switch m.step {
        case .open:
            switch rng.int(0..<4) {
            case 0: m.startCulling(); return "card button"
            case 1: m.startOverClick(); return "Start over"
            case 2: if m.openShowsRecent { m.resumeRecent(); return "Recent" }; return "Open (empty spot)"
            default: m.chooseFolder(); return "Open folder…"
            }
        case .cull:
            switch rng.int(0..<5) {
            case 0:
                guard let p = m.visiblePhotos.randomElement(using: &rng) else { return "grid (empty)" }
                m.select(p.id); return "tile \(p.id)"
            case 1: m.cullSet(keep: true); return "Keep"
            case 2: m.cullSet(keep: false); return "Out"
            case 3: let s = rng.int(0..<max(1, m.shoot.scenes.count)); m.keepSuggested(scene: s); return "Keep suggested, scene \(s)"
            default: let s: Step = rng.chance(0.5) ? .edit : .save; m.go(s); return "\(s.title) button"
            }
        case .edit:
            let e = m.edit
            switch e.overlay {
            case .crop?:
                switch rng.int(0..<6) {
                case 0: m.cropKeep(); return "crop Keep"
                case 1: m.cropCancel(); return "crop Cancel"
                case 2: let r = rng.pick(CropBox.ratios); m.setCropRatio(r); return "ratio \(r)"
                case 3: m.cropSwapRatio(); return "swap ratio"
                case 4: let d = rng.chance(0.5) ? 1 : -1; m.cropRotate(d); return "turn \(d)"
                default: let a = rng.double(-45...45); m.setCropAngle(a); return "angle \(a)"
                }
            case .variations?:
                let i = rng.int(0..<9)
                switch rng.int(0..<3) {
                case 0: m.variationsPick(i); return "variation \(i)"
                case 1: m.variationsSelect(i); return "hover variation \(i)"
                default: m.variationsToggle(); return "Variations button (close)"
                }
            case .sceneGrid?:
                if rng.chance(0.6), let id = m.sceneGrid?.ids.randomElement(using: &rng) { m.sceneGridPick(id); return "scene grid photo \(id)" }
                m.sceneGridClose(); return "scene grid close"
            case .help?, .intro?:
                m.helpClose(); m.introClose(); return "close help"
            case .picker?, nil:
                let keys = m.visibleSettings.map(\.key), key = keys.isEmpty ? "ev" : rng.pick(keys)
                switch rng.int(0..<16) {
                case 0:
                    guard let id = m.keptIDs.randomElement(using: &rng) else { return "filmstrip (empty)" }
                    m.editSelect(id); return "filmstrip \(id)"
                case 1: let s = rng.pick(EditSection.allCases); m.setSection(s); return "section \(s)"
                case 2: let a = rng.pick(EditSetting.colourAxes); m.setColourAxis(a); return "colour axis \(a)"
                case 3: m.resetSection(); return "Reset section"
                case 4: m.editNext(); return "Next"
                case 5: m.auto(); return "Auto"
                case 6: m.variationsToggle(); return "Variations button"
                case 7: m.sceneGridOpen(); return "scene grid"
                case 8: m.cropOpen(); return "Crop button"
                case 9:
                    let c = m.canvasSize, p = CGPoint(x: rng.double(-0.5...0.5) * Double(c.width), y: rng.double(-0.5...0.5) * Double(c.height))
                    m.zoomToggle(at: p); return "click the photo at \(p)"
                case 10: m.toggleFocus(); return "Focus button"
                case 11:
                    m.sliderDragBegan(key)
                    for _ in 0..<rng.int(1..<5) { m.sliderDragMoved(by: rng.double(-0.3...0.3), fine: rng.chance(0.3)) }
                    m.sliderDragEnded(cancel: rng.chance(0.1)); return "drag \(key)"
                case 12:
                    m.beginTyping(key)
                    let text = rng.pick(["12", "-5", "abc", "1e9", "", "0.35", "−7"]); m.commitTyping(text); return "type \(key) = \(text)"
                case 13: m.resetSetting(key); return "double-click \(key)"
                case 14:
                    m.pickWhite()
                    if m.edit.pickingWhite, rng.chance(0.7) { m.pickWhite(at: CGPoint(x: rng.double(0...1), y: rng.double(0...1))) }
                    return "white picker"
                default: m.helpOpen(); return "? button"
                }
            }
        case .save:
            switch rng.int(0..<5) {
            case 0: let f = rng.pick(SaveFormat.allCases); m.setFormat(f); return "format \(f)"
            case 1: let on = rng.chance(0.5); m.setWithEdits(on); return "include edits \(on)"
            case 2: m.saveNow(); return "Save button"
            case 3: m.revealSaved(); return "Show in Finder"
            default: if m.savePresentation.hasUndecided { m.go(.cull) }; return "Finish culling"
            }
        }
    }

    /// One key from anywhere on the keyboard, sometimes with a modifier on top.
    func mashKey(_ rng: inout SuiteRNG) -> String {
        var k = rng.pick(Harness.stormKeys)
        if rng.chance(0.25) { let mod = rng.pick(["cmd", "alt", "shift"]); if !k.contains(mod + "+") { k = mod + "+" + k } }
        key(k, settle: rng.pick([0, 0.01, 0.05, 0.2, 0.6]), isRepeat: rng.chance(0.05))
        return k
    }
}

@MainActor
final class NewbieSuiteTests: XCTestCase {
    override class func tearDown() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("lumina-newbie-\(ProcessInfo.processInfo.processIdentifier)"))
    }
    override func tearDown() async throws { Faults.shared.clearAll() }

    private func inEdit(_ n: Int = 9, store: (any PersistenceStore)? = nil) -> Harness {
        let h = Harness(store: store)
        h.startCulling(); h.keepN(n); h.wait(0.3); h.go(3, settle: 1.2)
        return h
    }
    /// Quit (everything written) and open the app again on the same store.
    private func relaunch(_ h: Harness) -> Harness { h.model.flushPersistence(); return Harness(store: h.store) }

    // MARK: first-timer flows

    /// Open the demo card, cull a few, look at Edit without changing anything, save. The words on
    /// every screen along the way.
    func test_firstTimer_demoCard_cullEditNothingSave_wordsAlongTheWay() async throws {
        let h = Harness()
        XCTAssertEqual(h.state.step, "open")
        XCTAssertEqual(h.model.openCardName, "SD card · Untitled")
        XCTAssertEqual(h.model.openCardDetails, "ILCE-7M4 · 117 photos · 5 scenes · 09:12–19:14")
        XCTAssertEqual(h.model.openCardButton, "Copy & start culling")
        XCTAssertFalse(h.model.openShowsRecent); XCTAssertFalse(h.model.openShowsReopen)
        XCTAssertEqual(h.model.shellShootTitle, "No shoot open"); XCTAssertEqual(h.model.shellCopyStatus, "")

        // The big button (⏎): culling starts while the card copies.
        h.key("return", settle: 0.5)
        XCTAssertEqual(h.state.step, "cull"); XCTAssertTrue(h.model.copying); XCTAssertNotNil(h.state.cur)
        XCTAssertEqual(h.model.openCardButton, "Copying… start culling")
        XCTAssertTrue(h.model.shellCopyStatus.hasPrefix("Copying "), h.model.shellCopyStatus); XCTAssertTrue(h.model.shellIsCopying)
        h.wait(2)
        XCTAssertEqual(h.state.copied, 117); XCTAssertFalse(h.model.copying)
        XCTAssertEqual(h.model.shellCopyStatus, "All 117 copied and checked")
        XCTAssertEqual(h.model.openCardButton, "Continue culling")

        // Cull: three kept, one out; each says what happened and how to take it back.
        let first = try XCTUnwrap(h.state.cur)
        h.key("r"); XCTAssertEqual(h.model.toast?.text, "Kept \(first) · ⌘Z undoes")
        h.key("r"); h.key("r")
        let out = try XCTUnwrap(h.state.cur)
        h.key("x"); XCTAssertEqual(h.model.toast?.text, "Out · \(out) · ⌘Z undoes")
        XCTAssertEqual([h.state.kept, h.state.out], [3, 1])
        XCTAssertEqual(h.model.shellShootTitle, "3 keepers · 5 scenes")
        XCTAssertEqual(CullCopy.toEdit(kept: h.state.kept), "Edit 3 keepers"); XCTAssertEqual(CullCopy.toSave(kept: h.state.kept), "Save 3 keepers →")
        h.wait(AppModel.cullMessageSeconds + 0.1)
        XCTAssertNil(h.model.toast, "the message gives way to the key reminder")

        // Edit: look around, change nothing.
        h.go(3, settle: 1.2)
        XCTAssertEqual(h.state.cur, first, "Edit opens on the first keeper")
        XCTAssertEqual(h.model.editTag, "As shot"); XCTAssertEqual(h.model.editTitle, first)
        h.key("right"); h.key("right"); h.key("left")
        XCTAssertEqual(h.state.looksCount, 0); XCTAssertEqual(h.state.look, [:])

        // Save: three photos, as shot.
        h.go(4, settle: 2)
        var p = h.model.savePresentation
        XCTAssertEqual(p.summary, "3 keepers ready to save"); XCTAssertEqual(p.buttonLabel, "Save 3 photos"); XCTAssertTrue(p.buttonEnabled)
        XCTAssertEqual(p.behind, "1 out · 113 undecided · not saved"); XCTAssertTrue(p.hasUndecided)
        XCTAssertFalse(p.showsIncludeEdits, "nothing edited: no edits row"); XCTAssertNil(p.savedTitle); XCTAssertEqual(p.note, "")
        h.model.saveNow()
        p = h.model.savePresentation
        XCTAssertEqual(h.state.saved?.n, 3); XCTAssertEqual(h.state.saved?.ne, 0); XCTAssertEqual(h.state.saved?.fmt, "xmp"); XCTAssertEqual(h.state.saved?.again, false)
        XCTAssertEqual(p.buttonLabel, "✓ Saved"); XCTAssertFalse(p.buttonEnabled); XCTAssertEqual(p.note, "Up to date.")
        XCTAssertTrue(p.savedTitle?.hasPrefix("Saved · 3 photos, as shot · ") == true, p.savedTitle ?? "nil")
        XCTAssertEqual(p.savedHint, "In Lightroom: Import → Add, or Metadata → Read Metadata from Files.")
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.count, 1)
        XCTAssertTrue(h.exporter.jobs.first?.items.allSatisfy { $0.look == nil } == true, "nothing edited, nothing written as an edit")
        XCTAssertEqual(h.brokenCopy(), []); XCTAssertEqual(h.state.errors, 0)
    }

    /// noKeepEdit: straight to Edit with nothing kept, from Open (nothing copied) and from Cull:
    /// nothing acts on a photo that isn't there, and the way back to Cull works (R-45).
    func test_R45_straightToEdit_nothingKept_keysDoNothing_wayBackToCull() {
        let h = Harness()
        for from in ["open", "cull"] {
            if from == "cull" { h.go(1, settle: 0.5); h.key("return"); h.wait(2); XCTAssertEqual(h.state.step, "cull") }
            h.go(3, settle: 0.5)
            XCTAssertEqual(h.state.step, "edit"); XCTAssertNil(h.state.cur, "from \(from)"); XCTAssertTrue(h.model.keptIDs.isEmpty)
            XCTAssertEqual(h.model.editTitle, "–"); XCTAssertEqual(h.model.editTag, "")
            for k in [".", ",", "a", "x", "v", "c", "s", "z", "w", "0", "shift+0", "=", "return", "right", "left", "up", "cmd+z", "cmd+c", "cmd+v", "cmd+="] {
                h.key(k)
                guard h.checkInvariants("\(k) in an empty Edit (from \(from))") else { return }
            }
            XCTAssertEqual(h.state.looksCount, 0); XCTAssertNil(h.state.overlay); XCTAssertNil(h.state.cur); XCTAssertEqual(h.state.kept, 0)
            XCTAssertEqual(h.state.step, "edit", "⏎ with nothing to edit went somewhere")
            h.model.go(.cull)                                                       // "Go to Cull ⌘2"
            XCTAssertEqual(h.state.step, "cull")
        }
        // Keep one, and Edit has it.
        h.key("r"); h.go(3, settle: 1.2)
        XCTAssertNotNil(h.state.cur); XCTAssertEqual(h.state.errors, 0)
    }

    /// Wrong files first, then a messy folder, then back to the card: where the newbie lands
    /// and what each step says (R-10…R-13, R-19).
    func test_wrongFiles_junkThenMessyFolder_thenBackToTheCard() async {
        let h = Harness()
        h.model.importURLs([newbieCopy(Fixtures.onlyJunk)]); await h.model.importsIdle()
        XCTAssertEqual(h.state.step, "open", "nothing added: stay on Open")
        XCTAssertEqual(h.model.openImportMessage, "No photos added. Skipped 1 video · 2 not a photo. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
        XCTAssertTrue(h.model.imports.failed, "error colour")
        XCTAssertEqual(h.model.openCardButton, "Copy & start culling", "the card is still there, untouched")
        XCTAssertNil(h.model.openImportProgress)

        h.model.importURLs([newbieCopy(Fixtures.messy)]); await h.model.importsIdle()
        XCTAssertEqual(h.state.step, "cull", "photos added from Open: on to Cull")
        XCTAssertEqual(h.state.import?.msg, "Added 6 photos from Card dump. Skipped 1 video · 1 zip/archive (unzip it first) · 1 damaged or not really a photo · 1 empty (0 bytes) · 2 not a photo.")
        XCTAssertEqual(h.state.total, 6); XCTAssertEqual(h.model.shellCopyStatus, "All 6 copied and checked")
        h.key("r"); h.key("r")
        XCTAssertEqual(h.state.kept, 2)

        // The card's button goes back to the card; the folder waits on Open with its decisions.
        h.model.startCulling()
        XCTAssertFalse(h.model.shoot.local); XCTAssertEqual(h.state.total, 117); XCTAssertEqual(h.state.kept, 0)
        XCTAssertTrue(h.model.openShowsReopen); XCTAssertEqual(h.model.openReopenTitle, "Folder · Card dump")
        h.model.reopenFolder()
        XCTAssertTrue(h.model.shoot.local); XCTAssertEqual(h.state.kept, 2, "the folder's decisions came back")
        h.checkInvariants("after the round trip")
        XCTAssertEqual(h.brokenCopy(), []); XCTAssertEqual(h.state.errors, 0)
    }

    /// reloadEvery + "relaunch keeps everything": quit and reopen on each step, then what Open's
    /// Recent row says and where it leads (R-70).
    func test_R70_relaunchOnEveryStep_keepsEverything_recentSaysWhereYouWere() {
        var h = Harness(store: MemoryPersistence())
        h.startCulling(); h.keepN(6); h.key("x"); h.key("x")
        h.go(3, settle: 1.2); h.key("."); h.go(4, settle: 2); h.model.saveNow()
        let keep = h.state.keep, looks = h.model.edits.looks, saved = h.state.saved
        XCTAssertNotNil(saved)
        for n in [2, 3, 4, 1] {
            h.go(n, settle: n == 3 ? 1.2 : 0.5)
            let step = h.state.step, cur = h.state.cur
            h = relaunch(h)
            XCTAssertEqual(h.state.step, step, "came back on another step")
            XCTAssertEqual(h.state.cur, cur, "came back on another photo (\(step))")
            XCTAssertEqual(h.state.keep, keep); XCTAssertEqual(h.model.edits.looks, looks); XCTAssertEqual(h.state.saved, saved)
            h.checkInvariants("relaunched on \(step)")
        }
        XCTAssertEqual(h.model.openCardButton, "Continue culling")
        XCTAssertTrue(h.model.openShowsRecent)
        XCTAssertEqual(h.model.openRecentTitle, "Today · Untitled")
        XCTAssertEqual(h.model.openRecentDetails, "117 photos · 8 decided · 1 edited")
        XCTAssertTrue(h.model.openRecentAction.hasPrefix("Saved "), h.model.openRecentAction)
        h.model.resumeRecent()
        XCTAssertEqual(h.state.step, "cull", "photos still undecided: Recent goes on with culling")
        h.go(4, settle: 2)
        XCTAssertEqual(h.model.savePresentation.buttonLabel, "✓ Saved", "nothing changed since the save before the relaunch")
        XCTAssertEqual(h.state.errors, 0)
    }

    /// startOver: one stray click wipes nothing (and wears off); a second deliberate click does,
    /// and a relaunch brings nothing back (R-31).
    func test_R31_startOver_oneStrayClickWipesNothing_secondClickDoes() {
        var h = Harness(store: MemoryPersistence())
        h.startCulling(); h.keepN(5); h.key("x"); h.go(1, settle: 0.5)
        XCTAssertEqual(h.model.openStartOverTitle, "Start over")
        h.model.startOverClick()
        XCTAssertEqual(h.model.openStartOverTitle, "Click again to clear 6 decisions")
        XCTAssertEqual([h.state.kept, h.state.out], [5, 1], "the first click changed something")
        h.wait(4.1)
        XCTAssertEqual(h.model.openStartOverTitle, "Start over", "the second-click window didn’t end")
        h.model.startOverClick()
        XCTAssertEqual([h.state.kept, h.state.out], [5, 1], "a click after the window ended cleared")
        h.wait(0.4); h.model.startOverClick()
        XCTAssertEqual(h.state.kept + h.state.out, 0, "the second click didn’t clear")
        XCTAssertEqual(h.state.copied, 0); XCTAssertFalse(h.model.copying)
        XCTAssertEqual(h.model.openCardButton, "Copy & start culling"); XCTAssertFalse(h.model.openShowsRecent)
        XCTAssertNil(h.state.saved); XCTAssertEqual(h.state.step, "open"); XCTAssertEqual(h.model.openStartOverTitle, "Start over")
        h = relaunch(h)
        XCTAssertEqual(h.state.kept + h.state.out, 0, "a relaunch brought decisions back"); XCTAssertEqual(h.state.copied, 0)
        XCTAssertEqual(h.state.errors, 0)
    }

    // MARK: clumsy

    /// monkey: 300 seeded clicks on whatever each screen shows (no keyboard): no errors, nothing
    /// stuck (the invariants after every click), the tabs still work.
    func test_monkey_300SeededClicks_noErrors_nothingStuck_tabsStillWork() {
        let h = Harness()
        var rng = SuiteRNG(seed: 0x300C)
        for i in 0..<300 {
            let what = h.click(&rng)
            h.wait(rng.pick([0, 0.02, 0.15, 0.5]))
            h.layoutPass()
            guard h.checkInvariants("click \(i): \(what) on \(h.model.step)") else { return }
            if i % 50 == 49 { XCTAssertEqual(h.brokenCopy(), [], "after click \(i)") }
        }
        h.tabsStillWork()
        XCTAssertEqual(h.state.errors, 0)
    }

    /// triple: the main buttons triple-clicked: one copy, one decision step, one save (R-32).
    func test_R32_tripleClickingTheMainButtons_noDoubledActions() async throws {
        let h = Harness()
        for _ in 0..<3 { h.model.startCulling() }                                // "Copy & start culling"
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.model.openFeature.copyRun, 1, "the copy started more than once")
        h.wait(2); XCTAssertEqual(h.state.copied, 117)
        for _ in 0..<3 { h.model.startCulling() }                                // "Continue culling"
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.model.openFeature.copyRun, 1)
        let id = try XCTUnwrap(h.model.cullCur)
        for _ in 0..<3 { h.model.cullSet(keep: true) }                           // "Keep"
        XCTAssertEqual(h.state.kept, 1); XCTAssertEqual(h.model.cullCur, id, "Keep moved on")
        h.key("cmd+z"); XCTAssertEqual(h.state.kept, 0, "three clicks were more than one undo step")
        for _ in 0..<3 { h.model.cullSet(keep: true) }
        h.model.go(.save); h.wait(2)
        for _ in 0..<3 { h.model.saveNow() }                                     // "Save 1 photo"
        XCTAssertEqual(h.state.saved?.n, 1); XCTAssertEqual(h.state.saved?.again, false)
        XCTAssertEqual(h.model.savePresentation.buttonLabel, "✓ Saved")
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.count, 1, "one save, one export")
        XCTAssertEqual(h.state.errors, 0)
    }

    /// keyMash: 400 seeded keys and modifiers from a fresh window: no errors, nothing stuck, the
    /// app still answers.
    func test_keyMash_400SeededKeysAndModifiers_appStillAnswers() {
        let h = Harness()
        var rng = SuiteRNG(seed: 0x400)
        for i in 0..<400 {
            let k = h.mashKey(&rng)
            h.layoutPass()
            guard h.checkInvariants("key \(i): \(k) on \(h.model.step)") else { return }
        }
        h.model.releaseAllKeys()
        h.tabsStillWork()
        XCTAssertEqual(h.brokenCopy(), []); XCTAssertEqual(h.state.errors, 0)
    }

    /// mouseOnly: Open → Cull → Edit → Save with clicks only.
    func test_mouseOnly_openToSave_withClicksOnly() async {
        let h = Harness()
        h.model.startCulling(); h.wait(2)                                         // "Copy & start culling"
        let ids = h.model.visiblePhotos.prefix(8).map(\.id)
        for id in ids.prefix(4) { h.model.select(id); h.model.cullSet(keep: true) }   // a tile, then Keep
        h.model.select(ids[5]); h.model.cullSet(keep: false)
        h.model.keepSuggested(scene: 1)                                          // "Keep n suggested"
        let kept = h.state.kept
        XCTAssertGreaterThan(kept, 4, "harness: scene 1 has suggestions")
        XCTAssertEqual(h.state.out, 1)
        h.model.go(.edit); h.wait(1.2)                                            // "Edit n keepers"
        XCTAssertNotNil(h.state.cur)
        h.model.editSelect(h.model.keptIDs[2])                                    // a filmstrip photo
        XCTAssertEqual(h.state.cur, h.model.keptIDs[2])
        h.model.setSection(.colour)
        h.model.sliderDragBegan("sat_red"); h.model.sliderDragMoved(by: 0.2); h.model.sliderDragEnded()
        XCTAssertNotNil(h.state.look["sat_red"], "the drag edited the photo")
        h.model.go(.save); h.wait(0.5)                                            // the Save tab
        XCTAssertEqual(h.model.savePresentation.buttonLabel, "Save \(kept) photos")
        h.model.saveNow()
        XCTAssertEqual(h.state.saved?.n, kept); XCTAssertEqual(h.state.saved?.ne, h.model.keptLooks.count)
        XCTAssertGreaterThanOrEqual(h.state.saved?.ne ?? 0, 1)
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.first?.items.count, kept)
        XCTAssertEqual(h.state.errors, 0)
    }

    /// emptySave: everything out, then Save: it says there's nothing to save; the button, ⌘S
    /// and ⏎ do nothing (R-36).
    func test_R36_everythingOut_saveExplains_cmdSAndReturnDoNothing() async {
        let h = Harness(); h.startCulling()
        for _ in 0..<117 { h.key("x", settle: 0.005) }
        XCTAssertEqual(h.state.out, 117)
        h.go(4, settle: 2)
        let p = h.model.savePresentation
        XCTAssertEqual(p.summary, "No keepers yet"); XCTAssertEqual(p.buttonLabel, "Nothing to save yet"); XCTAssertFalse(p.buttonEnabled)
        XCTAssertEqual(p.note, "Keep photos in Cull first."); XCTAssertEqual(p.behind, "117 out · not saved")
        h.model.saveNow(); h.key("cmd+s"); h.key("return", settle: 0.4)
        XCTAssertNil(h.state.saved); XCTAssertNil(h.model.save.message)
        await h.model.saveSettled()
        XCTAssertTrue(h.exporter.jobs.isEmpty)
    }

    /// undoFlood: 150 × ⌘Z far past the start, then 150 × ⇧⌘Z, in Cull and in Edit: back exactly
    /// where it was, no errors.
    func test_undoFlood_150PastTheStart_then150Redo_cullAndEdit() {
        let h = Harness(); h.startCulling(); h.keepN(20)
        let keep = h.state.keep
        for _ in 0..<150 { h.key("cmd+z", settle: 0.005) }
        XCTAssertEqual(h.state.kept, 0); XCTAssertEqual(h.model.toast?.text, "Nothing to undo")
        for _ in 0..<150 { h.key("cmd+shift+z", settle: 0.005) }
        XCTAssertEqual(h.state.keep, keep); XCTAssertEqual(h.model.toast?.text, "Nothing to redo")
        h.checkInvariants("Cull flood")

        h.go(3, settle: 1.2)
        for i in 0..<24 { h.key(i % 4 == 3 ? "right" : ".", settle: 0.005) }
        let looks = h.model.edits.looks
        XCTAssertEqual(h.model.edits.undoCount, 18, "harness: 18 nudges, 18 undo steps"); XCTAssertFalse(looks.isEmpty)
        for _ in 0..<150 { h.key("cmd+z", settle: 0.005) }
        XCTAssertTrue(h.model.edits.looks.isEmpty); XCTAssertEqual(h.model.toast?.text, "Nothing to undo")
        XCTAssertEqual(h.state.keep, keep, "Edit's ⌘Z touched a Cull decision")
        for _ in 0..<150 { h.key("cmd+shift+z", settle: 0.005) }
        XCTAssertEqual(h.model.edits.looks, looks); XCTAssertEqual(h.model.toast?.text, "Nothing to redo")
        h.checkInvariants("Edit flood")
        XCTAssertEqual(h.state.errors, 0)
    }

    /// escapes: lost in a mode. 150 seeded mixes of help, crop, straighten, variations (tapped
    /// and held), zoom, focus, before and the white picker: at most three Esc always get back
    /// to normal, and Esc never moves or edits the photo (R-25).
    func test_R25_lostInAMode_threeEscAlwaysGetBack() {
        let h = inEdit(); h.layoutPass()
        func normal() -> Bool {
            let e = h.model.edit
            return e.overlay == nil && abs(e.zoom - 1) < 0.001 && !e.focus && !e.controlsHidden && !e.before && !e.pickingWhite && !e.straightening && h.model.escapeDepth == 0
        }
        var rng = SuiteRNG(seed: 0xE5C)
        let modes = ["h", "z", "\\", "w", "?", "c", "s", "v", "hold v", "cmd+=", "cmd+-"]
        for trial in 0..<150 {
            XCTAssertTrue(normal(), "trial \(trial) didn’t start from normal")
            let cur = h.state.cur, look = h.state.look
            var used: [String] = []
            for _ in 0..<rng.int(1..<6) {
                let m = rng.pick(modes); used.append(m)
                if m == "hold v" { h.hold("v"); h.wait(0.35) } else { h.key(m, settle: 0.05) }
                h.layoutPass()
            }
            var n = 0
            while !normal() && n < 6 { h.key("escape", settle: 0.1); h.layoutPass(); n += 1 }
            h.release("v")
            guard normal() else { XCTFail("trial \(trial) [\(used.joined(separator: " "))]: still not normal after 6 esc"); return }
            XCTAssertLessThanOrEqual(n, 3, "R-25 trial \(trial) [\(used.joined(separator: " "))] needed \(n) esc")
            XCTAssertEqual(h.state.cur, cur, "Esc moved the photo"); XCTAssertEqual(h.state.look, look, "Esc edited the photo")
            guard h.checkInvariants("trial \(trial)") else { return }
        }
    }

    /// Failed before the fix in this change: Help opened over focus + zoom + before + the white
    /// picker took four Esc presses: Esc closed only Help, and the other four layers took three
    /// more (`editEscape` keeps "never more than two left" for itself, Help's close didn't).
    func test_R25_helpOverFourLayers_threeEscInAll() {
        let h = inEdit(); h.layoutPass()
        h.key("h"); h.layoutPass(); h.key("z"); h.key("\\"); h.key("w"); h.key("?")
        XCTAssertEqual(h.state.overlay, "help")
        XCTAssertTrue(h.model.edit.focus && h.model.edit.before && h.model.edit.pickingWhite && h.state.zoom > 1, "harness: four layers under Help")
        for _ in 0..<3 { h.key("escape", settle: 0.1); h.layoutPass() }
        let e = h.model.edit
        XCTAssertNil(e.overlay); XCTAssertFalse(e.focus); XCTAssertEqual(e.zoom, 1, accuracy: 0.001)
        XCTAssertFalse(e.before, "R-25: before still on after three Esc"); XCTAssertFalse(e.pickingWhite, "R-25: picker still on after three Esc")
        XCTAssertEqual(h.model.escapeDepth, 0)
    }

    // MARK: screens

    /// stretch (state half): R-50's window shapes. Edit entered at each shape shows the photo at
    /// least 40 × 40, even a portrait one; resized into each shape while editing, too.
    ///
    /// Expected to FAIL (not fixed here, a layout decision): resized into 600 × 300 while editing,
    /// the controls below the photo keep their 138pt (they only start collapsed when Edit opens
    /// under 640 high, `Breakpoints.editControlsStartCollapsed`), the canvas is 74pt high and a
    /// portrait photo shows about 20 × 50pt. `EditLayout.frames` keeps 64pt for the canvas, which
    /// is 40pt of height but not 40pt of width for a portrait photo.
    func test_R50_everyShape_portraitPhoto_atLeast40x40_enteredOrResizedInto() {
        let shapes: [(Double, Double)] = [(320, 480), (375, 812), (600, 300), (1024, 1366), (1920, 1080), (2560, 1440), (400, 1600), (3000, 600)]
        let h = Harness(); h.startCulling(); h.keepN(40)
        guard let portrait = h.model.keptIDs.first(where: { (h.model.shoot.photo($0)?.aspect ?? 1) < 0.5 }) else { return XCTFail("harness: no portrait keeper") }
        for (w, ht) in shapes {
            // Entered at this shape.
            h.go(2, settle: 0.5); h.model.windowSize = CGSize(width: w, height: ht)
            h.model.edit.controlsCollapsed = false
            h.go(3, settle: 1.2); h.model.editSelect(portrait); h.layoutPass()
            var r = h.photoOnScreen ?? .zero
            XCTAssertGreaterThanOrEqual(min(r.width, r.height), 40, "R-50 Edit entered at \(w)×\(ht): photo \(r.size)")
            // Resized into it while editing (entered at 1100 × 760).
            h.go(2, settle: 0.5); h.model.windowSize = CGSize(width: 1100, height: 760); h.model.edit.controlsCollapsed = false
            h.go(3, settle: 1.2); h.model.editSelect(portrait); h.layoutPass()
            h.resize(w, ht)
            r = h.photoOnScreen ?? .zero
            XCTAssertGreaterThanOrEqual(min(r.width, r.height), 40, "R-50 resized into \(w)×\(ht) while editing: photo \(r.size)")
            h.checkInvariants("at \(w)×\(ht)")
        }
    }

    /// resizeStorm: 80 seeded resizes in a burst while editing, zoomed: the photo stays in the
    /// canvas, the zoom in range, nothing else moves.
    func test_R43_resizeStorm_80ResizesWhileEditing() {
        let h = inEdit(); h.layoutPass(); h.key("z")
        let cur = h.state.cur, keep = h.state.keep
        var rng = SuiteRNG(seed: 0x80)
        for i in 0..<80 {
            let w = rng.double(480...2560).rounded(), ht = rng.double(420...1440).rounded()
            h.resize(w, ht); h.wait(0.008)
            guard h.checkInvariants("resize \(i) to \(w)×\(ht)") else { return }
            let r = h.photoOnScreen ?? .zero, fit = h.model.editFitRect ?? .zero, z = h.model.edit.zoom
            let need: Double = min(40, Double(fit.width) * z, Double(fit.height) * z) - 0.5
            XCTAssertGreaterThanOrEqual(Double(min(r.width, r.height)), need, "resize \(i) to \(w)×\(ht)")
        }
        XCTAssertEqual(h.state.cur, cur); XCTAssertEqual(h.state.keep, keep); XCTAssertEqual(h.state.errors, 0)
    }

    // MARK: soak (the state half)

    /// sStuck / sErr: six rounds of chaos (40 clicks, 40 keys, 8 resizes, a lap of the steps):
    /// after every round the tabs still work, nothing is stuck, no errors, the histories stay
    /// bounded (R-90, R-73).
    func test_R90_soak_sixRoundsOfChaos_appStillAnswers() {
        let h = Harness()
        var rng = SuiteRNG(seed: 0x50A6)
        for round in 0..<6 {
            for i in 0..<40 {
                let what = h.click(&rng); h.wait(rng.pick([0, 0.05, 0.3])); h.layoutPass()
                guard h.checkInvariants("round \(round) click \(i): \(what)") else { return }
            }
            for i in 0..<40 {
                let k = h.mashKey(&rng); h.layoutPass()
                guard h.checkInvariants("round \(round) key \(i): \(k)") else { return }
            }
            h.model.releaseAllKeys()
            for _ in 0..<8 {
                h.resize(rng.double(480...2560).rounded(), rng.double(420...1440).rounded())
                guard h.checkInvariants("round \(round) resize") else { return }
            }
            h.resize(1100, 760)
            h.tabsStillWork()
            XCTAssertLessThanOrEqual(h.model.edits.undoCount, EditStore.depth)
            XCTAssertEqual(h.brokenCopy(), [], "round \(round)")
        }
        XCTAssertEqual(h.state.errors, 0)
    }
}
