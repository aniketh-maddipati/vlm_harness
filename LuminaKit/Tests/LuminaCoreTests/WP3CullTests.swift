import XCTest
import CoreGraphics
@testable import LuminaCore

// WP-3. Cull's rules, headless: the keys (R-04, R-05, R-08, R-28), keep suggested, U, the scene
// jumps, the justified grid for any mix of shapes (R-56, R-1C), and the key path at 5,000 photos
// (R-80, R-82).

/// A small deterministic generator, so a failing layout case can be reproduced from its seed.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class WP3CullKeyTests: XCTestCase {
    private func culling(_ card: String = "demo117") -> Harness { let h = Harness(card: card); h.startCulling(); return h }
    private var ids: [String] { Shoot.demo117.photos.map(\.id) }

    func test_R04_tenKeeps_tenUndos_threeRedos() {
        let h = culling()
        for _ in 0..<10 {
            h.key("r", settle: 0.04)
            for _ in 0..<3 { h.model.handle(KeyEvent("r", isRepeat: true)) }      // the key held down
        }
        XCTAssertEqual(h.state.kept, 10, "held repeats must not count")
        XCTAssertEqual(h.state.cur, ids[10])
        for _ in 0..<10 { h.key("cmd+z", settle: 0.03) }
        XCTAssertEqual(h.state.kept, 0); XCTAssertEqual(h.state.cur, ids[0])
        for _ in 0..<3 { h.key("cmd+shift+z", settle: 0.03) }
        XCTAssertEqual(h.state.kept, 3)
        h.key("cmd+y"); XCTAssertEqual(h.state.kept, 4, "⌘Y redoes too")
        XCTAssertEqual(h.state.keep, Dictionary(uniqueKeysWithValues: ids.prefix(4).map { ($0, true) }))
    }

    func test_R04_undoIs200Deep_thenSaysSo() {
        let h = culling("demo:400")
        for i in 0..<250 { h.key(i % 2 == 0 ? "r" : "x", settle: 0.01) }
        XCTAssertEqual(h.state.kept + h.state.out, 250)
        for _ in 0..<260 { h.key("cmd+z", settle: 0.01) }
        XCTAssertEqual(h.state.kept + h.state.out, 50, "exactly 200 steps come back")
        XCTAssertEqual(h.model.toast?.text, "Nothing to undo")
        for _ in 0..<260 { h.key("cmd+shift+z", settle: 0.01) }
        XCTAssertEqual(h.state.kept + h.state.out, 250)
        XCTAssertEqual(h.model.toast?.text, "Nothing to redo")
    }

    func test_R05_keepAndOutTogether_neverAHalfState() {
        let h = culling()
        var seen = 0
        for _ in 0..<20 {
            h.model.handle(KeyEvent("r")); h.model.handle(KeyEvent("x"))
            h.model.handle(KeyEvent("r", phase: .up)); h.model.handle(KeyEvent("x", phase: .up))
            let s = h.state
            XCTAssertEqual(s.kept + s.out + s.undecided, s.total)
            XCTAssertEqual(s.kept, s.keep.values.filter { $0 }.count); XCTAssertEqual(s.out, s.keep.values.filter { !$0 }.count)
            XCTAssertEqual(s.keep.count, s.kept + s.out, "a decision is true, false or absent")
            seen = s.kept + s.out
        }
        XCTAssertEqual(seen, 40, "each press decided one photo")
        // The same photo, both keys: the last one wins, and the counts follow.
        let d = DecisionStore(ids: ["a", "b"])
        d.mark("a", keep: true); d.mark("a", keep: false); d.mark("a", keep: false)
        XCTAssertEqual(d.keep, ["a": false]); XCTAssertEqual(d.keptCount, 0); XCTAssertEqual(d.outCount, 1)
        d.mark(["a", "b"], keep: nil)
        XCTAssertEqual(d.keep, [:]); XCTAssertEqual(d.outCount, 0)
    }

    func test_R28_xIsOut_undoRestoresThePreviousDecision() {
        let h = culling()
        h.key("r"); h.key("left")
        XCTAssertEqual(h.state.keep[ids[0]], true)
        h.key("x")
        XCTAssertEqual(h.state.keep[ids[0]], false); XCTAssertEqual(h.state.out, 1); XCTAssertEqual(h.state.kept, 0)
        XCTAssertEqual(h.model.toast?.text, "Out · DSC03260 · ⌘Z undoes")
        h.key("cmd+z")
        XCTAssertEqual(h.state.keep[ids[0]], true, "⌘Z brings back Kept, not Undecided")
        XCTAssertEqual(h.state.cur, ids[0])
        h.key("cmd+z")
        XCTAssertNil(h.state.keep[ids[0]])
    }

    func test_R08_outInEdit_thenUndoInCull_doesNotBringItBack() {
        let h = culling(); h.keepN(6)
        h.go(3, settle: 1.0)
        let c = h.state.cur!
        h.key("x", settle: 0.15)
        h.go(2, settle: 0.5); h.key("cmd+z", settle: 0.3)
        XCTAssertEqual(h.state.keep[c], false)
        XCTAssertEqual(h.state.kept, 5)
    }

    func test_undoGoesBackToThePhoto_redoToWhereUndoWasPressed() {
        let h = culling()
        h.key("r")                                   // keep 0, now on 1
        for _ in 0..<5 { h.key("right") }            // on 6
        h.key("cmd+z")
        XCTAssertEqual(h.state.cur, ids[0], "undo shows the photo the decision was made on")
        h.key("cmd+shift+z")
        XCTAssertEqual(h.state.cur, ids[6], "redo returns to where ⌘Z was pressed")
        XCTAssertEqual(h.state.keep[ids[0]], true)
        h.key("cmd+z")
        XCTAssertEqual(h.state.cur, ids[0]); XCTAssertEqual(h.state.kept, 0)
    }

    func test_rOnAKeptPhoto_isItsOwnUndoStep() {
        let h = culling()
        h.key("r"); h.key("x")                       // 0 kept, 1 out, now on 2
        h.key("left"); h.key("left"); h.key("r")     // R again on 0: nothing changes, moves to 1
        XCTAssertEqual(h.state.cur, ids[1]); XCTAssertEqual(h.state.kept, 1)
        h.key("cmd+z")
        XCTAssertEqual(h.state.cur, ids[0]); XCTAssertEqual(h.state.kept, 1); XCTAssertEqual(h.state.out, 1, "an older decision must not be undone instead")
    }

    func test_keysMoveThroughTheShoot_andStopAtTheEnds() {
        let h = culling()
        h.key("left"); XCTAssertEqual(h.state.cur, ids[0])
        h.key("right"); h.key("right"); XCTAssertEqual(h.state.cur, ids[2])
        for _ in 0..<200 { h.model.handle(KeyEvent("right", isRepeat: true)) }
        XCTAssertEqual(h.state.cur, ids.last, "held arrows repeat")
        h.key("r"); XCTAssertEqual(h.state.cur, ids.last, "R on the last photo decides and stays")
        XCTAssertEqual(h.state.keep[ids.last!], true)
    }

    func test_sceneJumps_firstPhotoOfThePreviousAndNextScene() {
        let h = culling(), scenes = Shoot.demo117.scenes
        h.key("right"); h.key("right")
        h.key("down"); XCTAssertEqual(h.state.cur, scenes[1].ids[0])
        h.key("right")
        h.key("down"); XCTAssertEqual(h.state.cur, scenes[2].ids[0])
        h.key("right"); h.key("up"); XCTAssertEqual(h.state.cur, scenes[1].ids[0], "↑ goes to the previous scene, not to the top of this one")
        h.key("up"); h.key("up"); XCTAssertEqual(h.state.cur, scenes[0].ids[0], "no scene above the first")
        for _ in 0..<9 { h.key("down") }
        XCTAssertEqual(h.state.cur, scenes[4].ids[0], "no scene below the last")
    }

    func test_sceneJump_whileCopying_onlyReachesWhatIsOnScreen() {
        let h = Harness(); h.key("return", settle: 0.1)        // about 6 of the first scene's 14 photos
        XCTAssertLessThan(h.model.copied, 14); XCTAssertGreaterThan(h.model.copied, 3)
        let before = h.state.cur
        h.key("down", settle: 0); XCTAssertEqual(h.state.cur, before, "the next scene hasn't arrived")
        for _ in 0..<40 { h.key("right", settle: 0) }
        XCTAssertEqual(h.model.shoot.position(h.state.cur), h.model.copied - 1, "→ stops at the last photo copied")
    }

    func test_U_nextUndecided_wraps_andSaysWhenDone() {
        let h = culling()
        h.key("r"); h.key("r"); h.key("x")               // 0, 1, 2 decided; on 3
        h.key("left"); h.key("left"); h.key("left")      // back on 0
        h.key("u"); XCTAssertEqual(h.state.cur, ids[3])
        h.key("u"); XCTAssertEqual(h.state.cur, ids[4])
        for _ in 0..<200 { h.key("right", settle: 0) }
        h.key("u"); XCTAssertEqual(h.state.cur, ids[3], "wraps past the end to the first undecided")
        // Decide everything: U stays put and says so.
        let d = Harness(card: "demo:30"); d.startCulling()
        for _ in 0..<d.state.total { d.key("r", settle: 0) }
        let last = d.state.cur
        d.key("u")
        XCTAssertEqual(d.state.cur, last); XCTAssertEqual(d.model.toast?.text, "Everything is decided")
        d.key("cmd+z"); d.key("right"); d.key("right"); d.key("u")
        XCTAssertEqual(d.state.cur, d.model.shoot.photos.last?.id, "the one undecided photo is found from anywhere")
    }

    func test_keepSuggested_keepsTheSceneUndecidedSuggestions_asOneStep() {
        let h = culling(), shoot = Shoot.demo117, scene = shoot.scenes[1]
        let suggested = scene.ids.filter { shoot.photo($0)!.suggested }
        XCTAssertGreaterThan(suggested.count, 2)
        // One suggested photo is already Out: it stays Out.
        h.model.select(suggested[0]); h.model.cullSet(keep: false)
        let cur = h.state.cur
        h.model.keepSuggested(scene: 1)
        XCTAssertEqual(h.state.kept, suggested.count - 1)
        XCTAssertEqual(h.state.keep[suggested[0]], false)
        for id in suggested.dropFirst() { XCTAssertEqual(h.state.keep[id], true) }
        for id in scene.ids where !suggested.contains(id) { XCTAssertNil(h.state.keep[id], "only ringed photos") }
        XCTAssertEqual(h.state.cur, cur, "the current photo doesn't move")
        XCTAssertEqual(h.model.toast?.text, "Kept \(suggested.count - 1) suggested · ⌘Z undoes")
        h.model.keepSuggested(scene: 1)
        XCTAssertEqual(h.state.kept, suggested.count - 1, "nothing left to keep: nothing happens")
        h.key("cmd+z")
        XCTAssertEqual(h.state.kept, 0, "one ⌘Z undoes the whole chip"); XCTAssertEqual(h.state.out, 1)
        h.model.keepSuggested(scene: 99)                                   // out of range: ignored
        XCTAssertEqual(h.state.kept, 0)
    }

    func test_keepAndOutButtons_decideWithoutMovingOn() {
        let h = culling()
        h.model.select(ids[3]); h.model.cullSet(keep: true)
        XCTAssertEqual(h.state.cur, ids[3]); XCTAssertEqual(h.state.keep[ids[3]], true)
        h.model.cullSet(keep: true)                                         // again: not a second undo step
        h.model.cullSet(keep: false)
        XCTAssertEqual(h.state.keep[ids[3]], false); XCTAssertEqual(h.state.cur, ids[3])
        h.key("cmd+z"); XCTAssertEqual(h.state.keep[ids[3]], true)
        h.key("cmd+z"); XCTAssertNil(h.state.keep[ids[3]])
    }

    func test_movingIsSaved_soARelaunchLandsOnThePhotoYouWereLookingAt() throws {
        let h = culling()
        // The store coalesces writes to one per 250 ms (WP-8), so each move is on disk within that.
        h.key("r"); h.key("right"); h.key("right"); h.wait(0.3)
        XCTAssertEqual(try h.store.load(shootKey: h.model.shoot.key)?.cur, ids[3])
        h.key("down"); h.wait(0.3); XCTAssertEqual(try h.store.load(shootKey: h.model.shoot.key)?.cur, h.state.cur)
        h.key("u"); h.wait(0.3); XCTAssertEqual(try h.store.load(shootKey: h.model.shoot.key)?.cur, h.state.cur)
        h.model.select(ids[9]); h.model.flushPersistence()   // quitting flushes
        XCTAssertEqual(try h.store.load(shootKey: h.model.shoot.key)?.cur, ids[9])
        // A second launch on the same store comes back to it, decisions included.
        let again = Harness(store: h.store)
        XCTAssertEqual(again.model.cullCur, ids[9]); XCTAssertEqual(again.state.keep, [ids[0]: true])
    }

    func test_message_showsThenGivesWayToTheKeyReminder() {
        let h = culling()
        h.key("r")
        XCTAssertEqual(h.model.toast?.text, "Kept DSC03260 · ⌘Z undoes")
        h.wait(2); h.key("cmd+z")
        XCTAssertEqual(h.model.toast?.text, "Undone · ⇧⌘Z redoes")
        h.wait(2); XCTAssertNotNil(h.model.toast, "the first message's timer must not clear the second")
        h.wait(1.5); XCTAssertNil(h.model.toast)
        h.key("cmd+shift+z"); XCTAssertEqual(h.model.toast?.text, "Redone")
    }

    func test_tileSize_stepsOf1_25_within64to320_andIsRemembered() throws {
        let h = culling()
        XCTAssertEqual(h.model.cullTileHeight(gridHeight: 666), 80, "no choice yet: the formula")
        XCTAssertEqual(h.model.cullTileHeight(gridHeight: 1310), 151)
        h.model.cullSession.gridHeight = 1000                               // formula says 115
        h.key("cmd+="); XCTAssertEqual(h.model.cull.tileHeightOverride, 144)
        h.key("cmd++"); XCTAssertEqual(h.model.cull.tileHeightOverride, 180)
        for _ in 0..<6 { h.key("cmd+=") }
        XCTAssertEqual(h.model.cull.tileHeightOverride, 320)
        for _ in 0..<12 { h.key("cmd+-") }
        XCTAssertEqual(h.model.cull.tileHeightOverride, 64)
        XCTAssertEqual(h.model.cullTileHeight(gridHeight: 3000), 64, "the choice wins over the formula")
        XCTAssertEqual(h.state.kept + h.state.out, 0, "⌘± decides nothing")

        // Remembered across launches that share a store directory.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wp3-prefs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func launch() -> AppModel {
            var c = LaunchConfig(arguments: ["-LuminaUITest", "YES"], environment: ["LUMINA_CARD": "demo117"]); c.storeDir = dir
            return AppModel.launch(config: c, services: Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: MemoryPersistence()), clock: TestScheduler())
        }
        let a = launch(); a.cullRestoreTileSize()
        XCTAssertNil(a.cull.tileHeightOverride)
        a.cullSession.gridHeight = 600; a.cullTileSize(1)
        XCTAssertEqual(a.cull.tileHeightOverride, 100)
        let b = launch(); b.cullRestoreTileSize()
        XCTAssertEqual(b.cull.tileHeightOverride, 100)
    }

    func test_copy_missingFieldsAreLeftOut() {
        let full = Shoot.demo117.photos[0]
        XCTAssertEqual(full.cullDetails, "ILCE-7M4 · 09:12:40 · 85mm f/2 1/250 · ISO 100")
        let p = Photo(id: "a", file: "a.jpg", time: "18:30:02", camera: "Canon EOS R6", focal: 85, aperture: 2.8, shutter: "1/250", iso: 800, source: .demo(seed: 1, bw: false))
        XCTAssertEqual(p.cullDetails, "Canon EOS R6 · 18:30:02 · 85mm f/2.8 1/250 · ISO 800")
        XCTAssertEqual(Photo(id: "b", file: "b.png", source: .demo(seed: 1, bw: false)).cullDetails, "")
        XCTAssertEqual(Photo(id: "c", file: "c", time: "10:00:00", camera: " ", aperture: 4, source: .demo(seed: 1, bw: false)).cullDetails, "10:00:00 · f/4")
        XCTAssertEqual(Photo(id: "d", file: "d", camera: "X", focal: 23.5, shutter: "—", iso: 0, source: .demo(seed: 1, bw: false)).cullDetails, "X · 23.5mm")
        for photo in Shoot.demo117.photos + [p] {
            for bad in ["undefined", "nil", "—", "Optional", "NaN", "· ·"] { XCTAssertFalse(photo.cullDetails.contains(bad), photo.cullDetails) }
        }
        XCTAssertEqual(CullCopy.state(true), "Kept"); XCTAssertEqual(CullCopy.state(false), "Out"); XCTAssertEqual(CullCopy.state(nil), "Undecided")
        // The preview's line (prototype pvSt, golden cull-mid): the camera stays in the
        // accessibility value only, a suggested keeper says so while undecided.
        XCTAssertEqual(full.cullShotDetails, "09:12:40 · 85mm f/2 1/250 · ISO 100")
        XCTAssertEqual(p.cullShotDetails, "18:30:02 · 85mm f/2.8 1/250 · ISO 800")
        XCTAssertEqual(Photo(id: "d", file: "d", camera: "X", focal: 23.5, source: .demo(seed: 1, bw: false)).cullShotDetails, "23.5mm")
        XCTAssertEqual(CullCopy.state(nil, suggested: true), "Undecided · suggested keep")
        XCTAssertEqual(CullCopy.state(nil, suggested: false), "Undecided")
        XCTAssertEqual(CullCopy.state(true, suggested: true), "Kept"); XCTAssertEqual(CullCopy.state(false, suggested: true), "Out")
        XCTAssertEqual(Shoot.demo117.photos.filter(\.suggested).count, 44)
        XCTAssertEqual(CullCopy.sceneCount(photos: 14, decided: 0), "14 photos"); XCTAssertEqual(CullCopy.sceneCount(photos: 14, decided: 3), "14 photos · 3 decided")
        XCTAssertEqual(CullCopy.toSave(kept: 12), "Save 12 keepers →"); XCTAssertEqual(CullCopy.toEdit(kept: 12), "Edit 12 keepers")
        XCTAssertEqual(CullCopy.copying(42, of: 117), "Copying 42 of 117. Photos appear here one by one…")
    }

    // MARK: load (R-80, R-82)

    func test_R80_R82_5000photos_keysStayFast_countsExact() {
        let h = Harness(card: "demo:5000", copyRate: 400)
        h.key("return"); h.wait(2)                                           // copying: about 800 on screen
        XCTAssertTrue(h.model.copying); XCTAssertLessThan(h.model.copied, 1500)
        var ms: [Double] = []
        func timed(_ k: KeyEvent) { let t = CFAbsoluteTimeGetCurrent(); h.model.handle(k); ms.append((CFAbsoluteTimeGetCurrent() - t) * 1000) }
        // R-80: keys while the copy runs.
        for i in 0..<240 {
            timed(KeyEvent(i % 4 == 3 ? "r" : "right")); if i % 4 == 0 { h.wait(0.01) }
        }
        XCTAssertLessThan(percentile95(ms), 100, "R-80 key handling while copying")
        h.wait(20)
        XCTAssertEqual(h.model.copied, h.model.total); XCTAssertFalse(h.model.copying)
        // R-82: back to the start, then every photo decided at full speed.
        for _ in 0..<60 { h.model.cullUndo() }
        for _ in 0..<(h.model.total + 5) { h.model.handle(KeyEvent("left")) }
        XCTAssertEqual(h.state.kept + h.state.out, 0); XCTAssertEqual(h.model.cullCur, h.model.shoot.photos.first?.id)
        ms = []
        let t0 = CFAbsoluteTimeGetCurrent(), total = h.model.total
        for i in 0..<total { timed(KeyEvent(i % 2 == 0 ? "r" : "x")) }
        let took = CFAbsoluteTimeGetCurrent() - t0
        let s = h.state
        XCTAssertEqual(s.undecided, 0); XCTAssertEqual(s.kept, (total + 1) / 2); XCTAssertEqual(s.out, total / 2)
        XCTAssertEqual(s.keep.count, total)
        XCTAssertLessThan(took, 60, "R-82"); XCTAssertLessThan(percentile95(ms), 100, "R-80 at 5,000 photos")
        // U, the scene keys and undo on a fully decided 5,000-photo shoot.
        ms = []
        timed(KeyEvent("u")); timed(KeyEvent("up")); timed(KeyEvent("down")); timed(KeyEvent("z", .command)); timed(KeyEvent("u"))
        XCTAssertLessThan(ms.max() ?? 0, 100)
        print(String(format: "WP3 load: %d decisions in %.2f s", total, took))
    }

    func test_R80_gridFor5000photos_isLaidOutInWellUnderAFrameBudget() {
        let shoot = Shoot.demo(5000)
        let config = CullGrid.Config(width: 1000, tileHeight: 110)
        var grid = CullGrid(shoot: shoot, visible: shoot.photos.count, config: config)
        let t = CFAbsoluteTimeGetCurrent()
        for n in stride(from: 4000, through: 5000, by: 100) { grid = CullGrid(shoot: shoot, visible: n, config: config) }
        let each = (CFAbsoluteTimeGetCurrent() - t) / 11 * 1000
        XCTAssertLessThan(each, 100, "one layout of 5,000 photos took \(each) ms")
        XCTAssertEqual(grid.items.reduce(0) { $0 + $1.tiles.count }, 5000)
        // Only a screenful is ever drawn.
        let shown = grid.range(offset: grid.contentHeight / 2, viewport: 800, overscan: 400)
        XCTAssertLessThan(shown.count, 30); XCTAssertGreaterThan(shown.count, 5)
        print(String(format: "WP3 load: 5,000-photo grid in %.2f ms, %d rows", each, grid.items.count))
    }

    private func percentile95(_ a: [Double]) -> Double { let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * 0.95))] }
}

