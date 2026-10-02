import XCTest
@testable import Lumina

/// Release task R1e: sessions made before the app was sandboxed are brought over, never lost.
/// The earlier build's store (~/Library/Application Support/Lumina) is built here in a temporary
/// folder, in the format that build wrote, and imported into a second, empty store. Nothing in
/// these tests reads the real one.
final class SetsShootImportTests: XCTestCase {
    private var sandbox: URL!
    private var oldSupport: URL!
    private var newSupport: URL!
    private var store: SetsShootStore!
    private let fm = FileManager.default

    private let a = "aaaaaaaaaaaaaaa1", b = "bbbbbbbbbbbbbbb2", c = "ccccccccccccccc3"
    private let sessionA = Data(#"{"keep":{"100MSDCF/DSC00001.ARW":1,"100MSDCF/DSC00007.ARW":1},"seen":{"r1":1},"look":{"100MSDCF/DSC00001.ARW":"ev:+0.70 con:+12"}}"#.utf8)
    private let sessionB = Data("{\n  \"keep\": { \"DSC01000.ARW\": 1 },\n  \"flag\": { \"DSC01002.ARW\": 1 }\n}\n".utf8)
    private let sessionC = Data(#"{"keep":{},"note":"café · 写真"}"#.utf8)

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("sets-import-\(UUID().uuidString)", isDirectory: true)
        oldSupport = sandbox.appendingPathComponent("home/Library/Application Support/Lumina", isDirectory: true)
        newSupport = sandbox.appendingPathComponent("container/Data/Library/Application Support/Lumina", isDirectory: true)
        try fm.createDirectory(at: oldSupport.appendingPathComponent("shoots", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: newSupport, withIntermediateDirectories: true)
        store = SetsShootStore(supportDir: newSupport)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: sandbox) }

    // MARK: The earlier store, as the earlier build wrote it

    private var oldShoots: URL { oldSupport.appendingPathComponent("shoots", isDirectory: true) }

    private func put(_ data: Data, _ rel: String, in root: URL? = nil) throws {
        let url = (root ?? oldSupport).appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// One index entry in the on-disk format: ISO-8601 date, the bookmark as base64 (arbitrary
    /// bytes here: a bookmark made outside the sandbox is useless inside it anyway).
    private func entry(_ id: String, title: String, opened: String, extra: String = "") -> String {
        """
          {
            "bookmark" : "\(Data([0x62, 0x6f, 0x6f, 0x6b, 0x00, 0xff, 0x10, 0x20]).base64EncodedString())",
            "firstCapture" : "2026:05:17 09:41:00",
            "id" : "\(id)",
            "opened" : "\(opened)",
            "path" : "/Users/someone/Pictures/\(title)",
            "photos" : 412,
            "title" : "\(title)",
            "volumeUUID" : "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"\(extra)
          }
        """
    }

    private func putIndex(_ entries: [String]) throws {
        try put(Data(("[\n" + entries.joined(separator: ",\n") + "\n]").utf8), "shoots/index.json")
    }

    private var headerBytes: Data {
        Data(#"{"bodies":{},"decoderVersion":8,"pinnedOn":"15.6","v":1}"#.utf8)
    }

    /// Three shoots with sessions, one of them with a header; plus what an earlier build left
    /// beside them (an export journal, the legacy bookmarks folder).
    private func makeOldStore() throws {
        try putIndex([
            entry(b, title: "mehendi", opened: "2026-09-20T18:00:00Z", extra: ",\n    \"keepers\" : 31,\n    \"last\" : \"DSC01002.ARW\",\n    \"seen\" : 120"),
            entry(a, title: "death-valley", opened: "2026-09-28T07:30:00Z", extra: ",\n    \"place\" : \"\(c)\""),
            entry(c, title: "studio", opened: "2026-08-01T12:00:00Z"),
        ])
        try put(sessionA, "shoots/\(a)/session.json")
        try put(headerBytes, "shoots/\(a)/Lumina.json")
        try put(sessionB, "shoots/\(b)/session.json")
        try put(sessionC, "shoots/\(c)/session.json")
        try put(Data(#"{"id":"e1","planned":[],"done":[]}"#.utf8), "exports/e1.json")
        try put(Data([1, 2, 3]), "bookmarks/\(a).bookmark")
    }

    /// Every file under `root` with its bytes (a link: where it points), and every folder.
    private func tree(_ root: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        for rel in (fm.enumerator(atPath: root.path)?.allObjects as? [String]) ?? [] {
            let path = root.appendingPathComponent(rel).path
            if let to = try? fm.destinationOfSymbolicLink(atPath: path) { out[rel] = Data(("link → " + to).utf8) }
            else { out[rel] = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data("folder".utf8) }
        }
        return out
    }

    private func newFile(_ rel: String) -> Data? { try? Data(contentsOf: newSupport.appendingPathComponent(rel)) }

    // MARK: The import

    func testSessionsAndHeadersComeOverByteForByteAndTheIndexWithoutBookmarks() throws {
        try makeOldStore()
        let before = tree(oldSupport)

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.sessions, 3)
        XCTAssertEqual(r.headers, 1)
        XCTAssertEqual(r.recents, 3)
        XCTAssertEqual(r.alreadyHere, 0)
        XCTAssertEqual(r.keptNewer, 0)
        XCTAssertEqual(r.skipped, [:])
        XCTAssertTrue(r.changed)
        XCTAssertEqual(r.statusLine, "3 sessions brought over · open a folder to continue it")

        XCTAssertEqual(newFile("shoots/\(a)/session.json"), sessionA)
        XCTAssertEqual(newFile("shoots/\(b)/session.json"), sessionB)
        XCTAssertEqual(newFile("shoots/\(c)/session.json"), sessionC)
        XCTAssertEqual(newFile("shoots/\(a)/Lumina.json"), headerBytes)
        XCTAssertEqual(store.session(a), sessionA)
        XCTAssertEqual(store.header(a).decoderVersion, 8)
        XCTAssertNil(newFile("shoots/\(b)/Lumina.json"))

        let index = store.index()
        XCTAssertEqual(index.map(\.id), [a, b, c], "newest first")
        XCTAssertTrue(index.allSatisfy { $0.bookmark == nil }, "a bookmark made outside the sandbox is not brought over")
        XCTAssertEqual(index[0].title, "death-valley")
        XCTAssertEqual(index[0].path, "/Users/someone/Pictures/death-valley")
        XCTAssertEqual(index[0].volumeUUID, "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")
        XCTAssertEqual(index[0].photos, 412)
        XCTAssertEqual(index[0].firstCapture, "2026:05:17 09:41:00")
        XCTAssertEqual(index[0].place, c, "where a moved folder is now comes along")
        XCTAssertEqual(index[0].opened, ISO8601DateFormatter().date(from: "2026-09-28T07:30:00Z"))
        XCTAssertEqual(index[1].seen, 120)
        XCTAssertEqual(index[1].keepers, 31)
        XCTAssertEqual(index[1].last, "DSC01002.ARW")
        XCTAssertFalse(String(decoding: newFile("shoots/index.json") ?? Data(), as: UTF8.self).contains("bookmark"))

        // Not the export journals, not the legacy bookmarks; and the old folder is as it was.
        XCTAssertFalse(fm.fileExists(atPath: newSupport.appendingPathComponent("exports").path))
        XCTAssertFalse(fm.fileExists(atPath: newSupport.appendingPathComponent("bookmarks").path))
        XCTAssertEqual(Set(tree(newSupport).keys), ["shoots", "shoots/index.json", "shoots/\(a)", "shoots/\(a)/session.json", "shoots/\(a)/Lumina.json",
                                                    "shoots/\(b)", "shoots/\(b)/session.json", "shoots/\(c)", "shoots/\(c)/session.json"])
        XCTAssertEqual(tree(oldSupport), before, "the earlier store is only read")
    }

    /// The same folder opened again gets the same id, so the session is simply there.
    func testAnImportedSessionIsFoundByTheFoldersID() throws {
        let folder = sandbox.appendingPathComponent("Pictures/shoot", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = SetsShootStore.id(for: folder)
        try putIndex([entry(id, title: "shoot", opened: "2026-09-28T07:30:00Z")])
        try put(sessionA, "shoots/\(id)/session.json")

        _ = try store.importStore(from: oldSupport)

        XCTAssertEqual(store.shootID(at: SetsShootStore.id(for: folder)), id)
        XCTAssertEqual(store.session(store.shootID(at: SetsShootStore.id(for: folder))), sessionA)
    }

    func testASecondImportChangesNothing() throws {
        try makeOldStore()
        _ = try store.importStore(from: oldSupport)
        let before = tree(newSupport)
        let index = newSupport.appendingPathComponent("shoots/index.json")
        let file = try fm.attributesOfItem(atPath: index.path)[.systemFileNumber] as? NSNumber
        let old = tree(oldSupport)

        let r = try store.importStore(from: oldSupport)

        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.sessions, 0)
        XCTAssertEqual(r.headers, 0)
        XCTAssertEqual(r.recents, 0)
        XCTAssertEqual(r.alreadyHere, 3)
        XCTAssertEqual(r.keptNewer, 0)
        XCTAssertEqual(r.statusLine, "earlier sessions are already here")
        XCTAssertEqual(tree(newSupport), before)
        XCTAssertEqual(try fm.attributesOfItem(atPath: index.path)[.systemFileNumber] as? NSNumber, file, "the index is not rewritten")
        XCTAssertEqual(tree(oldSupport), old)
    }

    // MARK: A shoot in both stores: this store wins

    func testAShootInBothStoresKeepsWhatThisStoreHas() throws {
        try makeOldStore()
        // Since the update: shoot a was opened and culled further here, with a bookmark and a new pin.
        let mine = Data(#"{"keep":{"100MSDCF/DSC00001.ARW":1,"100MSDCF/DSC00099.ARW":1}}"#.utf8)
        let bookmark = Data([9, 9, 9])
        try store.upsert(SetsShootStore.Shoot(id: a, title: "death-valley (here)", path: "/Volumes/T7/death-valley", volumeUUID: "V", photos: 500, firstCapture: "",
                                              opened: Date(timeIntervalSince1970: 1_800_000_000), bookmark: bookmark, seen: 7, keepers: 2, last: "DSC00099.ARW"))
        try store.saveSession(a, mine)
        var h = LookShootHeader(); h.decoderVersion = 9
        try store.saveHeader(a, h)
        let myHeader = newFile("shoots/\(a)/Lumina.json")

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.sessions, 2)
        XCTAssertEqual(r.headers, 0)
        XCTAssertEqual(r.recents, 2)
        XCTAssertEqual(r.keptNewer, 1)
        XCTAssertEqual(r.alreadyHere, 0)
        XCTAssertEqual(r.statusLine, "2 sessions brought over · open a folder to continue it · 1 kept as it is here")
        XCTAssertEqual(store.session(a), mine, "work done since is never replaced")
        XCTAssertEqual(newFile("shoots/\(a)/Lumina.json"), myHeader)
        XCTAssertEqual(store.header(a).decoderVersion, 9)
        let entry = try XCTUnwrap(store.index().first { $0.id == a })
        XCTAssertEqual(entry.bookmark, bookmark)
        XCTAssertEqual(entry.title, "death-valley (here)")
        XCTAssertEqual(entry.path, "/Volumes/T7/death-valley")
        XCTAssertEqual(entry.keepers, 2)
        XCTAssertNil(entry.place)
        XCTAssertEqual(store.index().map(\.id), [a, b, c])
        XCTAssertEqual(store.session(b), sessionB)
    }

    /// Opened here but nothing decided yet (a header and an index entry, no session): the earlier
    /// session comes, the header and the entry that are here stay.
    func testAShootOpenedHereWithoutASessionGetsTheEarlierSession() throws {
        try makeOldStore()
        try store.upsert(SetsShootStore.Shoot(id: a, title: "here", path: "/p", volumeUUID: nil, photos: 1, firstCapture: "", opened: Date(timeIntervalSince1970: 1_800_000_000), bookmark: Data([1])))
        var h = LookShootHeader(); h.decoderVersion = 9
        try store.saveHeader(a, h)

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.sessions, 3)
        XCTAssertEqual(r.headers, 0)
        XCTAssertEqual(r.recents, 2)
        XCTAssertEqual(store.session(a), sessionA)
        XCTAssertEqual(store.header(a).decoderVersion, 9)
        XCTAssertEqual(store.index().first { $0.id == a }?.bookmark, Data([1]))
    }

    // MARK: Skipped, and counted

    func testInvalidIDsLinksOversizedAndUnreadableSessionsAreSkipped() throws {
        try putIndex([entry(a, title: "good", opened: "2026-09-28T07:30:00Z")])
        try put(sessionA, "shoots/\(a)/session.json")
        // Not ids.
        try put(sessionB, "shoots/ABCDEF0123456789/session.json")
        try put(sessionB, "shoots/0123456789abcdef0/session.json")
        try put(sessionB, "shoots/notes/session.json")
        try put(Data("x".utf8), "shoots/stray.json")
        // Ignored without a count: Finder's file and a temp file an interrupted write left.
        try put(Data(), "shoots/.DS_Store")
        try put(Data("{".utf8), "shoots/.index.json.lumina-tmp-1a2b3c4d")
        // A shoot folder that is a link to a folder outside the store.
        let outside = sandbox.appendingPathComponent("elsewhere/secret", isDirectory: true)
        try put(Data(#"{"keep":{"stolen":1}}"#.utf8), "session.json", in: outside)
        try fm.createSymbolicLink(at: oldShoots.appendingPathComponent("1111111111111111"), withDestinationURL: outside)
        // A session that is a link.
        try fm.createDirectory(at: oldShoots.appendingPathComponent("2222222222222222"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: oldShoots.appendingPathComponent("2222222222222222/session.json"), withDestinationURL: outside.appendingPathComponent("session.json"))
        // Over the cap by one byte, and still a JSON object.
        try put(Data("{\"k\":\"".utf8) + Data(repeating: 0x61, count: SetsShootStore.importSessionBytes - 8 + 1) + Data("\"}".utf8), "shoots/3333333333333333/session.json")
        // Not JSON, JSON that is not an object, not UTF-8.
        try put(Data("keep everything".utf8), "shoots/4444444444444444/session.json")
        try put(Data("[1,2,3]".utf8), "shoots/5555555555555555/session.json")
        try put(Data([0xff, 0xfe, 0x7b, 0x00, 0x7d, 0x00]), "shoots/6666666666666666/session.json")
        // Nothing decided there; and a plain file where a shoot folder should be.
        try put(headerBytes, "shoots/7777777777777777/Lumina.json")
        try put(Data("{}".utf8), "shoots/8888888888888888")
        // A good session whose header does not decode, and one whose header is a link.
        try put(sessionC, "shoots/9999999999999999/session.json")
        try put(Data("not a header".utf8), "shoots/9999999999999999/Lumina.json")
        try put(sessionC, "shoots/aaaaaaaaaaaaaaa0/session.json")
        try put(headerBytes, "Lumina.json", in: outside)
        try fm.createSymbolicLink(at: oldShoots.appendingPathComponent("aaaaaaaaaaaaaaa0/Lumina.json"), withDestinationURL: outside.appendingPathComponent("Lumina.json"))

        XCTAssertEqual((try fm.attributesOfItem(atPath: oldShoots.appendingPathComponent("3333333333333333/session.json").path)[.size] as? NSNumber)?.intValue,
                       SetsShootStore.importSessionBytes + 1)
        let old = tree(oldSupport), elsewhere = tree(outside)

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.sessions, 3)
        XCTAssertEqual(r.headers, 0)
        XCTAssertEqual(r.recents, 1)
        XCTAssertEqual(r.skipped, [.notAnID: 4, .link: 2, .tooBig: 1, .unreadable: 3, .noSession: 2, .header: 2])
        XCTAssertEqual(r.skippedTotal, 14)
        XCTAssertEqual(r.statusLine, "3 sessions brought over · open a folder to continue it · 14 skipped")

        // Only the good ones are here, and nothing was written anywhere else.
        XCTAssertEqual(Set(tree(newSupport).keys), ["shoots", "shoots/index.json", "shoots/\(a)", "shoots/\(a)/session.json",
                                                    "shoots/9999999999999999", "shoots/9999999999999999/session.json",
                                                    "shoots/aaaaaaaaaaaaaaa0", "shoots/aaaaaaaaaaaaaaa0/session.json"])
        XCTAssertEqual(store.session("9999999999999999"), sessionC)
        XCTAssertEqual(tree(oldSupport), old)
        XCTAssertEqual(tree(outside), elsewhere)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: sandbox.path)), ["home", "container", "elsewhere"])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: sandbox.appendingPathComponent("container/Data/Library/Application Support").path), ["Lumina"])
    }

