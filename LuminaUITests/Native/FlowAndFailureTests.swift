import XCTest

/// Ports "Buttons", "Animation", "Loading", "Import/Export", "Connectors" from the stress suite.
final class FlowAndFailureTests: LuminaTestCase {
    override class var limit: TimeInterval { 180 }
    var l: Lumina!
    override func tearDown() { if let l { assertNoErrors(l); l.app.terminate() } }

    /// Every non-destructive button clicked twice fast: no errors, app stays up.
    func test_clickEverySafeButtonTwice() {
        l = Lumina().launch(); l.startCulling(); l.keepN(6)
        let skip = try! NSRegularExpression(pattern: "start over|^save|saved|out$|open folder|choose photos|copy &|continue|change…|finder", options: .caseInsensitive)
        var n = 0
        for step in [2, 3, 4] {
            l.go(step, settle: step == 3 ? 1.1 : 0.5)
            for b in l.app.buttons.allElementsBoundByIndex.prefix(40) where b.isHittable && !b.identifier.hasPrefix("debug.") {
                let t = b.label.isEmpty ? b.identifier : b.label
                if skip.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { continue }
                b.click(); b.click(); n += 1; l.esc()
            }
            if l.state.step != ["open", "cull", "edit", "save"][step - 1] { l.go(step) }
        }
        XCTAssertNil(l.alive()); XCTAssertGreaterThan(n, 10)
    }

    /// R-61
    func test_R61_nothingStuckMidAnimation() {
        l = Lumina().launch(); l.startCulling(); l.keepN(4); l.go(3, settle: 2.3)
        XCTAssertEqual(l.value("edit.photo"), "loaded")
        let a = l.el("edit.photo").frame; l.pause(0.5)
        XCTAssertEqual(l.el("edit.photo").frame, a, "photo still moving after settling")
    }

    /// R-44
    func test_R44_photoFailsToLoad_saysSo() {
        l = Lumina(faults: ["imageLoadFail"]).launch(); l.startCulling(); l.keepN(4); l.go(3, settle: 1.5)
        XCTAssertTrue(l.exists("edit.loadError", timeout: 3), "blank frame instead of a message")
        XCTAssertTrue(l.value("edit.loadError").contains("Couldn’t open"))
        l.command("{\"clearFault\":\"imageLoadFail\"}"); l.click("edit.retry")
        XCTAssertTrue(l.waitUntil(5) { l.value("edit.photo") == "loaded" })
    }

    /// R-71
    func test_R71_storageFull_warns() {
        l = Lumina().launch(); l.startCulling(); l.keepN(4); l.go(3, settle: 1.0)
        l.command("{\"injectFault\":\"storageFull\"}")
        l.key("."); l.key("."); l.pause(0.7)
        XCTAssertTrue(l.value("edit.warning").contains("Couldn’t save on this computer"))
        l.command("{\"clearFault\":\"storageFull\"}")
    }

    /// R-1A
    func test_R1A_relaunchMidCopy_resumesAndOnlyCountsUp() {
        l = Lumina(copyRate: 30).launch(); l.enter()
        XCTAssertTrue(l.waitUntil(6) { (20..<100).contains(l.state.copied) })
        let c1 = l.state.copied
        l.relaunch()
        var seen: [Int] = []
        XCTAssertTrue(l.waitUntil(15) { seen.append(l.state.copied); return l.state.copied >= l.state.total }, "copy never finished after relaunch")
        XCTAssertGreaterThanOrEqual(seen.first ?? 0, c1 - 15, "resumed far behind (saved every 15)")
        XCTAssertEqual(seen, seen.sorted(), "count went backwards")
    }

