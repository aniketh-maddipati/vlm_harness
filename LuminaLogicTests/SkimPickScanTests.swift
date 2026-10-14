import XCTest
@testable import Lumina

/// Skim's pick in the app (`SkimPickScan`, LOCAL-CHANGES 280): a whole drive is caught before WebKit lists it. The
/// count stops at the file limit, the clip limit is the page's, and the first clips by path come with their sidecars.
/// Foundation only.
final class SkimPickScanTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-pick-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func make(_ rel: String, _ bytes: Int = 10) throws {
        let u = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: u)
    }

    func testTheLimitsAreThePagesOwn() {
        XCTAssertEqual(SkimPickScan.clips, 1500); XCTAssertEqual(SkimPickScan.files, 50_000)
    }

    func testAClipFolderUnderTheLimitPassesWithItsCountAndSize() throws {
        try make("CARD/CLIP/C0001.MP4", 100); try make("CARD/CLIP/C0001M01.XML"); try make("CARD/CLIP/C0002.MP4", 200); try make("CARD/notes.txt")
        let r = SkimPickScan.scan([tmp.appendingPathComponent("CARD")])
        XCTAssertFalse(r.tooBig); XCTAssertEqual(r.name, "CARD"); XCTAssertEqual(r.clips, 2); XCTAssertEqual(r.bytes, 300); XCTAssertEqual(r.files, 4); XCTAssertFalse(r.cut)
    }

    func testPastTheClipLimitTheFirstByPathComeWithTheirSidecars() throws {
        for i in (1...7).reversed() { try make(String(format: "T7/day%d/C%04d.MP4", i % 2, i)) }
        try make("T7/day1/C0001M01.XML"); try make("T7/day0/C0001M01.XML"); try make("T7/._C0009.MP4")
        let r = SkimPickScan.scan([tmp.appendingPathComponent("T7")], maxClips: 3)
        XCTAssertEqual(r.clips, 7); XCTAssertTrue(r.clips > 3 && !r.cut)
        XCTAssertEqual(r.first.map { $0.deletingLastPathComponent().lastPathComponent + "/" + $0.lastPathComponent },
                       ["day0/C0002.MP4", "day0/C0004.MP4", "day0/C0006.MP4"], "by path, and a sidecar only beside its own clip")
        let s = SkimPickScan.scan([tmp.appendingPathComponent("T7")], maxClips: 4)
        XCTAssertEqual(s.first.map(\.lastPathComponent), ["C0002.MP4", "C0004.MP4", "C0006.MP4", "C0001.MP4", "C0001M01.XML"])
    }

    func testAFirehoseStopsAtTheFileLimit() throws {
        for i in 0..<30 { try make("Disk/junk/\(i).txt") }
        try make("Disk/a/C0001.MP4")
        var calls = 0
        let r = SkimPickScan.scan([tmp.appendingPathComponent("Disk")], maxFiles: 12, progress: { _, _ in calls += 1 })
        XCTAssertTrue(r.cut); XCTAssertTrue(r.tooBig); XCTAssertEqual(r.files, 12)
        XCTAssertEqual(r.json["cut"] as? Int, 12); XCTAssertEqual(r.json["name"] as? String, "Disk")
        XCTAssertEqual(calls, 0, "progress every 2,000 files")
    }

    func testANewerPickStopsTheCount() throws {
        for i in 0..<5 { try make("D/\(i).MP4") }
        let r = SkimPickScan.scan([tmp.appendingPathComponent("D")], stop: { true })
        XCTAssertTrue(r.cut); XCTAssertEqual(r.files, 0)
    }

    func testLooseClipsAreTheseClips() throws {
        try make("a/C0001.MP4"); try make("a/C0002.MP4")
        let r = SkimPickScan.scan([tmp.appendingPathComponent("a/C0001.MP4"), tmp.appendingPathComponent("a/C0002.MP4")])
        XCTAssertEqual(r.name, "These clips"); XCTAssertEqual(r.clips, 2); XCTAssertFalse(r.tooBig)
    }

    func testClipsAndSidecarsAreReadAsThePageReadsThem() {
        XCTAssertTrue(SkimPickScan.isClip("C0001.MP4")); XCTAssertTrue(SkimPickScan.isClip("a.mxf")); XCTAssertFalse(SkimPickScan.isClip("._C0001.MP4")); XCTAssertFalse(SkimPickScan.isClip("C0001M01.XML"))
        XCTAssertEqual(SkimPickScan.sidecarStem("C0001M01.XML"), "C0001"); XCTAssertEqual(SkimPickScan.sidecarStem("clip.xml"), "CLIP"); XCTAssertNil(SkimPickScan.sidecarStem("C0001.MP4"))
    }

    func testEachClipAndSidecarCarriesItsPlaceAsTheFolderInputWouldGiveIt() throws {
        try make("CARD/PRIVATE/M4ROOT/CLIP/C0001.MP4"); try make("CARD/PRIVATE/M4ROOT/CLIP/C0001M01.XML"); try make("CARD/junk.txt")
        let r = SkimPickScan.scan([tmp.appendingPathComponent("CARD")])
        XCTAssertEqual(r.rels, ["CARD/PRIVATE/M4ROOT/CLIP/C0001.MP4", "CARD/PRIVATE/M4ROOT/CLIP/C0001M01.XML"])
        try make("loose/C0009.MP4")
        XCTAssertEqual(SkimPickScan.scan([tmp.appendingPathComponent("loose/C0009.MP4")]).rels, ["C0009.MP4"], "a file picked by itself: its name")
    }
}