    /// A session of exactly the cap comes over.
    func testASessionAtTheCapComesOver() throws {
        try putIndex([])
        let big = Data("{\"k\":\"".utf8) + Data(repeating: 0x61, count: SetsShootStore.importSessionBytes - 8) + Data("\"}".utf8)
        XCTAssertEqual(big.count, SetsShootStore.importSessionBytes)
        try put(big, "shoots/\(a)/session.json")
        let r = try store.importStore(from: oldSupport)
        XCTAssertEqual(r.sessions, 1)
        XCTAssertEqual(r.skipped, [:])
        XCTAssertEqual(store.session(a), big)
        XCTAssertEqual(r.statusLine, "1 session brought over · open its folder to continue it")
    }

    /// The sessions are what matters: they come over even when the index is damaged. Opening the
    /// folder finds the session by its id; only the recents are missing.
    func testACorruptIndexIsSkippedAndTheSessionsStillCome() throws {
        try makeOldStore()
        try put(Data("[{\"id\": \"aaaaaaaaaaaaaaa1\", \"title\": ".utf8), "shoots/index.json")
        let old = tree(oldSupport)

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.sessions, 3)
        XCTAssertEqual(r.headers, 1)
        XCTAssertEqual(r.recents, 0)
        XCTAssertEqual(r.skipped, [.index: 1])
        XCTAssertNil(newFile("shoots/index.json"), "no index is made from a damaged one")
        XCTAssertTrue(store.index().isEmpty)
        XCTAssertEqual(store.session(b), sessionB)
        XCTAssertEqual(tree(oldSupport), old)

