import XCTest

/// Port of the Load suites (stress "Load" + Controls Test "Load", demo×13 and Unsplash 5,000).
/// Uses XCTest metrics so results land in Xcode's performance baselines.
/// The app emits os_signpost intervals (subsystem "com.lumina", category "perf") named
/// "PhotoSwitch", "CullKey", "Save", "Import"; tests measure those, not wall-clock key typing.
final class LoadTests: XCTestCase {
    var l: Lumina!
    override func tearDown() { if let l { assertNoErrors(l); l.app.terminate() } }
    func signpost(_ name: String) -> XCTOSSignpostMetric { XCTOSSignpostMetric(subsystem: "com.lumina", category: "perf", name: name) }
    var opts: XCTMeasureOptions { let o = XCTMeasureOptions(); o.iterationCount = 3; return o }

    /// R-80
    func test_R80_cullKeysWhileCopying() {
        l = Lumina(card: "demo:1500").launch(); l.enter()
        XCTAssertTrue(l.waitCopied(30, timeout: 8))
        measure(metrics: [signpost("CullKey")], options: opts) { for i in 0..<60 { if i % 4 == 3 { l.key("r") } else { l.right() } } }
    }

    /// R-82
    func test_R82_decideEveryPhoto_5000() {
        l = Lumina(card: "unsplash:5000", copyRate: 400).launch(); l.startCulling()
        for _ in 0..<(l.state.total + 5) { l.left() }
        let t0 = Date()
        for i in 0..<l.state.total { l.key(i % 2 == 0 ? "r" : "x") }
        XCTAssertTrue(l.waitUntil(30) { l.state.undecided == 0 }, "\(l.state.undecided) left undecided")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 60)
    }

    /// R-81 (117 and 5,000)
    func test_R81_photoSwitchInEdit_demo() { switchBench(card: "demo117", limitMs: 50) }
    func test_R81_photoSwitchInEdit_5000() { switchBench(card: "unsplash:5000", limitMs: 60) }
    private func switchBench(card: String, limitMs: Double) {
        l = Lumina(card: card, copyRate: 400).launch(); l.startCulling()
        for _ in 0..<min(l.state.total, 2500) { l.key("r") }
        l.go(3, settle: 2)
        measure(metrics: [signpost("PhotoSwitch"), XCTMemoryMetric(application: l.app)], options: opts) {
            for i in 0..<100 { if i % 5 == 4 { l.left() } else { l.right() } }
        }
        // Baseline limit. Set it in Xcode's baseline editor to limitMs at the 95th; CI fails on regression.
        _ = limitMs
    }

    /// R-86
    func test_R86_edit300Photos_storageSmall() {
        l = Lumina(card: "demo:1500", copyRate: 400).launch(); l.startCulling()
        for _ in 0..<1500 { l.key("r") }
        l.go(3, settle: 2)
        for _ in 0..<300 { l.key("."); l.enter() }
        l.pause(1.2)
        XCTAssertGreaterThan(l.state.looksCount, 250)
        XCTAssertLessThan(l.state.lookBytes, 2 * 1024 * 1024, "R-86 edits use \(l.state.lookBytes / 1024) KB")
    }

    /// R-83
    func test_R83_saveBigShoot() {
        l = Lumina(card: "unsplash:5000", copyRate: 400).launch(); l.startCulling()
        for i in 0..<l.state.total { l.key(i % 2 == 0 ? "r" : "x") }
        l.go(4, settle: 1)
        measure(metrics: [signpost("Save")], options: { let o = XCTMeasureOptions(); o.iterationCount = 1; return o }()) { l.click("save.button") }
        let s1 = l.state.saved; l.cmd("s"); l.pause(0.3)
        XCTAssertEqual(l.state.saved?.sig, s1?.sig)
    }

    /// R-84
    func test_R84_relaunchBigShoot() {
        l = Lumina(card: "unsplash:5000", copyRate: 400).launch(); l.startCulling()
        for i in 0..<1000 { l.key(i % 2 == 0 ? "r" : "x") }
        let k0 = l.state.keep
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: opts) { l.app.terminate(); l.app.launch() }
        XCTAssertEqual(l.state.keep, k0)
    }

    /// R-85
    func test_R85_import400PhotoFolder() {
        let big = Fixtures.big(400)
        l = Lumina().launch()
        l.command("{\"drop\":[\"\(big.path)\"]}")
        var ts: [Double] = []
        while l.state.import?.busy ?? true { let t = Date(); l.right(); _ = l.state; ts.append(Date().timeIntervalSince(t) * 1000); l.pause(0.06); if ts.count > 1500 { break } }
        XCTAssertEqual(l.state.total, 400)
        XCTAssertLessThan(percentile(ts, 0.95), 150 + 60, "keys slow while checking (includes XCUITest round-trip)")
    }
}