final class WP3CullLayoutTests: XCTestCase {
    private let gap: CGFloat = 6
    private func rowWidth(_ r: CullLayout.Row) -> CGFloat { r.width(gap: gap) }

    /// Every photo once and in order; no row wider than the grid; every row but the last fills it.
    private func check(_ aspects: [CGFloat], width: CGFloat, height: CGFloat, _ note: String, file: StaticString = #filePath, line: UInt = #line) -> [CullLayout.Row] {
        let rows = CullLayout.rows(aspects: aspects, width: width, targetHeight: height, gap: gap)
        XCTAssertEqual(rows.flatMap { $0.tiles.map(\.index) }, Array(aspects.indices), "\(note): photos lost or reordered", file: file, line: line)
        for (i, r) in rows.enumerated() {
            XCTAssertFalse(r.tiles.isEmpty, "\(note): empty row", file: file, line: line)
            XCTAssertLessThanOrEqual(rowWidth(r), width + 0.5, "\(note): row \(i) is wider than the grid", file: file, line: line)
            XCTAssertGreaterThan(r.height, 0, file: file, line: line)
            XCTAssertEqual(r.last, i == rows.count - 1, file: file, line: line)
            if i < rows.count - 1 { XCTAssertEqual(rowWidth(r), width, accuracy: 0.5, "\(note): row \(i) is ragged", file: file, line: line) }
            for t in r.tiles {
                XCTAssertTrue(t.width.isFinite && t.width > 0, file: file, line: line)
                // The tile's shape is its box, scaled with the row: photos are cropped or shown whole, never stretched.
                XCTAssertEqual(t.width / r.height, CullLayout.box(aspects[t.index]).aspect, accuracy: 0.001, file: file, line: line)
            }
        }
        if let last = rows.last { XCTAssertLessThanOrEqual(last.height, height + 0.001, "\(note): the last row never grows", file: file, line: line) }
        return rows
    }

