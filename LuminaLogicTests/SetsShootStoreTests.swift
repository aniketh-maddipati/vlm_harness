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

    // MARK: Files this build can't read are kept aside (R8)

    private var shoots: URL { support.appendingPathComponent("shoots", isDirectory: true) }

    /// A damaged index is moved to index.damaged.json byte for byte before the next write, and the
    /// new index holds what was written.
    func testADamagedIndexIsKeptAsideBeforeItIsReplaced() throws {
        try fm.createDirectory(at: shoots, withIntermediateDirectories: true)
        let garbage = Data("[{\"id\": \"0123".utf8)
        try garbage.write(to: shoots.appendingPathComponent("index.json"))
        XCTAssertTrue(store.index().isEmpty)
        try store.upsert(shoot(good))
        XCTAssertEqual(try Data(contentsOf: shoots.appendingPathComponent("index.damaged.json")), garbage)
        XCTAssertEqual(store.index().map(\.id), [good])
    }

    /// One entry that no longer decodes costs that entry, not the Open screen's whole list; the
    /// original index is still kept aside on the next write, since that write drops the entry.
    func testOneBadEntryKeepsTheOthers() throws {
        try store.upsert(shoot(good))
        let url = shoots.appendingPathComponent("index.json")
        var list = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        list.append(["id": "fedcba9876543210", "title": 7])
        let mixed = try JSONSerialization.data(withJSONObject: list)
        try mixed.write(to: url)
        XCTAssertEqual(store.index().map(\.id), [good])
        try store.saveSummary(good, photos: 4, seen: 1, keepers: 1, last: nil)
        XCTAssertEqual(try Data(contentsOf: shoots.appendingPathComponent("index.damaged.json")), mixed)
        XCTAssertEqual(store.index().first?.keepers, 1)
    }

    func testAGoodIndexIsNeverSetAside() throws {
        try store.upsert(shoot(good))
        try store.upsert(shoot("fedcba9876543210"))
        try store.saveSummary(good, photos: 4, seen: 1, keepers: 1, last: nil)
        try store.remove("fedcba9876543210")
        XCTAssertFalse(fm.fileExists(atPath: shoots.appendingPathComponent("index.damaged.json").path))
    }

    /// A session that is not JSON (the page started over with nothing) is kept as
    /// session.damaged.json when the page's first save replaces it.
    func testADamagedSessionIsKeptAside() throws {
        let folder = shoots.appendingPathComponent(good, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let garbage = Data("{\"v\":2,\"marks\":{\"DSC0".utf8)
        try garbage.write(to: folder.appendingPathComponent("session.json"))
        try store.saveSession(good, Data("{\"v\":2}".utf8))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("session.damaged.json")), garbage)
        XCTAssertEqual(store.session(good), Data("{\"v\":2}".utf8))
    }

    /// A session from a newer format is kept once as session.v<N>.json; later saves in this
    /// build's format leave that copy alone, and saves in the same format never make one.
    func testANewerSessionFormatIsKeptAsideOnce() throws {
        let folder = shoots.appendingPathComponent(good, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newer = Data("{\"v\":3,\"marks\":{\"DSC00001.ARW\":\"keep\"}}".utf8)
        try newer.write(to: folder.appendingPathComponent("session.json"))
        try store.saveSession(good, Data("{\"v\":2,\"marks\":{}}".utf8))
        try store.saveSession(good, Data("{\"v\":2,\"marks\":{\"a\":1}}".utf8))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("session.v3.json")), newer)
        XCTAssertEqual(store.session(good), Data("{\"v\":2,\"marks\":{\"a\":1}}".utf8))
        let names = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["session.json", "session.v3.json"])
    }

    func testSessionVersionReadsV() {
        XCTAssertEqual(SetsShootStore.sessionVersion(Data("{\"v\":2}".utf8)), 2)
        XCTAssertEqual(SetsShootStore.sessionVersion(Data("{}".utf8)), 0)
        XCTAssertNil(SetsShootStore.sessionVersion(Data("[1]".utf8)))
        XCTAssertNil(SetsShootStore.sessionVersion(Data("{".utf8)))
    }
}
