import XCTest
@testable import Lumina

/// The page's stored keys (tour seen, names, seen-before): only the named keys, each under its
/// cap, kept across "launches" (a new store on the same folder), and a damaged file reads as empty.
final class SetsPageStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("page-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testAllowedKeysRoundTripAcrossStores() {
        XCTAssertTrue(SetsPageStore(supportDir: dir).set("lumina-v4-toured", "1"))
        XCTAssertTrue(SetsPageStore(supportDir: dir).set("lumina-v4-names", #"{"a|3":"Wedding"}"#))
        XCTAssertEqual(SetsPageStore(supportDir: dir).all(), ["lumina-v4-toured": "1", "lumina-v4-names": #"{"a|3":"Wedding"}"#])
    }

    func testUnknownKeyAndOversizeValueAreRefusedAndChangeNothing() {
        let store = SetsPageStore(supportDir: dir)
        XCTAssertTrue(store.set("lumina-v4-toured", "1"))
        XCTAssertFalse(store.set("lumina-prefs", "{}"))
        XCTAssertFalse(store.set("anything", "x"))
        XCTAssertFalse(store.set("lumina-v4-toured", String(repeating: "1", count: 17)))
        XCTAssertEqual(store.all(), ["lumina-v4-toured": "1"])
    }

    func testNilRemoves() {
        let store = SetsPageStore(supportDir: dir)
        store.set("lumina-phone-kind", "android")
        XCTAssertTrue(store.set("lumina-phone-kind", nil))
        XCTAssertEqual(store.all(), [:])
    }

    func testDamagedFileReadsAsEmptyAndIsReplacedByTheNextSet() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("page-store.json"))
        let store = SetsPageStore(supportDir: dir)
        XCTAssertEqual(store.all(), [:])
        XCTAssertTrue(store.set("lumina-v4-pre-ok", "1"))
        XCTAssertEqual(store.all(), ["lumina-v4-pre-ok": "1"])
    }

    func testAKeyDroppedFromTheListIsNotHandedBack() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"lumina-v4-toured":"1","old-key":"x"}"#.utf8).write(to: dir.appendingPathComponent("page-store.json"))
        XCTAssertEqual(SetsPageStore(supportDir: dir).all(), ["lumina-v4-toured": "1"])
    }
}