    func test_R56_randomMixes_rowsFill_heightsInRange_nothingWiderThanTheGrid() {
        var rng = SplitMix(state: 0x4C75_6D69)
        let shapes: [CGFloat] = [1.5, 1.5, 1.5, 2.0 / 3, 1, 4.0 / 3, 16.0 / 9, 3, 0.8, 0.5, 0.4, 40, 1.0 / 40, 2.0 / 3000, 0.75, 2.39]
        for round in 0..<600 {
            let width = CGFloat(Int.random(in: 300...2500, using: &rng)), height = CGFloat(Int.random(in: 64...320, using: &rng))
            let n = Int.random(in: 1...90, using: &rng)
            let aspects: [CGFloat] = (0..<n).map { _ in Bool.random(using: &rng) ? shapes.randomElement(using: &rng)! : CGFloat.random(in: 0.3...3.2, using: &rng) }
            let note = "round \(round) w \(width) h \(height) n \(n)"
            let rows = check(aspects, width: width, height: height, note)
            // Once the grid is about five tiles wide every row can be scaled within ×0.8…×1.25.
            if width >= 5.5 * height {
                for r in rows { XCTAssertTrue((0.8 * height - 0.001...1.25 * height + 0.001).contains(r.height), "\(note): row height \(r.height)") }
            }
            // A last row that doesn't reach the right edge is at the tile height, left-aligned.
            if let last = rows.last, rowWidth(last) < width - 0.5 { XCTAssertEqual(last.height, height, accuracy: 0.001, "\(note): the last row stays at the tile height") }
        }
    }

