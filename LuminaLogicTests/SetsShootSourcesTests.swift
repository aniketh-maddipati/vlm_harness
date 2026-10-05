import WebKit
import XCTest
@testable import Lumina

/// Several sources in one shoot (BRIDGE.md "Sources"): roots under names of their own, roots that
/// are only some files of a folder, the source list kept per shoot, and the bridge's ops for the
/// page's Add, drops, Reconnect and the AirDrop watch, called as WebKit calls them.
///
/// Holds: two folders with the same name are two roots; a root of single files reads, lists and
/// takes sidecars for those files only, never a sibling; a kept source comes back on a reopen and
/// is marked missing when it is not there; nothing is written outside the run's temp folder.
/// Temp folders only; real security-scoped bookmarks (the test host is sandboxed as the app is).
@MainActor
final class SetsShootSourcesTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var support: URL!

    @MainActor final class Chooser: SetsChooser {
        var sources: [URL] = []
        var picks: [[URL]] = []
        var downloads: URL?
        var asked: [(at: URL?, files: Bool, multiple: Bool, prompt: String)] = []
        func chooseSource(allowsDirectories: Bool) async -> URL? { sources.isEmpty ? nil : sources.removeFirst() }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? { nil }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { nil }
        func chooseSources(at: URL?, files: Bool, multiple: Bool, prompt: String, message: String) async -> [URL] {
            asked.append((at, files, multiple, prompt))
            return picks.isEmpty ? [] : picks.removeFirst()
        }
        func chooseDownloads(at: URL) async -> URL? { downloads }
    }

    final class Message: WKScriptMessage {
        private let payload: Any
        init(_ payload: Any) { self.payload = payload; super.init() }
        override var body: Any { payload }
        override var name: String { "lumina" }
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sets-sources-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        support = root.appendingPathComponent("support", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    @discardableResult
    private func folder(_ path: String, _ files: [String]) throws -> URL {
        let dir = root.appendingPathComponent(path, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, f) in files.enumerated() { try Data(repeating: UInt8(i + 1), count: 2048 + i).write(to: dir.appendingPathComponent(f)) }
        return dir
    }

    private func call(_ b: SetsBridge, _ body: Any) async -> Any? {
        let (r, e) = await b.userContentController(WKUserContentController(), didReceive: Message(body))
        XCTAssertNil(e)
        return r
    }

    private func rels(_ d: Any?) -> [String] { (((d as? [String: Any])?["files"] as? [[String: Any]]) ?? []).compactMap { $0["rel"] as? String }.sorted() }

    /// A bridge with `shoot` opened through the page's own ops; the shoot's id.
    private func opened(_ shoot: URL) async -> (SetsBridge, Chooser, String) {
        let chooser = Chooser()
        let b = SetsBridge(chooser: chooser, supportDir: support)
        chooser.sources = [shoot]
        let listing = await call(b, ["op": "openFolder"])
        XCTAssertEqual((listing as? [String: Any])?["name"] as? String, shoot.lastPathComponent)
        let s = await call(b, ["op": "shootOpened", "name": shoot.lastPathComponent, "n": 2, "date": "2026:09:08 10:00:00"])
        let id = (s as? [String: Any])?["id"] as? String ?? ""
        XCTAssertTrue(SetsShootStore.isID(id))
        return (b, chooser, id)
    }

    // MARK: Roots

    func testTwoFoldersWithOneNameAreTwoRoots() throws {
        let a = try folder("a/100MSDCF", ["DSC00001.ARW"]), b = try folder("b/100MSDCF", ["DSC00001.ARW", "DSC00002.ARW"])
        let ingest = SetsIngest(workers: 1)
        ingest.register(a)
        let second = SetsShootSources.alias("100MSDCF", taken: ["100MSDCF"])
        XCTAssertEqual(second, "100MSDCF 2")
        XCTAssertEqual(SetsShootSources.alias("100MSDCF", taken: ["100MSDCF", "100MSDCF 2"]), "100MSDCF 3")
        ingest.register(b, as: second)
        XCTAssertEqual(ingest.resolve("100MSDCF/DSC00001.ARW")?.path, a.appendingPathComponent("DSC00001.ARW").path)
        XCTAssertEqual(ingest.resolve("100MSDCF 2/DSC00001.ARW")?.path, b.appendingPathComponent("DSC00001.ARW").path)
        XCTAssertEqual(try ingest.head("100MSDCF 2/DSC00002.ARW").count, 2049)
        let listing = SetsIngest.list(b, name: second)
        XCTAssertEqual(listing.name, second)
        XCTAssertEqual(listing.files.map(\.rel).sorted(), ["100MSDCF 2/DSC00001.ARW", "100MSDCF 2/DSC00002.ARW"])
        XCTAssertNil(ingest.resolve("100MSDCF 2/../../a/100MSDCF/DSC00001.ARW"))
    }

    func testARootOfSingleFilesReadsOnlyThoseFiles() throws {
        let dir = try folder("Downloads", ["IMG_1.DNG", "IMG_2.DNG", "secret.ARW", "IMG_1.xmp", "notes.txt"])
        try fm.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data([1]).write(to: dir.appendingPathComponent("sub/IMG_9.DNG"))
        let ingest = SetsIngest(workers: 1)
        ingest.register(dir, as: "AirDrop", only: ["IMG_1.DNG", "IMG_2.DNG", "../secret.ARW", "sub/IMG_9.DNG", ".hidden"])
        XCTAssertEqual(ingest.allowed(named: "AirDrop"), ["IMG_1.DNG", "IMG_2.DNG"])
        XCTAssertNotNil(ingest.resolve("AirDrop/IMG_1.DNG"))
        XCTAssertNil(ingest.resolve("AirDrop/secret.ARW"))
        XCTAssertNil(ingest.resolve("AirDrop/sub/IMG_9.DNG"))
        XCTAssertNil(ingest.resolve("AirDrop/IMG_1.xmp"))
        XCTAssertThrowsError(try ingest.head("AirDrop/secret.ARW"))
        XCTAssertEqual(try ingest.head("AirDrop/IMG_2.DNG").count, 2049)
        // The folder is not one of the opened folders (Show in Finder, export refusals); its files are.
        XCTAssertTrue(ingest.rootURLs.isEmpty)
        XCTAssertEqual(Set(ingest.looseURLs.map(\.lastPathComponent)), ["IMG_1.DNG", "IMG_2.DNG"])
        // The listing looks at the named files only: no sibling, no sidecar that was not named, nothing below.
        let l = SetsIngest.list(dir, name: "AirDrop", only: ["IMG_1.DNG", "IMG_2.DNG", "gone.DNG", "sub"])
        XCTAssertEqual(l.files.map(\.rel), ["AirDrop/IMG_1.DNG", "AirDrop/IMG_2.DNG"])
        XCTAssertTrue(l.xmp.isEmpty && l.others.isEmpty)
        XCTAssertEqual(SetsIngest.list(dir, name: "AirDrop", only: ["IMG_1.DNG", "IMG_1.xmp", "notes.txt"]).xmp.map(\.rel), ["AirDrop/IMG_1.xmp"])
        // A link among the names is not a file.
        try fm.createSymbolicLink(at: dir.appendingPathComponent("LINK.DNG"), withDestinationURL: dir.appendingPathComponent("secret.ARW"))
        XCTAssertTrue(SetsIngest.list(dir, name: "AirDrop", only: ["LINK.DNG"]).files.isEmpty)
        // A whole folder registered under the same name again reads everything, as before.
        ingest.register(dir, as: "AirDrop")
        XCTAssertNil(ingest.allowed(named: "AirDrop"))
        XCTAssertNotNil(ingest.resolve("AirDrop/secret.ARW"))
    }

    func testSidecarsOfARootOfSingleFilesStayBesideThem() {
        let files: Set<String> = ["IMG_1.DNG", "X1.ARW"]
        XCTAssertTrue(SetsBridge.sidecarAllowed("X1.xmp", among: files))
        XCTAssertTrue(SetsBridge.sidecarAllowed("IMG_1.XMP", among: files))
        XCTAssertFalse(SetsBridge.sidecarAllowed("Y.xmp", among: files))
        XCTAssertFalse(SetsBridge.sidecarAllowed("sub/X1.xmp", among: files))
        XCTAssertFalse(SetsBridge.sidecarAllowed("../X1.xmp", among: files))
        XCTAssertTrue(SetsBridge.sidecarAllowed("sub/anything.xmp", among: nil))
    }

    // MARK: Claims

    func testThePagesFilesAreMatchedOnlyToWhatWasGranted() throws {
        let shoot = try folder("drop/Wedding", ["DSC1.ARW"]), dl = try folder("Downloads", ["IMG_1.DNG", "IMG_2.DNG", "other.DNG"])
        let pic = try folder("Pictures", ["IMG_1.DNG"])
        let granted: [(url: URL, isDirectory: Bool)] = [(shoot, true), (pic.appendingPathComponent("IMG_1.DNG"), false),
                                                        (dl.appendingPathComponent("IMG_1.DNG"), false), (dl.appendingPathComponent("IMG_2.DNG"), false)]
        let claims = SetsShootSources.claims(files: ["Wedding/DSC1.ARW", "Wedding/sub/DSC2.ARW", "IMG_1.DNG", "Phone/IMG_2.DNG", "other.DNG", "Nowhere/x.ARW", "../IMG_1.DNG/..", "a/b/IMG_1.DNG"], granted: granted)
        XCTAssertEqual(claims.count, 3)
        XCTAssertEqual(claims[0], .init(url: shoot, only: nil, base: "Wedding"))
        // The newest grant of a name wins (Downloads, not Pictures); a page folder ("Phone") names its own root.
        XCTAssertEqual(claims[1], .init(url: dl, only: ["IMG_1.DNG"], base: "Downloads"))
        XCTAssertEqual(claims[2], .init(url: dl, only: ["IMG_2.DNG"], base: "Phone"))
        XCTAssertTrue(SetsShootSources.claims(files: ["other.DNG", "Wedding2/DSC1.ARW"], granted: granted).isEmpty)
        XCTAssertTrue(SetsShootSources.claims(files: ["Wedding/DSC1.ARW"], granted: []).isEmpty)
        // Picked or dropped URLs: folders whole, single files together per folder.
        let picked = SetsBridge.claims(of: [shoot, dl.appendingPathComponent("IMG_1.DNG"), dl.appendingPathComponent("IMG_2.DNG"), root.appendingPathComponent("nothing")])
        XCTAssertEqual(picked, [.init(url: shoot, only: nil, base: "Wedding"), .init(url: dl, only: ["IMG_1.DNG", "IMG_2.DNG"], base: "Downloads")])
        XCTAssertNotEqual(SetsShootSources.loosePlace(folder: "abc", names: ["a"]), SetsShootSources.loosePlace(folder: "abc", names: ["a", "b"]))
        XCTAssertTrue(SetsShootStore.isID(SetsShootSources.loosePlace(folder: "abc", names: ["a"])))
    }

    // MARK: The store

    func testTheSourceListIsKeptPerShootAndRefusesOtherIds() throws {
        let store = SetsShootSources(supportDir: support)
        let id = "0123456789abcdef"
        var s = SetsShootSources.Stored()
        s.entries = [.init(nid: "n1", name: "B", kind: "folder", label: "B", files: nil, refs: ["r"], primary: nil, offset: -300, n: 5)]
        try store.save(id, s)
        XCTAssertEqual(store.load(id).entries, s.entries)
        XCTAssertThrowsError(try store.save("../../outside", s))
        XCTAssertTrue(store.load("../../outside").entries.isEmpty)
        s.entries = []
        try store.save(id, s)                                 // nothing left to keep: no file
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("sources/\(id).json").path))
        store.remove("../../outside")
    }

    // MARK: The bridge's ops

    func testAddFromJoinsAFolderUnderItsOwnNameAndAReopenBringsItBack() async throws {
        let a = try folder("a/100MSDCF", ["DSC00001.ARW", "DSC00002.ARW"]), b = try folder("b/100MSDCF", ["DSC00001.ARW", "DSC00009.ARW", "DSC00009.xmp"])
        let (bridge, chooser, id) = await opened(a)
        chooser.picks = [[b]]
        let r = await call(bridge, ["op": "addFrom", "where": "pictures", "add": true, "id": id]) as? [String: Any]
        let added = (r?["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(chooser.asked.first?.at?.lastPathComponent, "Pictures")
        XCTAssertEqual(chooser.asked.first?.prompt, "Add to shoot")
        XCTAssertEqual(added?["name"] as? String, "100MSDCF 2")
        XCTAssertEqual(added?["kind"] as? String, "pictures")
        XCTAssertNil(added?["primary"])
        XCTAssertEqual(rels(added), ["100MSDCF 2/DSC00001.ARW", "100MSDCF 2/DSC00009.ARW"])
        let nid = try XCTUnwrap(added?["nid"] as? String)
        XCTAssertEqual(bridge.shootRoots.map(\.name), ["100MSDCF", "100MSDCF 2"])
        XCTAssertEqual(bridge.resolve("100MSDCF 2/DSC00001.ARW")?.path, b.appendingPathComponent("DSC00001.ARW").path)
        XCTAssertEqual(bridge.resolve("100MSDCF/DSC00001.ARW")?.path, a.appendingPathComponent("DSC00001.ARW").path)
        // The same folder again is the same root (the page then finds nothing new).
        chooser.picks = [[b]]
        let again = ((await call(bridge, ["op": "addFrom", "where": "folder", "add": true, "id": id]) as? [String: Any])?["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(again?["name"] as? String, "100MSDCF 2")
        XCTAssertEqual(again?["nid"] as? String, nid)
        XCTAssertEqual(bridge.shootRoots.count, 2)
        XCTAssertNil(chooser.asked.last?.at)
        // The page keeps it, with a clock shift: the Mac stores both, and says it is there.
        let status = await call(bridge, ["op": "shootSources", "id": id, "sources": [["nid": nid, "offset": -300, "n": 2]]]) as? [[String: Any]]
        XCTAssertEqual(status?.count, 1)
        XCTAssertEqual(status?.first?["missing"] as? Bool, false)
        let kept = bridge.sources.load(id).entries
        XCTAssertEqual(kept.map(\.name), ["100MSDCF 2"])
        XCTAssertEqual(kept.first?.offset, -300)
        XCTAssertEqual(kept.first?.n, 2)
        // Save: a sidecar under each root, beside its own RAW.
        let xmp = Data("<x:xmpmeta/>".utf8).base64EncodedString()
        let w1 = await call(bridge, ["op": "writeSidecars", "root": "100MSDCF 2", "files": [["name": "DSC00001.xmp", "b64": xmp]]]) as? [String: Any]
        let w2 = await call(bridge, ["op": "writeSidecars", "root": "100MSDCF", "files": [["name": "DSC00001.xmp", "b64": xmp]]]) as? [String: Any]
        XCTAssertEqual(w1?["n"] as? Int, 1)
        XCTAssertEqual(w2?["n"] as? Int, 1)
        XCTAssertEqual(w1?["path"] as? String, b.path)
        XCTAssertTrue(fm.fileExists(atPath: b.appendingPathComponent("DSC00001.xmp").path) && fm.fileExists(atPath: a.appendingPathComponent("DSC00001.xmp").path))
        // Close and open the folder again: the added source comes back as `more`, with what was kept.
        bridge.closeShoot()
        XCTAssertTrue(bridge.shootRoots.isEmpty)
        chooser.sources = [a]
        let reopened = await call(bridge, ["op": "openFolder"]) as? [String: Any]
        let more = reopened?["more"] as? [[String: Any]]
        XCTAssertEqual((reopened?["source"] as? [String: Any])?["kind"] as? String, "folder")
        XCTAssertEqual(more?.count, 1)
        XCTAssertEqual(more?.first?["nid"] as? String, nid)
        XCTAssertEqual(more?.first?["offset"] as? Int, -300)
        XCTAssertEqual(rels(more?.first), ["100MSDCF 2/DSC00001.ARW", "100MSDCF 2/DSC00009.ARW"])
        XCTAssertNil(more?.first?["missing"])
        XCTAssertEqual(bridge.shootRoots.map(\.name), ["100MSDCF", "100MSDCF 2"])
        // Gone: the shoot still opens, the source is marked.
        bridge.closeShoot()
        try fm.moveItem(at: b.deletingLastPathComponent(), to: root.appendingPathComponent("b-moved"))
        chooser.sources = [a]
        let partly = await call(bridge, ["op": "openFolder"]) as? [String: Any]
        XCTAssertEqual(rels(partly), ["100MSDCF/DSC00001.ARW", "100MSDCF/DSC00002.ARW"])
        let lost = (partly?["more"] as? [[String: Any]])?.first
        // A bookmark follows a folder moved on its volume: either found again, or marked missing. Never read from the old path.
        if lost?["missing"] as? Bool == true {
            XCTAssertEqual(lost?["n"] as? Int, 2)
            do { let v = (await call(bridge, ["op": "sourcesStatus"]) as? [[String: Any]])?.first?["missing"] as? Bool; XCTAssertEqual(v, true) }
        } else {
            XCTAssertEqual(rels(lost), ["100MSDCF 2/DSC00001.ARW", "100MSDCF 2/DSC00009.ARW"])
            XCTAssertEqual(bridge.resolve("100MSDCF 2/DSC00009.ARW")?.resolvingSymlinksInPath().path, root.appendingPathComponent("b-moved/100MSDCF/DSC00009.ARW").path)
        }
        // The page dropped it: the Mac forgets it.
        _ = await call(bridge, ["op": "shootOpened", "name": "100MSDCF", "n": 2, "date": ""])
        _ = await call(bridge, ["op": "shootSources", "id": id, "sources": []])
        XCTAssertTrue(bridge.sources.load(id).entries.isEmpty)
    }

    func testASourceThatIsGoneIsMissingAndReconnectAsksForTheFolder() async throws {
        let a = try folder("a/Shoot", ["DSC00001.ARW"]), b = try folder("b/Second", ["DSC00005.ARW"])
        let (bridge, chooser, id) = await opened(a)
        chooser.picks = [[b]]
        let added = ((await call(bridge, ["op": "addFrom", "where": "folder", "add": true, "id": id]) as? [String: Any])?["sources"] as? [[String: Any]])?.first
        let nid = try XCTUnwrap(added?["nid"] as? String)
        _ = await call(bridge, ["op": "shootSources", "id": id, "sources": [["nid": nid, "n": 1]]])
        bridge.closeShoot()
        try fm.removeItem(at: b)
        chooser.sources = [a]
        let partly = await call(bridge, ["op": "openFolder"]) as? [String: Any]
        let lost = (partly?["more"] as? [[String: Any]])?.first
        XCTAssertEqual(lost?["missing"] as? Bool, true)
        XCTAssertEqual(lost?["name"] as? String, "Second")
        XCTAssertNil(bridge.resolve("Second/DSC00005.ARW").flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil })
        _ = await call(bridge, ["op": "shootOpened", "name": "Shoot", "n": 1, "date": ""])
        // Reconnect: the bookmark finds nothing, the panel is asked, the pick takes the source's place under its name.
        let moved = try folder("elsewhere/Renamed", ["DSC00005.ARW", "DSC00006.ARW"])
        chooser.picks = []
        do { let v = await call(bridge, ["op": "sourceReconnect", "nid": nid, "id": id]); XCTAssertTrue(v is NSNull) }          // cancelled
        chooser.picks = [[moved]]
        let back = (await call(bridge, ["op": "sourceReconnect", "nid": nid, "id": id]) as? [String: Any])?["source"] as? [String: Any]
        XCTAssertEqual(chooser.asked.last?.prompt, "Reconnect")
        XCTAssertEqual(chooser.asked.last?.files, false)
        XCTAssertEqual(rels(back), ["Second/DSC00005.ARW", "Second/DSC00006.ARW"])
        XCTAssertEqual(bridge.resolve("Second/DSC00006.ARW")?.path, moved.appendingPathComponent("DSC00006.ARW").path)
        do { let v = (await call(bridge, ["op": "sourcesStatus"]) as? [[String: Any]])?.first?["missing"] as? Bool; XCTAssertEqual(v, false) }
        // Another shoot's id, or a made-up source: nothing.
        do { let v = await call(bridge, ["op": "sourceReconnect", "nid": "nope", "id": id]); XCTAssertTrue(v is NSNull) }
        do { let v = await call(bridge, ["op": "sourceReconnect", "nid": nid, "id": "../../x"]); XCTAssertTrue(v is NSNull) }
    }

    func testDroppedFilesAreClaimedAsARootOfTheirOwnAndNothingElseIs() async throws {
        let a = try folder("a/Shoot", ["DSC00001.ARW"])
        let dl = try folder("Downloads", ["X1.ARW", "X2.ARW", "Y.ARW"])
        let dropped = try folder("drop/Dropped", ["DSC00007.ARW"])
        let (bridge, _, id) = await opened(a)
        // Nothing was handed over yet: the page reads its own files.
        do { let v = await call(bridge, ["op": "claimFiles", "files": [["rel": "X1.ARW", "size": 2048]], "add": true, "id": id]); XCTAssertTrue(v is NSNull) }
        bridge.grant([dl.appendingPathComponent("X1.ARW"), dl.appendingPathComponent("X2.ARW"), dropped])
        let r = await call(bridge, ["op": "claimFiles", "files": [["rel": "X1.ARW", "size": 2048], ["rel": "X2.ARW", "size": 2049], ["rel": "Y.ARW", "size": 2050], ["rel": "Dropped/DSC00007.ARW", "size": 2048]],
                                    "add": true, "id": id, "kind": "drop"]) as? [String: Any]
        let list = r?["sources"] as? [[String: Any]] ?? []
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(rels(list.first), ["Dropped/DSC00007.ARW"])
        XCTAssertEqual(rels(list.last), ["Downloads/X1.ARW", "Downloads/X2.ARW"])
        XCTAssertEqual(list.last?["kind"] as? String, "drop")
        XCTAssertNotNil(bridge.resolve("Downloads/X1.ARW"))
        XCTAssertNil(bridge.resolve("Downloads/Y.ARW"))                 // a sibling that was not dropped
        // Sidecars: beside a dropped file, never beside its sibling.
        let xmp = Data("<x:xmpmeta/>".utf8).base64EncodedString()
        let w = await call(bridge, ["op": "writeSidecars", "root": "Downloads", "files": [["name": "X1.xmp", "b64": xmp], ["name": "Y.xmp", "b64": xmp], ["name": "sub/X1.xmp", "b64": xmp]]]) as? [String: Any]
        XCTAssertEqual(w?["n"] as? Int, 1)
        XCTAssertEqual((w?["errors"] as? [[String: String]])?.map { $0["reason"] }, ["refused", "refused"])
        XCTAssertTrue(fm.fileExists(atPath: dl.appendingPathComponent("X1.xmp").path))
        XCTAssertFalse(fm.fileExists(atPath: dl.appendingPathComponent("Y.xmp").path))
        let read = await call(bridge, ["op": "readSidecars", "root": "Downloads", "files": ["X1.xmp", "Y.xmp"]]) as? [[String: Any]]
        XCTAssertNotNil(read?.first?["base"])
        XCTAssertNil(read?.last?["base"])
        // More files of the same folder join the same root.
        bridge.grant([dl.appendingPathComponent("Y.ARW")])
        let more = ((await call(bridge, ["op": "claimFiles", "files": [["rel": "Y.ARW", "size": 2050]], "add": true, "id": id, "kind": "drop"]) as? [String: Any])?["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(rels(more), ["Downloads/Y.ARW"])
        XCTAssertEqual(more?["nid"] as? String, list.last?["nid"] as? String)
        XCTAssertNotNil(bridge.resolve("Downloads/X2.ARW"))
        XCTAssertEqual(bridge.shootRoots.map(\.name), ["Shoot", "Dropped", "Downloads"])
        // Show in Finder: a dropped file, not the folder it came from.
        do { let v = await call(bridge, ["op": "reveal", "path": "Downloads"]) as? Bool; XCTAssertEqual(v, false) }
    }

    func testADropWithNoShootOpenIsAShootAndSingleFilesReopenThroughTheirOwnBookmarks() async throws {
        let dl = try folder("Downloads", ["IMG_1.DNG", "IMG_2.DNG", "IMG_3.DNG"])
        let chooser = Chooser()
        let bridge = SetsBridge(chooser: chooser, supportDir: support)
        bridge.grant([dl.appendingPathComponent("IMG_1.DNG"), dl.appendingPathComponent("IMG_2.DNG")])
        let r = await call(bridge, ["op": "claimFiles", "files": [["rel": "Phone/IMG_1.DNG", "size": 1], ["rel": "Phone/IMG_2.DNG", "size": 1]], "add": false, "kind": "phone", "label": "AirDrop"]) as? [String: Any]
        let first = (r?["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["primary"] as? Bool, true)
        XCTAssertEqual(first?["name"] as? String, "Phone")
        XCTAssertEqual((first?["source"] as? [String: Any])?["kind"] as? String, "phone")
        XCTAssertEqual(rels(first), ["Phone/IMG_1.DNG", "Phone/IMG_2.DNG"])
        XCTAssertNil(bridge.resolve("Phone/IMG_3.DNG"))
        let s = await call(bridge, ["op": "shootOpened", "name": "Phone", "n": 2, "date": ""]) as? [String: Any]
        let id = try XCTUnwrap(s?["id"] as? String)
        XCTAssertEqual(bridge.shoots.index().first?.title, "Phone")
        XCTAssertNil(bridge.shoots.index().first?.bookmark)             // the folder was never granted
        let entry = try XCTUnwrap(bridge.sources.load(id).entries.first)
        XCTAssertTrue(entry.isPrimary)
        XCTAssertEqual(entry.files, ["IMG_1.DNG", "IMG_2.DNG"])
        // The page keeps no added source: the first one stays.
        _ = await call(bridge, ["op": "shootSources", "id": id, "sources": []])
        XCTAssertEqual(bridge.sources.load(id).entries.count, 1)
        // From Recents: the same shoot, the same two files, through their bookmarks.
        bridge.closeShoot()
        XCTAssertTrue(bridge.reopen(id: id))
        let again = await call(bridge, ["op": "openFolder"]) as? [String: Any]
        XCTAssertEqual(rels(again), ["Phone/IMG_1.DNG", "Phone/IMG_2.DNG"])
        XCTAssertNil(bridge.resolve("Phone/IMG_3.DNG"))
        let s2 = await call(bridge, ["op": "shootOpened", "name": "Phone", "n": 2, "date": ""]) as? [String: Any]
        XCTAssertEqual(s2?["id"] as? String, id)
        XCTAssertEqual(bridge.sources.load(id).entries.count, 1)
        // Another pick from the same folder is another shoot.
        bridge.closeShoot()
        bridge.grant([dl.appendingPathComponent("IMG_3.DNG")])
        _ = await call(bridge, ["op": "claimFiles", "files": [["rel": "Phone/IMG_3.DNG", "size": 1]], "add": false, "kind": "phone"])
        let s3 = await call(bridge, ["op": "shootOpened", "name": "Phone", "n": 1, "date": ""]) as? [String: Any]
        XCTAssertNotEqual(s3?["id"] as? String, id)
    }

    func testTheAirDropWatchAsksOnceAndHandsOverOnlyWhatArrived() async throws {
        let dl = try folder("Downloads", ["old.DNG"])
        let a = try folder("a/Shoot", ["DSC00001.ARW"])
        let (bridge, chooser, id) = await opened(a)
        // No folder (the panel cancelled): false, nothing watched.
        do { let v = await call(bridge, ["op": "watchAirdrop", "on": true]) as? Bool; XCTAssertEqual(v, false) }
        chooser.downloads = dl
        do { let v = await call(bridge, ["op": "watchAirdrop", "on": true]) as? Bool; XCTAssertEqual(v, true) }
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("downloads.bookmark").path))
        // Not there before the watch started, complete for a second: an arrival.
        try await Task.sleep(nanoseconds: 300_000_000)
        try Data(repeating: 7, count: 4096).write(to: dl.appendingPathComponent("IMG_7.DNG"))
        var claimed: [String: Any]?
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 250_000_000)
            claimed = await call(bridge, ["op": "claimFiles", "files": [["rel": "AirDrop/IMG_7.DNG", "size": 4096], ["rel": "AirDrop/old.DNG", "size": 2048]], "add": true, "id": id, "kind": "phone", "label": "AirDrop"]) as? [String: Any]
            if claimed != nil { break }
        }
        let got = (claimed?["sources"] as? [[String: Any]])?.first
        XCTAssertEqual(rels(got), ["AirDrop/IMG_7.DNG"])
        XCTAssertEqual(got?["kind"] as? String, "phone")
        XCTAssertEqual(got?["label"] as? String, "AirDrop")
        XCTAssertNotNil(bridge.resolve("AirDrop/IMG_7.DNG"))
        XCTAssertNil(bridge.resolve("AirDrop/old.DNG"))                 // was there before: never an arrival
        XCTAssertEqual(bridge.sources.load(id).entries.first?.files, ["IMG_7.DNG"])
        // Off, then on again: the bookmark answers, the panel is not needed.
        do { let v = await call(bridge, ["op": "watchAirdrop", "on": false]) as? Bool; XCTAssertEqual(v, true) }
        chooser.downloads = nil
        do { let v = await call(bridge, ["op": "watchAirdrop", "on": true]) as? Bool; XCTAssertEqual(v, true) }
        do { let v = await call(bridge, ["op": "watchAirdrop", "on": false]) as? Bool; XCTAssertEqual(v, true) }
    }
}
