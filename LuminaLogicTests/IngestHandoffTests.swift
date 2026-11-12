import WebKit
import XCTest
@testable import Lumina

/// Lumina Ingest's Open in Pick: which folder Pick opens, and which of its files.
final class IngestHandoffTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-handoff-\(UUID().uuidString)", isDirectory: true)
        for f in ["card/DCIM/100MSDCF/A.ARW", "card/DCIM/100MSDCF/B.ARW", "card/DCIM/101MSDCF/C.ARW", "t7/D.ARW"] {
            let u = tmp.appendingPathComponent(f)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: u)
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func plan(_ paths: [String], whole: Bool, _ roots: [String]) -> Result<IngestHandoff.Plan, IngestHandoff.Refusal> {
        IngestHandoff.plan(paths: paths, whole: whole, roots: roots.map { tmp.appendingPathComponent($0) })
    }

    func testTheWholeReadOpensTheFolderAsPicked() throws {
        let p = try plan(["card/DCIM/100MSDCF/A.ARW", "card/DCIM/101MSDCF/C.ARW"], whole: true, ["card"]).get()
        XCTAssertEqual(p.folder.path, tmp.appendingPathComponent("card").standardizedFileURL.path)
        XCTAssertNil(p.only)
    }

    func testAFindOpensTheDeepestFolderAndOnlyThoseFiles() throws {
        let p = try plan(["card/DCIM/100MSDCF/B.ARW"], whole: false, ["card"]).get()
        XCTAssertEqual(p.folder.lastPathComponent, "100MSDCF")
        XCTAssertEqual(p.only, ["B.ARW"])
        let q = try plan(["card/DCIM/100MSDCF/A.ARW", "card/DCIM/101MSDCF/C.ARW"], whole: false, ["card"]).get()
        XCTAssertEqual(q.folder.lastPathComponent, "DCIM")
        XCTAssertEqual(q.only, ["100MSDCF/A.ARW", "101MSDCF/C.ARW"])
    }

    func testRefusals() {
        XCTAssertEqual(plan(["card/DCIM/100MSDCF/A.ARW", "t7/D.ARW"], whole: true, ["card", "t7"]), .failure(.severalSources))
        XCTAssertEqual(plan(["D.ARW"], whole: true, ["t7/D.ARW"]), .failure(.looseFiles))
        XCTAssertEqual(plan(["card/../t7/D.ARW"], whole: true, ["card"]), .failure(.unknown))
        XCTAssertEqual(plan(["elsewhere/A.ARW"], whole: true, ["card"]), .failure(.unknown))
        XCTAssertEqual(plan([], whole: true, ["card"]), .failure(.nothing))
    }

    func testAPartHasAShootIdOfItsOwn() {
        let a = IngestHandoff.subsetID(place: "0123456789abcdef", only: ["A.ARW", "B.ARW"])
        XCTAssertTrue(SetsShootStore.isID(a))
        XCTAssertNotEqual(a, "0123456789abcdef")
        XCTAssertEqual(a, IngestHandoff.subsetID(place: "0123456789abcdef", only: ["B.ARW", "A.ARW"]))
    }
}