    func test_R1C_oddShapes_andOddInputs() {
        // All panoramas, all strips, one of each, on a phone-wide grid and a wall-wide one.
        for width in [120, 280, 440, 900, 2500] as [CGFloat] {
            for height in [64, 80, 172, 320] as [CGFloat] {
                _ = check(Array(repeating: 40, count: 9), width: width, height: height, "panoramas \(width)×\(height)")
                _ = check(Array(repeating: 1.0 / 40, count: 9), width: width, height: height, "strips \(width)×\(height)")
                _ = check([1, 40, 1.0 / 40, 1.5, 2.0 / 3000], width: width, height: height, "shapes fixture \(width)×\(height)")
                _ = check([1.5], width: width, height: height, "one photo \(width)×\(height)")
            }
        }
        XCTAssertTrue(CullLayout.rows(aspects: [], width: 800, targetHeight: 100, gap: 6).isEmpty)
        // Nonsense in, something sane out.
        let odd = CullLayout.rows(aspects: [0, -1, .nan, .infinity, 1.5], width: 800, targetHeight: 100, gap: 6)
        XCTAssertEqual(odd.flatMap(\.tiles).count, 5)
        for t in odd.flatMap(\.tiles) { XCTAssertTrue(t.width.isFinite && t.width > 0) }
        XCTAssertEqual(CullLayout.rows(aspects: [1.5, 1.5], width: 0, targetHeight: 100, gap: 6).flatMap(\.tiles).count, 2, "a zero-width grid doesn't trap")
    }

