import XCTest
@testable import Lumina

/// Shoot ids reach the store from the page (saveSession, workingFiles, removeShoot) and name a
/// folder under `shoots/`. Only what `SetsShootStore.id(for:)` makes is accepted: 16 lowercase hex
/// characters. Anything else must leave everything outside (and inside) the store alone.
final class SetsShootStoreTests: XCTestCase {
    private var sandbox: URL!
    private var support: URL!
    private var store: SetsShootStore!
    private let fm = FileManager.default
    private let good = "0123456789abcdef"

    /// "..", "../..", a path, empty, 15 and 17 characters, uppercase hex, non-hex, and a few that
    /// only look right (a trailing newline, a full-width digit, 16 dots).
    private let bad = ["..", "../..", "../victim", "0123456/89abcdef", "/0123456789abcde", "", "0123456789abcde", "0123456789abcdef0",
                       "0123456789ABCDEF", "0123456789abcdeg", "0123456789abcde\n", "0123456789abcde０", "../../../victim/x", "................"]

    /// The support folder sits three levels inside the test's own folder, so every traversal
    /// above stays in it: if the check ever regresses, the test fails without touching the
    /// machine's temporary folder.
    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("sets-shoots-\(UUID().uuidString)", isDirectory: true)
        support = sandbox.appendingPathComponent("a/b/support", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        store = SetsShootStore(supportDir: support)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: sandbox) }

    /// Every file and folder in the sandbox, with its bytes: what a refused call may not change.
    private func everything() -> [String: Data] {
        var out: [String: Data] = [:]
        for rel in (fm.enumerator(atPath: sandbox.path)?.allObjects as? [String]) ?? [] {
            out[rel] = (try? Data(contentsOf: sandbox.appendingPathComponent(rel))) ?? Data()
        }
        return out
    }

    private func shoot(_ id: String) -> SetsShootStore.Shoot {
        SetsShootStore.Shoot(id: id, title: "Shoot", path: "/tmp/shoot", volumeUUID: nil, photos: 3, firstCapture: "", opened: Date(timeIntervalSince1970: 1_700_000_000), bookmark: nil)
    }

    /// A folder next to `shoots/` holding files with the store's own names: what "../victim" names.
    private func makeVictim() throws -> URL {
        let victim = support.appendingPathComponent("victim", isDirectory: true)
        try fm.createDirectory(at: victim, withIntermediateDirectories: true)
        try Data("{\"mine\":true}".utf8).write(to: victim.appendingPathComponent("session.json"))
        var h = LookShootHeader(); h.decoderVersion = 9
        try h.encoded().write(to: victim.appendingPathComponent(LookShootHeader.fileName))
        try Data(repeating: 7, count: 4096).write(to: victim.appendingPathComponent("DSC00001.ARW"))
        return victim
    }

    // MARK: What an id is

    func testOnlySixteenLowercaseHexCharactersAreAnID() {
        XCTAssertTrue(SetsShootStore.isID(good))
        XCTAssertTrue(SetsShootStore.isID("ffffffffffffffff"))
        for id in bad { XCTAssertFalse(SetsShootStore.isID(id), "\(id.debugDescription) must not be an id") }
    }

    func testTheIDMadeForAFolderIsAccepted() {
        XCTAssertTrue(SetsShootStore.isID(SetsShootStore.id(for: support)))
    }

    // MARK: A valid id

    func testAValidIDRoundTripsASessionAndAHeader() throws {
        try store.upsert(shoot(good))
        try store.saveSession(good, Data("{\"k\":1}".utf8))
        XCTAssertEqual(store.session(good), Data("{\"k\":1}".utf8))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("shoots/\(good)/session.json").path))

        var h = LookShootHeader(); h.decoderVersion = 8
        try store.saveHeader(good, h)
        XCTAssertEqual(store.header(good).decoderVersion, 8)

        try store.saveSummary(good, photos: 12, seen: 5, keepers: 2, last: "DSC00012.ARW")
        XCTAssertEqual(store.index().first?.keepers, 2)
        XCTAssertGreaterThan(store.bytes(good), 0)

        try store.remove(good)
        XCTAssertNil(store.session(good))
        XCTAssertTrue(store.index().isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("shoots/\(good)").path))
    }

    // MARK: Refused ids

    func testReadersAnswerNothingForARefusedID() throws {
        _ = try makeVictim()
        try store.upsert(shoot(good))
        try store.saveSession(good, Data("{}".utf8))
        for id in bad {
            XCTAssertNil(store.session(id), "session(\(id.debugDescription))")
            XCTAssertEqual(store.header(id), LookShootHeader(), "header(\(id.debugDescription))")
            XCTAssertEqual(store.bytes(id), 0, "bytes(\(id.debugDescription))")
        }
    }

    func testWritersThrowForARefusedIDAndWriteNothing() throws {
        _ = try makeVictim()
        try store.upsert(shoot(good))
        try store.saveSession(good, Data("{}".utf8))
        let before = everything()
        for id in bad {
            XCTAssertThrowsError(try store.saveSession(id, Data("{\"evil\":1}".utf8)), "saveSession(\(id.debugDescription))")
            XCTAssertThrowsError(try store.saveHeader(id, LookShootHeader()), "saveHeader(\(id.debugDescription))")
            XCTAssertThrowsError(try store.saveSummary(id, photos: 1, seen: 1, keepers: 1, last: "x"), "saveSummary(\(id.debugDescription))")
            XCTAssertThrowsError(try store.remove(id), "remove(\(id.debugDescription))")
        }
        XCTAssertEqual(everything(), before, "a refused id must not add, change or remove a file")
    }

    /// T1: `remove("../victim")` used to delete the folder next to `shoots/`.
    func testRemoveWithATraversalLeavesTheSiblingFolder() throws {
        let victim = try makeVictim()
        try store.upsert(shoot(good))
        let before = everything()
        XCTAssertThrowsError(try store.remove("../victim"))
        XCTAssertTrue(fm.fileExists(atPath: victim.appendingPathComponent("DSC00001.ARW").path))
        XCTAssertEqual(everything(), before)
    }

    /// `remove("..")` named the support folder itself, `remove("")` the whole store.
    func testRemoveCannotTakeTheStoreOrItsParent() throws {
        try store.upsert(shoot(good))
        try store.saveSession(good, Data("{}".utf8))
        let before = everything()
        for id in ["..", "../..", ""] { XCTAssertThrowsError(try store.remove(id)) }
        XCTAssertEqual(everything(), before)
        XCTAssertEqual(store.index().map(\.id), [good])
    }

    /// A refused remove does not rewrite the index either: the file is the same file, not a copy
    /// with the same bytes.
    func testARefusedRemoveDoesNotRewriteTheIndex() throws {
        try store.upsert(shoot(good))
        let index = support.appendingPathComponent("shoots/index.json")
        let before = try fm.attributesOfItem(atPath: index.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(before)
        XCTAssertThrowsError(try store.remove("../victim"))
        XCTAssertEqual(try fm.attributesOfItem(atPath: index.path)[.systemFileNumber] as? NSNumber, before)
    }
}
