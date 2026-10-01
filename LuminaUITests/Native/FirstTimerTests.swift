import XCTest

/// Port of "Lumina Newbie Test.dc.html": regression (wrong files, clumsy use, screens, flow).
final class FirstTimerTests: XCTestCase {
    var l: Lumina!
    override func setUp() { continueAfterFailure = true; l = Lumina().launch() }
    override func tearDown() { assertNoErrors(l); l.app.terminate() }
    var msg: String { l.state.import?.msg ?? "" }

    // MARK: wrong files
    /// R-10, R-11, R-12
    func test_R10_messyFolder_onlyRealPhotos_everySkipExplained() {
        l.importFixture(Fixtures.messy)
        XCTAssertEqual(l.state.total, Fixtures.messyExpectedAdded)
        for want in ["video", "zip", "damaged", "empty", "not a photo"] { XCTAssertTrue(msg.contains(want), "message misses “\(want)”: \(msg)") }
        XCTAssertNil(msg.range(of: #"DS_Store|xmp|\._"#, options: .regularExpression), "mentions system files")
        XCTAssertEqual(l.state.step, "cull")
    }
    /// R-13
    func test_R13_onlyJunk_staysOnOpen_saysWhatOpens() {
        let n0 = l.state.total
        l.importFixture(Fixtures.onlyJunk)
        XCTAssertEqual(l.state.step, "open"); XCTAssertEqual(l.state.total, n0)
        XCTAssertTrue(msg.contains("No photos added")); XCTAssertTrue(msg.contains("JPEG"))
    }
    /// R-12 (native: RAW must decode; fake RAW bytes are reported as damaged, never crash)
    func test_R12_fakeRawFiles_reportedNotCrashing() {
        l.importFixture(Fixtures.raws)
        XCTAssertTrue(msg.contains("4"), msg); XCTAssertNil(l.alive())
    }
    /// R-13
    func test_R13_emptyFolder() { l.importFixture(Fixtures.empty); XCTAssertTrue(msg.lowercased().contains("empty")); XCTAssertEqual(l.state.step, "open") }
    /// R-14
    func test_R14_samePhotosTwice_noDuplicates() {
        let f = Fixtures.batch("Pick", 3)
        l.importFixture(f); l.importFixture(f)
        XCTAssertEqual(l.state.total, 3); XCTAssertTrue(msg.contains("already in this shoot"))
    }
    /// R-15
    func test_R15_nestedFolders_groupedBySubfolder() {
        l.importFixture(Fixtures.nested)
        XCTAssertEqual(l.state.total, 4)
        let headers = l.all(prefix: "cull.scene.").map(\.label).joined(separator: "|")
        XCTAssertTrue(headers.contains("Day 1") && headers.contains("Day 2"), headers)
    }
    /// R-1B
    func test_R1B_oddNames_importAndLayoutHolds() {
        l.importFixture(Fixtures.names)
        XCTAssertEqual(l.state.total, 6)
        for size in [CGSize(width: 1100, height: 760), CGSize(width: 480, height: 800)] {
            l.resize(size.width, size.height)
            for n in [2, 3, 4] {
                l.go(n, settle: n == 3 ? 0.9 : 0.4)
                if n == 2 { for t in l.all(prefix: "cull.tile.") { t.click(); XCTAssertFalse(l.hasHorizontalScroll(), "sideways at \(size)") } }
                XCTAssertFalse(l.hasHorizontalScroll(), "sideways at \(size) step \(n)")
            }
        }
    }
    /// R-1C, R-41
    func test_R1C_oddShapes_trueAspectInEdit() {
        l.importFixture(Fixtures.shapes); l.go(2)
        for _ in 0..<8 { l.left() }; for _ in 0..<5 { l.key("r"); l.pause(0.06) }
        l.go(3, settle: 1.2)
        let want: [CGFloat] = [1, 40, 1.0 / 40, 1.5, 2.0 / 3000]
        for _ in want.indices {
            XCTAssertTrue(l.waitUntil(3) { l.value("edit.photo") == "loaded" })
            let f = l.el("edit.photo").frame
            XCTAssertTrue(f.width >= 1 && f.height >= 1, "invisible")
            if min(f.width, f.height) >= 3 {
                let ratio = f.width / f.height
                XCTAssertTrue(want.contains { abs(log($0 / ratio)) < 0.05 }, "shown \(f.size), not a true shape")
            }
            l.right(); l.pause(0.5)
        }
    }
    /// R-1D
    func test_R1D_rotatedPhonePhoto_uprightNotSquashed() {
        l.importFixture(Fixtures.rotated); l.key("r"); l.go(3, settle: 1.4)
        XCTAssertTrue(l.waitUntil(3) { l.value("edit.photo") == "loaded" })
        let f = l.el("edit.photo").frame
        XCTAssertGreaterThan(f.height, f.width, "shown sideways \(f.size)")
        XCTAssertEqual(f.width / f.height, 420.0 / 640.0, accuracy: 0.03, "squashed")
    }
    /// R-16
    func test_R16_exif_groupsByShotTime_showsCamera() {
        l.importFixture(Fixtures.exifDay)
        let headers = l.all(prefix: "cull.scene.").map(\.label).joined(separator: "|")
        XCTAssertTrue(headers.contains("09:00") && headers.contains("18:30"), "not grouped by shot time: \(headers)")
        l.all(prefix: "cull.tile.").first?.click()
        let meta = l.value("cull.previewMeta")
        for want in ["EOS R6", "85mm", "f/2.8", "1/250", "ISO 800"] { XCTAssertTrue(meta.contains(want), "meta misses \(want): \(meta)") }
    }
    /// R-17
    func test_R17_dropOnCull_addsAndStays() {
        l.importFixture(Fixtures.batch("First", 1)); l.go(2)
        let n0 = l.state.total
        l.importFixture(Fixtures.batch("Second", 2, startHour: 11))
        XCTAssertEqual(l.state.total, n0 + 2); XCTAssertEqual(l.state.step, "cull")
        XCTAssertFalse(l.exists("shell.dropOverlay"), "drop overlay stuck")
        XCTAssertNil(l.alive())
    }
    /// R-18
    func test_R18_dropWhileChecking_bothBatchesAdded() {
        let a = Fixtures.batch("A", 24), b = Fixtures.batch("B", 6, startHour: 13)
        l.command("{\"drop\":[\"\(a.path)\"]}"); l.pause(0.03); l.command("{\"drop\":[\"\(b.path)\"]}")
        XCTAssertTrue(l.waitUntil(30) { !(l.state.import?.busy ?? true) && l.state.total == 30 }, "\(l.state.total) of 30")
    }
    /// R-19
    func test_R19_relaunch_reopensFolder_decisionsKept() {
        let f = Fixtures.batch("Holiday", 5)
        l.importFixture(f); l.go(2); l.key("r"); l.pause(0.15); l.key("r"); l.pause(0.3)
        let k0 = l.state.kept
        l.relaunch()
        // Native: the security-scoped bookmark reopens automatically. If not, Open must offer it.
        if l.state.total != 5 { XCTAssertTrue(l.exists("open.reopenFolder", timeout: 2), "folder not offered"); l.importFixture(f) }
        XCTAssertEqual(l.state.kept, k0)
    }
    /// R-85
    func test_R85_bigFolder() {
        l.importFixture(Fixtures.big(400)); XCTAssertEqual(l.state.total, 400)
    }

    // MARK: clumsy
    func test_monkey300RandomClicks() {
        l.startCulling(waitAll: false); l.pause(1.2)
        monkey(l, 300)
        calm(l); XCTAssertNil(l.alive()); l.go(2); XCTAssertEqual(l.state.step, "cull")
    }
    func test_keyboardMash400() {
        l.startCulling(waitAll: false); l.pause(1.2)
        for s in [2, 3, 4, 1] { l.go(s, settle: s == 3 ? 0.9 : 0.3); mash(l, 100) }
        calm(l); XCTAssertNil(l.alive()); l.go(2); XCTAssertEqual(l.state.step, "cull")
    }
    func test_undoFlood150() {
        l.startCulling(waitAll: false); l.pause(1.2); l.keepN(5)
        for s in [2, 3] { l.go(s, settle: s == 3 ? 0.9 : 0.3); for _ in 0..<150 { l.cmd("z") }; for _ in 0..<150 { l.key("z", [.command, .shift]) } }
        XCTAssertNil(l.alive())
    }
    /// R-45
    func test_R45_straightToEdit_nothingKept_explains() {
        l.importFixture(Fixtures.batch("NoKeep", 2)); l.go(3, settle: 1.2)
        XCTAssertTrue(l.exists("edit.empty")); l.click("edit.empty.goCull"); l.pause(0.6)
        XCTAssertEqual(l.state.step, "cull")
    }
}

// MARK: chaos helpers (shared with SoakTests)
func monkey(_ l: Lumina, _ n: Int) {
    let w = l.window.frame
    for _ in 0..<n {
        if Int.random(in: 0..<100) < 8 { l.go(Int.random(in: 1...4), settle: 0.25); continue }
        let p = l.window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: .random(in: 0..<w.width), dy: .random(in: 0..<w.height)))
        if Int.random(in: 0..<5) == 0 { p.doubleClick() } else { p.click() }
    }
}
func mash(_ l: Lumina, _ n: Int) {
    let keys = Array("abcdefghijklmnopqrstuvwxyz0123459 ,./\\[]=-'").map(String.init) + [XCUIKeyboardKey.return.rawValue, XCUIKeyboardKey.escape.rawValue, XCUIKeyboardKey.tab.rawValue, XCUIKeyboardKey.delete.rawValue, XCUIKeyboardKey.leftArrow.rawValue, XCUIKeyboardKey.rightArrow.rawValue, XCUIKeyboardKey.upArrow.rawValue, XCUIKeyboardKey.downArrow.rawValue, XCUIKeyboardKey.home.rawValue, XCUIKeyboardKey.end.rawValue, XCUIKeyboardKey.pageUp.rawValue, XCUIKeyboardKey.pageDown.rawValue]
    let dangerous: Set<String> = ["q", "w", "r", "l", "t", "n", "m", "h"] // ⌘Q quits, ⌘W closes, ⌘H hides, ⌘M minimises…: not app behaviour
    for _ in 0..<n {
        let k = keys.randomElement()!
        var m: XCUIElement.KeyModifierFlags = []
        if Int.random(in: 0..<100) < 18, !dangerous.contains(k) { m.insert(.command) }
        if Int.random(in: 0..<100) < 15 { m.insert(.shift) }
        if Int.random(in: 0..<100) < 6 { m.insert(.option) }
        l.key(k, m)
    }
}
func calm(_ l: Lumina) { for _ in 0..<4 { l.esc(); l.pause(0.08) }; l.command("{\"releaseAllKeys\":true}"); l.blurWindow(); l.pause(0.2) }