    func test_boxes_portraitsFill_onlyStripsAreShownWhole() {
        XCTAssertEqual(CullLayout.box(1.5).aspect, 1.5); XCTAssertFalse(CullLayout.box(1.5).contain)
        XCTAssertEqual(CullLayout.box(2.0 / 3).aspect, 2.0 / 3, "a portrait's box is the portrait: nothing wasted (R-56)")
        XCTAssertFalse(CullLayout.box(2.0 / 3).contain); XCTAssertFalse(CullLayout.box(0.5).contain)
        XCTAssertTrue(CullLayout.box(0.49).contain); XCTAssertTrue(CullLayout.box(1.0 / 40).contain)
        XCTAssertEqual(CullLayout.box(0.4).aspect, 1.0)
        XCTAssertEqual(CullLayout.box(40).aspect, 1.8); XCTAssertFalse(CullLayout.box(40).contain)
    }

    func test_tileHeight_followsTheGridHeight() {
        XCTAssertEqual(CullLayout.tileHeight(gridHeight: 666), 80); XCTAssertEqual(CullLayout.tileHeight(gridHeight: 966), 111)
        XCTAssertEqual(CullLayout.tileHeight(gridHeight: 1310), 151); XCTAssertEqual(CullLayout.tileHeight(gridHeight: 5000), 200)
        for h in stride(from: 200, through: 2400, by: 37) as StrideThrough<CGFloat> {
            XCTAssertGreaterThanOrEqual(CullLayout.tileHeight(gridHeight: h), min(200, 0.10 * h) - 1, "R-56 at \(h)")
        }
    }