    /// R-34
    func test_R34_saveOnce_repeatNoop_formatChangeReenables() throws {
        l = Lumina().launch(); l.startCulling(); l.keepN(5); l.go(4)
        l.click("save.button"); l.pause(0.3)
        let s1 = try XCTUnwrap(l.state.saved)
        l.cmd("s"); l.pause(0.3)
        XCTAssertEqual(l.state.saved?.sig, s1.sig, "repeat save changed something")
        XCTAssertFalse(l.el("save.button").isEnabled)
        l.click("save.format.jpeg"); l.pause(0.25)
        XCTAssertTrue(l.el("save.button").isEnabled); XCTAssertTrue(l.el("save.button").label.contains("again"))
        l.click("save.button"); l.pause(0.3)
        XCTAssertEqual(l.state.saved?.fmt, "jpeg"); XCTAssertEqual(l.state.saved?.again, true)
    }

    /// R-72
    func test_R72_twoWindows_editWarnsTheOther() {
        l = Lumina().launch(); l.startCulling(); l.keepN(4); l.go(3, settle: 1.1)
        l.command("{\"openSecondWindow\":true}"); l.pause(1.2)
        let w2 = l.app.windows.element(boundBy: 1)
        l.app.windows.element(boundBy: 0).click(); l.key("."); l.key("."); l.pause(0.9)
        XCTAssertTrue(w2.staticTexts["edit.warning"].label.contains("another window") || (w2.descendants(matching: .any)["edit.warning"].value as? String ?? "").contains("another window"))
    }

    /// R-70
    func test_R70_relaunchOnEveryStep_comesBackTheSame() {
        l = Lumina().launch(); l.startCulling(); l.keepN(6)
        let k0 = l.state.keep
        for n in [2, 3, 4, 1] {
            l.go(n, settle: n == 3 ? 0.9 : 0.4); let want = l.state.step
            l.relaunch(); l.pause(0.4)
            XCTAssertEqual(l.state.step, want, "relaunched on \(want), came back on \(l.state.step)")
            XCTAssertEqual(l.state.keep, k0, "decisions changed after relaunching on \(want)")
        }
    }

    /// R-31
    func test_R31_startOverNeedsTwoClicks() {
        l = Lumina().launch(); l.startCulling(waitAll: false); l.pause(1.5); l.keepN(4); l.go(1)
        l.click("open.startOver")
        XCTAssertEqual(l.state.kept, 4, "one stray click wiped decisions")
        XCTAssertTrue(l.el("open.startOver").label.contains("Click again"))
        l.click("open.startOver"); l.pause(0.3)
        XCTAssertEqual(l.state.kept + l.state.out, 0)
    }

    /// R-32
    func test_R32_tripleClickSave_savesOnce() {
        l = Lumina().launch(); l.startCulling(); l.keepN(9); l.go(4)
        let before = l.state.saved?.sig
        l.click("save.button", times: 3); l.cmd("s"); l.cmd("s"); l.pause(0.4)
        XCTAssertNotEqual(l.state.saved?.sig, before); XCTAssertEqual(l.state.saved?.again, false, "saved more than once")
    }

    /// R-36
    func test_R36_everythingOut_nothingToSave() {
        l = Lumina().launch(); l.startCulling(); l.go(2)
        for _ in 0..<130 { l.left() }
        for _ in 0..<l.state.total { l.key("x") }
        l.go(4, settle: 1.6)
        XCTAssertTrue(l.el("save.button").label.contains("Nothing to save"))
        l.click("save.button"); l.enter(); l.cmd("s"); l.pause(0.4)
        XCTAssertNil(l.state.saved)
    }

    /// Mouse only: Open → Cull → Save with no keyboard.
    func test_mouseOnly_openToSave() {
        l = Lumina().launch(); l.click("open.card"); XCTAssertTrue(l.waitCopied(117, timeout: 20))
        let tiles = l.all(prefix: "cull.tile.")
        for i in [0, 3, 6] { tiles[i].click(); l.click("cull.keep") }
        l.click("cull.toSave"); l.pause(0.6); l.click("save.button"); l.pause(0.4)
        XCTAssertGreaterThanOrEqual(l.state.saved?.n ?? 0, 3)
    }
}
