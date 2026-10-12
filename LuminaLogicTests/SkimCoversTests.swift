import XCTest
@testable import Lumina

/// Skim's saved covers in the container (`SkimCovers`, STORAGE.md item 2): what the page sends comes back after a
/// relaunch, the sums are the files on disk, the cap takes the shoot opened longest ago and never the one being
/// written, a clear removes only its own folders, and nothing over the bounds is written. Foundation only.
final class SkimCoversTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("skim-covers-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func rec(_ k: String, bytes: Int = 2000) -> [String: String] {
        ["k": k, "meta": #"{"k":"\#(k)","ver":"v1-8","f":3,"dur":12.5,"facts":{"state":"ready"}}"#, "cover": Data(repeating: 0xFF, count: bytes).base64EncodedString()]
    }

    func testARecordComesBackAfterARelaunch() {
        XCTAssertEqual(SkimCovers(dir: dir).put(k: "lumina-skim:A-2", name: "A", n: 2, recs: [rec("C0001.MP4@2026-10-01T10:00:00#100"), rec("C0002.MP4@2026-10-01T10:01:00#200")]), .saved)
        let got = SkimCovers(dir: dir).get(["C0001.MP4@2026-10-01T10:00:00#100", "C0009.MP4@x#1"])
        XCTAssertEqual(Set(got.keys), ["C0001.MP4@2026-10-01T10:00:00#100"], "only what was saved")
        XCTAssertEqual(got["C0001.MP4@2026-10-01T10:00:00#100"]?["meta"], rec("C0001.MP4@2026-10-01T10:00:00#100")["meta"])
        XCTAssertEqual(Data(base64Encoded: got["C0001.MP4@2026-10-01T10:00:00#100"]?["cover"] ?? "")?.count, 2000)
    }

    func testTheSumsAreTheFilesOnDisk() {
        let c = SkimCovers(dir: dir)
        c.put(k: "a", name: "A", n: 3, recs: [rec("1", bytes: 3000), rec("2", bytes: 3000), rec("3", bytes: 3000)])
        c.put(k: "b", name: "B", n: 1, recs: [rec("4", bytes: 1000)])
        let st = c.stat(), a = st.shoots.first { $0.k == "a" }, b = st.shoots.first { $0.k == "b" }
        XCTAssertEqual(a?.n, 3); XCTAssertEqual(b?.n, 1)
        XCTAssertGreaterThanOrEqual(a?.bytes ?? 0, 9000); XCTAssertLessThan(a?.bytes ?? 0, 12000, "covers plus one small shoot.json")
        XCTAssertEqual(st.bytes, (a?.bytes ?? 0) + (b?.bytes ?? 0))
    }

    func testOverTheCapTheShootOpenedLongestAgoGoesNeverTheOneWritten() {
        let c = SkimCovers(dir: dir, cap: 25_000)
        XCTAssertEqual(c.put(k: "old", name: "Old", n: 1, recs: [rec("1", bytes: 10_000)], now: 1), .saved)
        XCTAssertEqual(c.put(k: "mid", name: "Mid", n: 1, recs: [rec("2", bytes: 10_000)], now: 2), .saved)
        XCTAssertEqual(Set(c.stat().shoots.map(\.k)), ["old", "mid"])
        XCTAssertEqual(c.put(k: "new", name: "New", n: 1, recs: [rec("3", bytes: 10_000)], now: 3), .saved)
        XCTAssertEqual(Set(c.stat().shoots.map(\.k)), ["mid", "new"], "the oldest went")
        // one shoot over the cap on its own stays: it is the one being written
        XCTAssertEqual(c.put(k: "big", name: "Big", n: 1, recs: [rec("4", bytes: 40_000)], now: 4), .saved)
        XCTAssertEqual(c.stat().shoots.map(\.k), ["big"])
    }

    func testTheEvictionOrderIsThePagesOwn() {
        let S = [SkimCovers.Held(k: "a", name: "", at: 3, bytes: 50, n: 1), .init(k: "b", name: "", at: 1, bytes: 40, n: 1),
                 .init(k: "cur", name: "", at: 0, bytes: 100, n: 1), .init(k: "c", name: "", at: 2, bytes: 30, n: 1)]
        XCTAssertEqual(SkimCovers.evictOrder(S, keep: "cur", bytes: 220, cap: 200), ["b"])
        XCTAssertEqual(SkimCovers.evictOrder(S, keep: "cur", bytes: 220, cap: 160), ["b", "c"])
        XCTAssertEqual(SkimCovers.evictOrder(S, keep: "cur", bytes: 220, cap: 0), ["b", "c", "a"])
        XCTAssertEqual(SkimCovers.evictOrder(S, keep: "cur", bytes: 150, cap: 200), [])
    }

    func testAClearRemovesOnlyItsOwnFolders() throws {
        let c = SkimCovers(dir: dir)
        c.put(k: "a", name: "A", n: 1, recs: [rec("1")]); c.put(k: "b", name: "B", n: 1, recs: [rec("2")])
        let beside = dir.deletingLastPathComponent().appendingPathComponent("beside-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: beside); defer { try? FileManager.default.removeItem(at: beside) }
        XCTAssertTrue(c.drop(["a", "../" + beside.lastPathComponent]))
        XCTAssertEqual(c.stat().shoots.map(\.k), ["b"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: beside.path), "a key is hashed into a folder name, never a path")
        XCTAssertEqual(c.get(["1"]), [:])
    }

    func testNothingOverTheBoundsIsWritten() {
        let c = SkimCovers(dir: dir)
        XCTAssertEqual(c.put(k: "", name: "", n: 0, recs: [rec("1")]), .refused)
        XCTAssertEqual(c.put(k: String(repeating: "k", count: 600), name: "", n: 0, recs: [rec("1")]), .refused)
        var big = rec("2"); big["meta"] = String(repeating: "m", count: SkimCovers.maxMeta + 1)
        var huge = rec("3"); huge["cover"] = Data(count: SkimCovers.maxCover + 1).base64EncodedString()
        var bad = rec("4"); bad["cover"] = "not base64!"
        XCTAssertEqual(c.put(k: "s", name: "S", n: 4, recs: [rec("1"), big, huge, bad]), .saved)
        XCTAssertEqual(Set(c.get(["1", "2", "3", "4"]).keys), ["1"], "only the record inside the bounds")
    }

    func testTouchMarksAShootOpenedWithoutClips() {
        let c = SkimCovers(dir: dir)
        XCTAssertTrue(c.touch(k: "s", name: "S", n: 40, now: 7))
        XCTAssertEqual(c.stat().shoots.first?.at, 7); XCTAssertEqual(c.stat().shoots.first?.n, 0)
    }
}