    func test_grid_demoShoot_everyWindowSize_rowsFill_positionsStack() {
        let shoot = Shoot.demo117
        // Grid widths and heights of the windows the sizing tests use (preview column and padding taken off).
        for (w, h) in [(642, 666), (853, 802), (1537, 1310), (440, 706), (280, 386), (1820, 506), (560, 206), (595, 1262)] as [(CGFloat, CGFloat)] {
            let tile = CullLayout.tileHeight(gridHeight: h)
            let grid = CullGrid(shoot: shoot, visible: 117, config: .init(width: w, tileHeight: tile))
            XCTAssertEqual(grid.items.flatMap { $0.tiles.map(\.id) }, shoot.photos.map(\.id), "every photo once, in order")
            XCTAssertEqual(grid.items.filter { $0.kind == .header }.map(\.scene), [0, 1, 2, 3, 4])
            for r in grid.metricRows where !r.last { XCTAssertEqual(r.width, r.gridWidth, accuracy: 0.5, "\(w)×\(h): scene \(r.scene) row ragged") }
            for r in grid.metricRows { XCTAssertLessThanOrEqual(r.width, r.gridWidth + 0.5) }
            var y: CGFloat = 0
            for item in grid.items { XCTAssertGreaterThanOrEqual(item.y, y, "items overlap"); y = item.y + item.height }
            XCTAssertEqual(grid.contentHeight, y + 24, accuracy: 0.001)
            XCTAssertEqual(grid.items.first?.y, 16)
        }
    }

