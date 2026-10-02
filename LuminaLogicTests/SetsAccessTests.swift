import XCTest
@testable import Lumina

/// Security-scoped access (T9, R1b): start / stop balanced per open shoot, at most one held
/// however often a shoot is reopened, a stale bookmark renewed and saved, no fallback to the
/// stored path when a bookmark cannot be resolved, and a renamed folder staying the same shoot.
/// Start and stop are counted by fakes; the bookmarks in the rename tests are real.
@MainActor
final class SetsAccessTests: XCTestCase {
    private var sandbox: URL!
    private var store: SetsShootStore!
    private let fm = FileManager.default

    /// What the fakes saw: folders currently started, and every start / stop.
    private var active: [String: Int] = [:]
    private var log: [String] = []

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("sets-access-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try fm.createDirectory(at: sandbox.appendingPathComponent("support"), withIntermediateDirectories: true)
        store = SetsShootStore(supportDir: sandbox.appendingPathComponent("support"))
        active = [:]; log = []
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: sandbox) }

    private func folder(_ name: String) throws -> URL {
        let u = sandbox.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Fakes: a "bookmark" is the folder's path; `stale` and `refuse` steer resolution.
    private func calls(stale: Bool = false, refuse: Bool = false) -> SetsAccess.Calls {
        SetsAccess.Calls(
            start: { [unowned self] u in active[u.path, default: 0] += 1; log.append("start \(u.lastPathComponent)"); return true },
            stop: { [unowned self] u in active[u.path, default: 0] -= 1; if active[u.path] == 0 { active[u.path] = nil }; log.append("stop \(u.lastPathComponent)") },
            resolve: { data in
                if refuse { throw CocoaError(.fileNoSuchFile) }
                return (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), stale)
            },
            bookmark: { Data(("renewed:" + $0.path).utf8) },
            exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue })
    }

    private func recent(_ url: URL, bookmark: Data?) throws -> SetsShootStore.Shoot {
        let s = SetsShootStore.Shoot(id: SetsShootStore.id(for: url), title: url.lastPathComponent, path: url.path, volumeUUID: SetsFileOps.volumeID(url),
                                     photos: 3, firstCapture: "", opened: Date(), bookmark: bookmark)
        try store.upsert(s)
        return s
    }

    private var startedNow: Int { active.values.reduce(0, +) }

    // MARK: Balance

    func testOpenOpenAnotherCloseReopenIsBalanced() throws {
        let a = try folder("A"), b = try folder("B")
        let access = SetsAccess(calls: calls())
        let shootA = try recent(a, bookmark: Data(a.path.utf8))
        let shootB = try recent(b, bookmark: Data(b.path.utf8))

        XCTAssertEqual(access.reopen(shootA, store: store)?.path, a.path)
        XCTAssertEqual(active, [a.path: 1])
        // The page then asks for the pending folder: the same folder, not started again.
        access.openShoot(a, scoped: false)
        XCTAssertEqual(access.starts, 1)

        XCTAssertNotNil(access.reopen(shootB, store: store))
        XCTAssertEqual(active, [b.path: 1], "opening B lets A go")
        access.closeShoot()
        XCTAssertEqual(active, [:])
        XCTAssertEqual(access.started, 0)

        XCTAssertNotNil(access.reopen(shootA, store: store))
        XCTAssertEqual(active, [a.path: 1])
        // A panel's pick: needs no start, and the bookmark's access is let go.
        access.openShoot(b, scoped: false)
        XCTAssertEqual(active, [:])
        access.closeShoot()
        XCTAssertEqual(access.starts, access.stops)
        XCTAssertEqual(log, ["start A", "start B", "stop A", "stop B", "start A", "stop A"])
    }

    func testTwoHundredReopensHoldAtMostOne() throws {
        let a = try folder("A"), b = try folder("B")
        let access = SetsAccess(calls: calls())
        let shoots = [try recent(a, bookmark: Data(a.path.utf8)), try recent(b, bookmark: Data(b.path.utf8))]
        for i in 0..<200 {
            let s = shoots[i % 3 == 0 ? 0 : 1]
            let url = try XCTUnwrap(access.reopen(s, store: store))
            access.openShoot(url, scoped: false)
            XCTAssertLessThanOrEqual(startedNow, 1, "reopen \(i)")
            XCTAssertLessThanOrEqual(access.started, 1)
            if i % 7 == 0 { access.closeShoot(); XCTAssertEqual(startedNow, 0) }
        }
        access.closeShoot()
        XCTAssertEqual(startedNow, 0)
        XCTAssertEqual(access.starts, access.stops)
    }

    func testReopeningTheOpenShootDoesNotRestartIt() throws {
        let a = try folder("A")
        let access = SetsAccess(calls: calls())
        let s = try recent(a, bookmark: Data(a.path.utf8))
        for _ in 0..<50 { _ = access.reopen(s, store: store) }
        XCTAssertEqual(access.starts, 1, "the same folder is started once")
        XCTAssertEqual(startedNow, 1)
        access.closeShoot()
        XCTAssertEqual(startedNow, 0)
    }

    func testHoldOutlivesTheShoot() throws {
        let a = try folder("A"), b = try folder("B")
        let access = SetsAccess(calls: calls())
        let s = try recent(a, bookmark: Data(a.path.utf8))
        _ = access.reopen(s, store: store)
        let t = access.hold(a)                       // a Save in flight
        access.openShoot(b, scoped: false)           // another shoot opened meanwhile
        XCTAssertEqual(active, [a.path: 1], "the Save keeps A")
        access.release(t)
        XCTAssertEqual(active, [:])
        access.release(t)                            // twice is harmless
        XCTAssertEqual(access.starts, access.stops)
    }

    // MARK: Resolution

    func testStaleBookmarkIsRenewedAndSaved() throws {
        let a = try folder("A")
        let access = SetsAccess(calls: calls(stale: true))
        let s = try recent(a, bookmark: Data(a.path.utf8))
        XCTAssertNotNil(access.reopen(s, store: store))
        let saved = try XCTUnwrap(store.index().first { $0.id == s.id })
        XCTAssertEqual(saved.bookmark, Data(("renewed:" + a.path).utf8))
        XCTAssertEqual(saved.path, a.path)
        XCTAssertNil(saved.place, "same place: nothing moved")
        XCTAssertEqual(saved.photos, 3)
    }

    func testUnresolvableBookmarkReturnsNilWithNoFallback() throws {
        let a = try folder("A")
        let access = SetsAccess(calls: calls(refuse: true))
        // The stored path exists and would be readable unsandboxed: it must not be used.
        let s = try recent(a, bookmark: Data(a.path.utf8))
        XCTAssertNil(access.reopen(s, store: store))
        XCTAssertNil(access.reopen(try recent(a, bookmark: nil), store: store), "no bookmark: not available")
        XCTAssertEqual(access.starts, 0)
        XCTAssertNil(access.shoot)
    }

    func testFolderGoneReturnsNilAndStopsWhatItStarted() throws {
        let a = try folder("A"), b = try folder("B")
        let access = SetsAccess(calls: calls())
        let sB = try recent(b, bookmark: Data(b.path.utf8))
        _ = access.reopen(sB, store: store)
        let s = try recent(a, bookmark: Data(a.path.utf8))
        try fm.removeItem(at: a)
        XCTAssertNil(access.reopen(s, store: store))
        XCTAssertEqual(active, [b.path: 1], "the open shoot is kept; the failed one is stopped")
        XCTAssertEqual(access.shoot?.path, b.path)
        access.closeShoot()
        XCTAssertEqual(access.starts, access.stops)
    }

    // MARK: Renamed and moved folders (real bookmarks)

    private func realBookmark(_ url: URL) throws -> Data {
        do { return try SetsAccess.Calls.system.bookmark(url) } catch { throw XCTSkip("no security-scoped bookmark here: \(error)") }
    }

    func testRenamedFolderIsFollowedAndKeepsItsShoot() throws {
        let a = try folder("Shoot")
        let s = try recent(a, bookmark: try realBookmark(a))
        let renamed = sandbox.appendingPathComponent("Shoot renamed", isDirectory: true)
        try fm.moveItem(at: a, to: renamed)
        let access = SetsAccess(calls: .system)
        let url = try XCTUnwrap(access.reopen(s, store: store), "the bookmark follows a rename on the same volume")
        XCTAssertEqual(url.resolvingSymlinksInPath().path, renamed.path)
        access.closeShoot()
        XCTAssertEqual(access.starts, access.stops)
        // The bridge then upserts it under the same id at its new place (shootOpened).
        var moved = s; moved.path = url.path; moved.place = SetsShootStore.id(for: url); moved.bookmark = nil
        try store.upsert(moved)
        let list = store.index()
        XCTAssertEqual(list.count, 1, "one shoot, not two")
        XCTAssertEqual(list[0].id, s.id)
        XCTAssertEqual(list[0].path, url.path)
        XCTAssertNotNil(list[0].bookmark, "the bookmark it came through is kept")
        XCTAssertEqual(store.shootID(at: SetsShootStore.id(for: url)), s.id, "a panel pick of the new place is the same shoot")
        // A new folder at the old place is another shoot, with an id of its own.
        let other = store.shootID(at: SetsShootStore.id(for: a))
        XCTAssertNotEqual(other, s.id)
        XCTAssertTrue(SetsShootStore.isID(other))
    }

    func testPanelPickOfARenamedFolderFindsItsShoot() throws {
        let a = try folder("Shoot")
        let s = try recent(a, bookmark: try realBookmark(a))
        let renamed = sandbox.appendingPathComponent("Shoot 2", isDirectory: true)
        try fm.moveItem(at: a, to: renamed)
        let access = SetsAccess(calls: .system)
        XCTAssertEqual(access.movedShoot(to: renamed, volume: SetsFileOps.volumeID(renamed), in: store)?.id, s.id)
        XCTAssertNil(access.movedShoot(to: try folder("Unrelated"), volume: SetsFileOps.volumeID(renamed), in: store))
        XCTAssertEqual(access.starts, 0, "matching starts nothing")
    }

    func testDeletedFolderBookmarkIsNotAvailable() throws {
        let a = try folder("Gone")
        let s = try recent(a, bookmark: try realBookmark(a))
        try fm.removeItem(at: a)
        let access = SetsAccess(calls: .system)
        XCTAssertNil(access.reopen(s, store: store))
        XCTAssertEqual(access.started, 0)
    }

    func testLegacyBookmarksFolderIsRemoved() throws {
        let support = sandbox.appendingPathComponent("support")
        let dir = support.appendingPathComponent("bookmarks")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("0123456789abcdef.bookmark"))
        try Data("keep".utf8).write(to: support.appendingPathComponent("prefs.json"))
        SetsAccess.removeLegacyBookmarks(supportDir: support)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("prefs.json").path))
        SetsAccess.removeLegacyBookmarks(supportDir: support)      // nothing left: quiet
    }
}