/// The bridge's half: Pick opens the handed-over folder through its own Open (`open` → `openFolder` → `shootOpened`),
/// whole as a plain shoot, or only the files the ingest page showed under an id of their own and no recent.
@MainActor
final class IngestHandoffBridgeTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    @MainActor final class Chooser: SetsChooser {
        func chooseSource(allowsDirectories: Bool) async -> URL? { nil }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? { nil }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { nil }
    }

    final class Message: WKScriptMessage {
        private let payload: Any
        init(_ payload: Any) { self.payload = payload; super.init() }
        override var body: Any { payload }
        override var name: String { "lumina" }
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("ingest-bridge-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        let shoot = root.appendingPathComponent("shoot/a", isDirectory: true)
        try fm.createDirectory(at: shoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("support"), withIntermediateDirectories: true)
        for n in ["DSC00001", "DSC00002", "DSC00003"] { try Data(repeating: 1, count: 4096).write(to: shoot.appendingPathComponent(n + ".ARW")) }
        try Data("<x:xmpmeta/>".utf8).write(to: shoot.appendingPathComponent("DSC00002.xmp"))
        try Data("<x:xmpmeta/>".utf8).write(to: shoot.appendingPathComponent("DSC00003.xmp"))
        try Data([0xFF, 0xD8]).write(to: shoot.appendingPathComponent("DSC00002.JPG"))
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func bridge() -> SetsBridge {
        let access = SetsAccess(calls: SetsAccess.Calls(start: { _ in true }, stop: { _ in },
                                                        resolve: { data in (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false) },
                                                        bookmark: { Data($0.path.utf8) },
                                                        exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }))
        return SetsBridge(chooser: Chooser(), supportDir: root.appendingPathComponent("support"), access: access)
    }

    private func call(_ b: SetsBridge, _ body: Any) async -> Any? {
        await b.userContentController(WKUserContentController(), didReceive: Message(body)).0
    }

    /// Ingest → plan → Pick's own open, as the window does it (`onIngestToPick` → `open(folder, only:)` once Pick is ready).
    private func handOver(_ b: SetsBridge, _ paths: [String], whole: Bool) async throws -> (listing: [String: Any], id: String) {
        var plan: IngestHandoff.Plan?
        b.onIngestToPick = { plan = $0 }
        b.ingestRoots = [root.appendingPathComponent("shoot")]
        let r = await b.ingestToPick(paths, whole: whole)
        XCTAssertEqual(r as? Bool, true, "\(r)")
        let p = try XCTUnwrap(plan)
        b.open(p.folder, only: p.only)
        let l0 = await call(b, ["op": "openFolder"])
        let listing = try XCTUnwrap(l0 as? [String: Any])
        let o0 = await call(b, ["op": "shootOpened", "name": p.folder.lastPathComponent, "n": 1, "date": ""])
        let opened = try XCTUnwrap(o0 as? [String: Any])
        return (listing, try XCTUnwrap(opened["id"] as? String))
    }

    private func rels(_ l: [String: Any], _ k: String) -> [String] {
        ((l[k] as? [[String: Any]])?.compactMap { $0["rel"] as? String } ?? (l[k] as? [String]) ?? []).sorted()
    }

    func testTheWholeReadIsPicksOwnOpen() async throws {
        let b = bridge()
        let (l, id) = try await handOver(b, ["shoot/a/DSC00001.ARW", "shoot/a/DSC00002.ARW", "shoot/a/DSC00003.ARW"], whole: true)
        XCTAssertEqual(rels(l, "files"), ["shoot/a/DSC00001.ARW", "shoot/a/DSC00002.ARW", "shoot/a/DSC00003.ARW"])
        XCTAssertEqual(id, SetsShootStore.id(for: root.appendingPathComponent("shoot")))
        XCTAssertEqual(b.shoots.index().map(\.id), [id], "a recent, as Open makes")
    }

    func testAFoundSetThatIsAWholeFolderOpensThatFolder() async throws {
        let b = bridge()
        let (l, id) = try await handOver(b, ["shoot/a/DSC00001.ARW", "shoot/a/DSC00002.ARW", "shoot/a/DSC00003.ARW", "shoot/a/DSC00002.JPG"], whole: false)
        XCTAssertEqual(rels(l, "files").count, 3)
        XCTAssertEqual(id, SetsShootStore.id(for: root.appendingPathComponent("shoot/a")))
    }

    func testPartOfAFolderReadsOnlyThoseFilesUnderItsOwnIdAndIsNoRecent() async throws {
        let b = bridge()
        let (l, id) = try await handOver(b, ["shoot/a/DSC00002.ARW"], whole: false)
        XCTAssertEqual(rels(l, "files"), ["a/DSC00002.ARW"])
        XCTAssertEqual(rels(l, "xmp"), ["a/DSC00002.xmp"], "its sidecar stays, the others' go")
        XCTAssertEqual(rels(l, "others"), ["a/DSC00002.JPG"])
        let folder = SetsShootStore.id(for: root.appendingPathComponent("shoot/a"))
        XCTAssertNotEqual(id, folder)
        XCTAssertEqual(id, IngestHandoff.subsetID(place: folder, only: ["DSC00002.ARW"]))
        XCTAssertTrue(b.shoots.index().isEmpty, "no recent for a part")
        // The user then opens a folder in Pick itself: the whole of it, as always.
        b.open(root.appendingPathComponent("shoot/a"))
        let a0 = await call(b, ["op": "openFolder"])
        let again = try XCTUnwrap(a0 as? [String: Any])
        XCTAssertEqual(rels(again, "files").count, 3)
    }

    func testRefusalsComeBackAsALine() async {
        let b = bridge()
        b.ingestRoots = [root.appendingPathComponent("shoot")]
        let r = await b.ingestToPick(["elsewhere/x.ARW"], whole: true) as? [String: String]
        XCTAssertEqual(r?["refused"], IngestHandoff.Refusal.unknown.rawValue)
    }
}