    func test_grid_whileCopying_showsOnlyWhatArrived_andTheCopyLine() {
        let shoot = Shoot.demo117
        XCTAssertTrue(CullGrid(shoot: shoot, visible: 0, config: .init(width: 600, tileHeight: 80, copyLine: 20)).items.isEmpty)
        let grid = CullGrid(shoot: shoot, visible: 20, config: .init(width: 600, tileHeight: 80, copyLine: 20))
        XCTAssertEqual(grid.items.flatMap { $0.tiles.map(\.id) }, shoot.photos.prefix(20).map(\.id))
        XCTAssertEqual(grid.items.filter { $0.kind == .header }.count, 2, "the third scene hasn't started")
        XCTAssertEqual(grid.sceneIDs[1]?.count, 6); XCTAssertNil(grid.sceneIDs[2])
        XCTAssertEqual(grid.items.last?.kind, .copyLine)
        XCTAssertNil(grid.item(of: shoot.photos[20].id)); XCTAssertNotNil(grid.item(of: shoot.photos[19].id))
        XCTAssertEqual(Set(grid.sceneSuggested[0] ?? []), Set(shoot.scenes[0].ids.filter { shoot.photo($0)!.suggested }))
        // Rows already full don't move when more photos arrive.
        let later = CullGrid(shoot: shoot, visible: 40, config: .init(width: 600, tileHeight: 80, copyLine: 20))
        let firstScene = grid.items.filter { $0.scene == 0 }
        XCTAssertEqual(Array(later.items.prefix(firstScene.count)), firstScene)
    }

    func test_grid_extendedByTheCopy_equalsAGridBuiltFromScratch() {
        var rng = SplitMix(state: 7)
        for shoot in [Shoot.demo117, Shoot.demo(1500)] {
            let config = CullGrid.Config(width: 700, tileHeight: 90, copyLine: 20)
            var grid = CullGrid(shoot: shoot, visible: 1, config: config), n = 1
            while n < shoot.photos.count {
                n = min(shoot.photos.count, n + Int.random(in: 1...(shoot.photos.count / 20), using: &rng))
                XCTAssertTrue(grid.extend(shoot: shoot, visible: n))
                let fresh = CullGrid(shoot: shoot, visible: n, config: config)
                XCTAssertEqual(grid.items, fresh.items, "\(n) photos")
                XCTAssertEqual(grid.contentHeight, fresh.contentHeight); XCTAssertEqual(grid.sceneIDs, fresh.sceneIDs); XCTAssertEqual(grid.sceneSuggested, fresh.sceneSuggested)
                XCTAssertEqual(grid.item(of: shoot.photos[n - 1].id), fresh.item(of: shoot.photos[n - 1].id))
                XCTAssertEqual(grid.item(of: shoot.photos[n / 2].id), fresh.item(of: shoot.photos[n / 2].id))
            }
            XCTAssertTrue(grid.extend(shoot: shoot, visible: n), "nothing new is fine")
            XCTAssertFalse(grid.extend(shoot: shoot, visible: n - 1), "it never shrinks")
        }
        // A shoot whose scenes are not in photo order is refused, and the grid is left alone.
        var mixed = Shoot.demo117
        mixed.scenes[0].ids.swapAt(0, mixed.scenes[0].ids.count - 1)
        var grid = CullGrid(shoot: mixed, visible: 5, config: .init(width: 700, tileHeight: 90))
        let before = grid.items
        XCTAssertFalse(grid.extend(shoot: mixed, visible: 9)); XCTAssertEqual(grid.items, before)
    }