        let again = try store.importStore(from: oldSupport)
        XCTAssertFalse(again.changed)
        XCTAssertEqual(again.alreadyHere, 3)
    }

    func testAnIndexThatIsNotAListIsSkipped() throws {
        try put(Data(#"{"shoots":[]}"#.utf8), "shoots/index.json")
        try put(sessionA, "shoots/\(a)/session.json")
        let r = try store.importStore(from: oldSupport)
        XCTAssertEqual(r.sessions, 1)
        XCTAssertEqual(r.skipped, [.index: 1])
    }

    // MARK: Index entries

    /// The index as 4421a7c (the last build before the sandbox work) wrote it: no `place`, and the
    /// summary fields only once a session was saved; `volumeUUID` and `bookmark` absent when nil.
    func testAnIndexInThe4421a7cFormatDecodes() throws {
        try put(Data("""
        [
          {
            "bookmark" : "Ym9va21hcmsAAQID",
            "firstCapture" : "2026:07:04 18:22:10",
            "id" : "\(a)",
            "keepers" : 12,
            "last" : "DSC04410.ARW",
            "opened" : "2026-09-30T21:14:03Z",
            "path" : "/Volumes/Untitled/DCIM",
            "photos" : 3012,
            "seen" : 88,
            "title" : "SONY-A7M4",
            "volumeUUID" : "5D2C1A3B-0000-4111-8222-333344445555"
          },
          {
            "firstCapture" : "",
            "id" : "\(b)",
            "opened" : "2026-09-12T08:00:00Z",
            "path" : "/Users/someone/Pictures/empty date",
            "photos" : 0,
            "title" : "empty date"
          }
        ]
        """.utf8), "shoots/index.json")

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.recents, 2)
        XCTAssertEqual(r.skipped, [:])
        XCTAssertEqual(r.statusLine, "no earlier sessions found")
        let index = store.index()
        XCTAssertEqual(index.map(\.id), [a, b])
        XCTAssertEqual(index[0], SetsShootStore.Shoot(id: a, title: "SONY-A7M4", path: "/Volumes/Untitled/DCIM", volumeUUID: "5D2C1A3B-0000-4111-8222-333344445555", photos: 3012,
                                                      firstCapture: "2026:07:04 18:22:10", opened: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T21:14:03Z")),
                                                      bookmark: nil, seen: 88, keepers: 12, last: "DSC04410.ARW"))
        XCTAssertNil(index[1].volumeUUID)
        XCTAssertNil(index[1].seen)
        XCTAssertNil(index[1].place)
        XCTAssertEqual(index[1].currentPlace, b)
    }

    func testBadEntriesAreSkippedOneByOneAndStringsAreCapped() throws {
        let long = String(repeating: "x", count: 5000)
        try putIndex([
            entry(a, title: long, opened: "2026-09-28T07:30:00Z", extra: ",\n    \"last\" : \"\(long)\",\n    \"place\" : \"../../etc\",\n    \"seen\" : -4"),
            "  { \"id\" : \"\(b)\", \"opened\" : \"2026-09-20T18:00:00Z\" }",                       // fields missing
            entry("../../../../etc", title: "traversal", opened: "2026-09-20T18:00:00Z"),            // not an id
            entry(c, title: "dated wrongly", opened: "yesterday"),                                    // not a date
            "  42",
            entry(a, title: "the same id again", opened: "2026-01-01T00:00:00Z"),                    // a duplicate: the first stays
            entry(c, title: "studio", opened: "2026-08-01T12:00:00Z", extra: ",\n    \"place\" : \"\(c)\""),
        ])

        let r = try store.importStore(from: oldSupport)

        XCTAssertEqual(r.recents, 2)
        XCTAssertEqual(r.skipped, [.entry: 4])
        let index = store.index()
        XCTAssertEqual(index.map(\.id), [a, c])
        XCTAssertEqual(index[0].title.count, SetsShootStore.importNameCap)
        XCTAssertEqual(index[0].last?.count, SetsShootStore.importNameCap)
        XCTAssertEqual(index[0].path.count, SetsShootStore.importPathCap)
        XCTAssertEqual(index[0].seen, 0)
        XCTAssertNil(index[0].place, "a place that is not an id is dropped")
        XCTAssertEqual(index[1].title, "studio")
        XCTAssertNil(index[1].place, "a place equal to the id is the id")
        XCTAssertLessThan((newFile("shoots/index.json") ?? Data()).count, 8000)
    }

    // MARK: Refusals

    func testAFolderWithoutAnIndexIsRefusedAndNothingIsWritten() throws {
        let empty = sandbox.appendingPathComponent("home/Library/Application Support/Other", isDirectory: true)
        try fm.createDirectory(at: empty.appendingPathComponent("shoots/\(a)", isDirectory: true), withIntermediateDirectories: true)
        try sessionA.write(to: empty.appendingPathComponent("shoots/\(a)/session.json"))
        let before = tree(sandbox)

        XCTAssertThrowsError(try store.importStore(from: empty))
        XCTAssertThrowsError(try store.importStore(from: sandbox.appendingPathComponent("nowhere")))
        XCTAssertNil(SetsShootStore.earlierStore(in: empty))
        XCTAssertNil(SetsShootStore.earlierStore(in: sandbox.appendingPathComponent("nowhere")))
        XCTAssertEqual(tree(sandbox), before)
    }

    func testThisStoreItselfIsRefused() throws {
        try store.upsert(SetsShootStore.Shoot(id: a, title: "t", path: "/p", volumeUUID: nil, photos: 1, firstCapture: "", opened: Date(timeIntervalSince1970: 1_700_000_000), bookmark: Data([1])))
        try store.saveSession(a, sessionA)
        let before = tree(sandbox)
        XCTAssertThrowsError(try store.importStore(from: newSupport))
        XCTAssertEqual(tree(sandbox), before)
    }

    /// The panel's pick: the "Lumina" folder itself, or "Application Support" above it. Never
    /// through a link.
    func testTheEarlierStoreIsFoundInThePickedFolderOrItsLumina() throws {
        try makeOldStore()
        XCTAssertEqual(SetsShootStore.earlierStore(in: oldSupport)?.path, oldSupport.path)
        XCTAssertEqual(SetsShootStore.earlierStore(in: oldSupport.deletingLastPathComponent())?.path, oldSupport.path)
        XCTAssertNil(SetsShootStore.earlierStore(in: oldShoots))
        XCTAssertNil(SetsShootStore.earlierStore(in: sandbox))

        let linked = sandbox.appendingPathComponent("linked/Lumina", isDirectory: true)
        try fm.createDirectory(at: linked, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linked.appendingPathComponent("shoots"), withDestinationURL: oldShoots)
        XCTAssertNil(SetsShootStore.earlierStore(in: linked))
        XCTAssertThrowsError(try store.importStore(from: linked))
        XCTAssertTrue(tree(newSupport).isEmpty)
    }

    // MARK: The launch question

    func testTheQuestionIsOfferedOnlyToAStoreNeverUsedAndNeverAnswered() throws {
        XCTAssertTrue(store.offersImport)
        try store.markImportAsked()
        XCTAssertFalse(store.offersImport)
        XCTAssertEqual(tree(newSupport).keys.sorted(), ["import-asked"], "the marker sits beside shoots/, not in it")
        try store.markImportAsked()
        XCTAssertFalse(store.offersImport)

        let used = SetsShootStore(supportDir: sandbox.appendingPathComponent("used", isDirectory: true))
        XCTAssertTrue(used.offersImport)
        try used.upsert(SetsShootStore.Shoot(id: a, title: "t", path: "/p", volumeUUID: nil, photos: 1, firstCapture: "", opened: Date(), bookmark: nil))
        XCTAssertFalse(used.offersImport, "a store with recents of its own is not asked")
    }

    func testTheStatusLineSaysWhatHappened() {
        var r = SetsShootStore.ImportResult()
        XCTAssertEqual(r.statusLine, "no earlier sessions found")
        r.skipped = [.unreadable: 2]
        XCTAssertEqual(r.statusLine, "no earlier sessions found · 2 skipped")
        r = SetsShootStore.ImportResult(); r.keptNewer = 2
        XCTAssertEqual(r.statusLine, "earlier sessions are already here")
        r = SetsShootStore.ImportResult(); r.sessions = 5; r.keptNewer = 2; r.skipped = [.link: 1]
        XCTAssertEqual(r.statusLine, "5 sessions brought over · open a folder to continue it · 2 kept as they are here · 1 skipped")
    }

    #if canImport(WebKit)
    /// The import takes what the bridge lets the page store, no more.
    @MainActor
    func testTheImportCapIsTheBridgesSessionCap() {
        XCTAssertEqual(SetsShootStore.importSessionBytes, SetsBridge.maxSessionBytes)
    }

    /// The alert's words, as handed to the design (DESIGN-ASKS, "sessions from before the sandbox").
    func testTheAlertsWords() {
        XCTAssertEqual(SetsEarlierSessions.message, "Bring over your earlier sessions?")
        XCTAssertEqual(SetsEarlierSessions.choose, "Choose Folder…")
        XCTAssertEqual(SetsEarlierSessions.notNow, "Not Now")
        XCTAssertTrue(SetsEarlierSessions.earlierSupportDir.path.hasSuffix("/Library/Application Support/Lumina"))
        XCTAssertFalse(SetsEarlierSessions.earlierSupportDir.path.contains("/Containers/"), "the real home, not the container")
        XCTAssertTrue(SetsEarlierSessions.underTest, "a launch under XCTest never asks")
    }
    #endif
}
