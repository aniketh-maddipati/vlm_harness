import XCTest
@testable import Lumina

/// Skim's saved shoots (`SkimStore`): what the page sends survives a new store (a relaunch), removals stick,
/// and nothing outside the page's keys or over the bounds is written. Foundation only.
final class SkimStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("skim-store-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testAnEntrySurvivesARelaunchAndARemovalSticks() {
        let key = "lumina-skim:SLOG-3 Footage-2", value = #"{"marks":{"F0001":"keep"},"name":"SLOG-3 Footage","n":2}"#
        XCTAssertEqual(SkimStore(dir: dir).all(), [:], "nothing yet")
        XCTAssertTrue(SkimStore(dir: dir).set(key, value))
        XCTAssertEqual(SkimStore(dir: dir).all(), [key: value], "a new store reads what the last one wrote")
        XCTAssertTrue(SkimStore(dir: dir).set("lumina-skim:A7M3-day1-50", "{}"))
        XCTAssertTrue(SkimStore(dir: dir).set(key, nil))
        XCTAssertEqual(Set(SkimStore(dir: dir).all().keys), ["lumina-skim:A7M3-day1-50"])
    }

    func testOnlyThePagesKeysAndSizesAreWritten() {
        let s = SkimStore(dir: dir)
        XCTAssertFalse(s.set("lumina-v4-toured", "1"), "Pick's keys are not Skim's")
        XCTAssertFalse(s.set("lumina-skim:" + String(repeating: "x", count: SkimStore.maxKey), "{}"))
        XCTAssertFalse(s.set("lumina-skim:big", String(repeating: "x", count: SkimStore.maxValue + 1)))
        XCTAssertFalse(s.set("lumina-skim:a\0b", "{}"))
        XCTAssertEqual(s.all(), [:], "nothing refused was written")
    }

    func testAMalformedFileReadsAsEmptyAndTheNextWriteReplacesIt() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("store.json"))
        XCTAssertEqual(SkimStore(dir: dir).all(), [:])
        XCTAssertTrue(SkimStore(dir: dir).set("lumina-skim:x-1", "{}"))
        XCTAssertEqual(SkimStore(dir: dir).all(), ["lumina-skim:x-1": "{}"])
    }
}