    func test_grid_keepsTheCurrentPhotoInView_withTheSmallestMove() {
        let shoot = Shoot.demo(1500), viewport: CGFloat = 600
        let grid = CullGrid(shoot: shoot, visible: 1500, config: .init(width: 640, tileHeight: 80))
        func rect(_ i: Int) -> (top: CGFloat, bottom: CGFloat) { let it = grid.item(of: shoot.photos[i].id)!; return (it.y, it.y + it.height) }
        // Already in view: nothing moves.
        XCTAssertNil(grid.offsetShowing(shoot.photos[0].id, offset: 0, viewport: viewport))
        XCTAssertNil(grid.offsetShowing(nil, offset: 0, viewport: viewport)); XCTAssertNil(grid.offsetShowing("nope", offset: 0, viewport: viewport))
        // Walk down the whole shoot, then back up: the photo is always fully in view afterwards,
        // and a step never scrolls more than a couple of rows.
        var offset: CGFloat = 0, moves = 0
        for i in Array(0..<1500) + Array((0..<1500).reversed()) {
            if let o = grid.offsetShowing(shoot.photos[i].id, offset: offset, viewport: viewport) {
                XCTAssertLessThan(abs(o - offset), 260, "photo \(i): a jump of \(abs(o - offset))pt")
                XCTAssertTrue((0...grid.contentHeight - viewport).contains(o))
                offset = o; moves += 1
            }
            let r = rect(i)
            XCTAssertGreaterThanOrEqual(r.top, offset - 0.5, "photo \(i) is above the view"); XCTAssertLessThanOrEqual(r.bottom, offset + viewport + 0.5, "photo \(i) is below the view")
        }
        XCTAssertLessThan(moves, 2 * grid.items.count, "no scrolling while the photo is in view")
        XCTAssertEqual(offset, 0, "back at the top, the first header shows again")
        // A far jump (undo, a scene key) lands with the row clear of the edge, header included.
        let far = shoot.scenes[3].ids[0], o = grid.offsetShowing(far, offset: 0, viewport: viewport)!
        let row = grid.item(of: far)!, header = grid.items.first { $0.kind == .header && $0.scene == 3 }!
        XCTAssertLessThanOrEqual(row.y + row.height, o + viewport - 8); XCTAssertGreaterThanOrEqual(row.y, o)
        XCTAssertNil(grid.offsetShowing(far, offset: o, viewport: viewport), "showing it twice doesn't move twice")
        let back = grid.offsetShowing(far, offset: grid.contentHeight - viewport, viewport: viewport)!
        XCTAssertLessThanOrEqual(back, header.y, "scrolling up to a scene's first row brings its header along")
        // What is drawn covers the viewport and little more.
        let range = grid.range(offset: o, viewport: viewport, overscan: 300)
        XCTAssertLessThanOrEqual(grid.items[range.lowerBound].y, o); XCTAssertGreaterThanOrEqual(grid.items[range.upperBound - 1].y + grid.items[range.upperBound - 1].height, o + viewport)
        XCTAssertLessThan(range.count, 24)
        XCTAssertEqual(grid.range(offset: 0, viewport: 0, overscan: 0).count, 0)
        XCTAssertEqual(grid.range(offset: grid.contentHeight + 5000, viewport: viewport, overscan: 100).count, 0)
    }
}

/// Out's picture (README §2 "Tiles", tokens outDim `grayscale(1) brightness(0.7)`): grey, at 70 %,
/// in the pixels, so it shows where Core Animation filters are not drawn (lumina-snap, goldens).
final class WP3OutDimTests: XCTestCase {
    /// A `w` × `h` sRGB picture of one colour.
    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, w: Int = 6, h: Int = 4) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// The first pixel's grey value, 0…255.
    private func grey(_ image: CGImage) -> Int {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: image.colorSpace!,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Int(ctx.data!.load(as: UInt8.self))
    }

    func test_outDim_isGreyAtSeventyPercent() throws {
        let white = try XCTUnwrap(OutDim.image(solid(1, 1, 1)))
        XCTAssertEqual(white.width, 6); XCTAssertEqual(white.height, 4)
        XCTAssertEqual(white.colorSpace?.model, .monochrome, "grey, one channel")
        XCTAssertEqual(grey(white), Int((255 * OutDim.brightness).rounded()), accuracy: 2)
        XCTAssertEqual(grey(try XCTUnwrap(OutDim.image(solid(0, 0, 0)))), 0)
        // A colour turns into a grey darker than white's, and green reads brighter than blue.
        let green = grey(try XCTUnwrap(OutDim.image(solid(0, 1, 0)))), blue = grey(try XCTUnwrap(OutDim.image(solid(0, 0, 1))))
        XCTAssertGreaterThan(green, blue); XCTAssertLessThan(green, grey(white)); XCTAssertGreaterThan(blue, 0)
    }
}
