import XCTest

/// Port of the Newbie Test "Soak": repeat chaos, watch for pile-up, leaks and slowdowns (R-90…R-93).
/// Rounds via env SOAK_ROUNDS (default 25). Run nightly or before a release, not on every PR.
final class SoakTests: LuminaTestCase {
    override class var limit: TimeInterval { 3600 }
    override class var long: Bool { true }
    func test_R90_R93_soak() {
        let rounds = Int(ProcessInfo.processInfo.environment["SOAK_ROUNDS"] ?? "25") ?? 25
        let l = Lumina().launch(); l.startCulling(waitAll: false); l.pause(1.2)
        let mix = Fixtures.messy
        var nodes: [Int] = [], mem: [Double] = []
        for r in 1...rounds {
            l.importFixture(mix)                      // duplicates after round 1, so memory should level off
            monkey(l, 80); calm(l); mash(l, 80); calm(l)
            for _ in 0..<15 { l.resize(.random(in: 360...1760), .random(in: 360...1060), settle: 0.02) }
            l.resize(1100, 760)
            for s in [2, 3, 4] { l.go(s, settle: s == 3 ? 0.7 : 0.25) }
            l.go(1, settle: 0.3); if l.exists("open.card") { l.click("open.card") }; l.go(2, settle: 0.5)
            l.pause(2.5)                              // idle so the heap settles before measuring
            XCTAssertNil(l.alive(), "R-90 round \(r)")
            nodes.append(l.app.descendants(matching: .any).count)
            mem.append(Double(l.value("debug.memoryMB")) ?? 0)   // app reports phys_footprint in UI-test builds
        }
        let k = max(1, min(5, rounds / 3))
        func med(_ a: ArraySlice<Double>) -> Double { let s = a.sorted(); return s[s.count / 2] }
        let n0 = med(nodes.dropFirst().prefix(k).map(Double.init)[...]), n1 = med(nodes.suffix(k).map(Double.init)[...])
        let m0 = med(mem.dropFirst().prefix(k)[...]), m1 = med(mem.suffix(k)[...])
        XCTAssertLessThan(n1 / n0, 1.6, "R-91 elements \(n0) → \(n1)")
        XCTAssertLessThan(m1 / max(1, m0), 1.5, "R-92 memory \(m0) → \(m1) MB")
        l.importFixture(Fixtures.big(min(1200, 200 * ((rounds + 4) / 5))))
        XCTAssertNil(l.alive(), "R-93")
        assertNoErrors(l)
    }
}
