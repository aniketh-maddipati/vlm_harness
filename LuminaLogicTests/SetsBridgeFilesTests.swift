import WebKit
import XCTest
@testable import Lumina

/// Handoff's file view through the bridge (`window.lumina.files`, Prompt 27), called exactly as WebKit calls it: the shoot's
/// folder is the one place Lumina may look in here. Listings stay inside it, copies (never moves) land only inside it and
/// are read back, a rename stays in place, the search pages, Save to writes where it is told, and Show in Finder and the
/// Trash take only what they may. Temp folders only; Finder is a recorder.
@MainActor
final class SetsBridgeFilesTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var shoot: URL!
    private var outside: URL!
    private var dest: URL!
    private var shown: [[URL]] = []

    @MainActor final class Chooser: SetsChooser {
        var sources: [URL] = []
        var dest: URL?
        func chooseSource(allowsDirectories: Bool) async -> URL? { sources.isEmpty ? nil : sources.removeFirst() }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? { refusal == nil ? dest : nil }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { nil }
    }

    final class Message: WKScriptMessage {
        private let payload: Any
        init(_ payload: Any) { self.payload = payload; super.init() }
        override var body: Any { payload }
        override var name: String { "lumina" }
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sets-files-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        shoot = root.appendingPathComponent("shoot", isDirectory: true)
        outside = root.appendingPathComponent("outside", isDirectory: true)
        dest = root.appendingPathComponent("dest", isDirectory: true)
        for d in [shoot!, outside!, dest!] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        for i in 1...2 { try Data(repeating: UInt8(i), count: 4096).write(to: shoot.appendingPathComponent(String(format: "DSC%05d.ARW", i))) }
        try Data("<x:xmpmeta xmp:Rating=\"2\"/>".utf8).write(to: shoot.appendingPathComponent("DSC00001.xmp"))
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        shown = []
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func access() -> SetsAccess {
        SetsAccess(calls: SetsAccess.Calls(start: { _ in true }, stop: { _ in },
                                           resolve: { data in (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false) },
                                           bookmark: { Data($0.path.utf8) },
                                           exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }))
    }

    private func bridge() async throws -> SetsBridge {
        let chooser = Chooser()
        chooser.dest = dest
        chooser.sources = [shoot]
        let b = SetsBridge(chooser: chooser, supportDir: root.appendingPathComponent("support", isDirectory: true), access: access())
        b.reveal = { [unowned self] in shown.append([$0]) }
        b.revealAll = { [unowned self] in shown.append($0) }
        b.openInApp = { _, _ in false }
        let r = await call(b, ["op": "openFolder"])
        XCTAssertEqual((r as? [String: Any])?["name"] as? String, "shoot")
        return b
    }

    private func call(_ b: SetsBridge, _ body: [String: Any]) async -> Any? {
        await b.userContentController(WKUserContentController(), didReceive: Message(body)).0
    }

    func testPlacesNameTheShootAndListingsStayInside() async throws {
        let b = try await bridge()
        let plAnswer = await call(b, ["op": "filesPlaces"]) as? [String: Any]
        let pl = try XCTUnwrap(plAnswer)
        let places = try XCTUnwrap(pl["places"] as? [[String: Any]])
        XCTAssertTrue(places.contains { $0["kind"] as? String == "shoot" && $0["path"] as? String == shoot.path }, "\(places)")
        XCTAssertTrue(pl["saveTo"] is NSNull)
        XCTAssertEqual(pl["ask"] as? Bool, false)
        if let disk = (pl["drives"] as? [[String: Any]])?.first(where: { $0["path"] as? String == "/" }) {
            XCTAssertEqual(disk["granted"] as? String, "some", "the startup disk with the shoot's folder let in")
            let some = await call(b, ["op": "filesDirList", "path": "/"]) as? [[String: Any]]
            XCTAssertEqual(some?.compactMap { $0["path"] as? String }, [shoot.path])
        }
        let lAnswer = await call(b, ["op": "filesDirList", "path": shoot.path]) as? [[String: Any]]
        let l = try XCTUnwrap(lAnswer)
        XCTAssertEqual(l.compactMap { $0["name"] as? String }, ["DSC00001.ARW", "DSC00001.xmp", "DSC00002.ARW"])
        for p in [outside.path, root.path, shoot.path + "/../outside", "shoot", "", "/etc"] {
            let r = await call(b, ["op": "filesDirList", "path": p])
            XCTAssertTrue(r is NSNull, p)
        }
    }

    func testCopiesRenamesAndSearch() async throws {
        let b = try await bridge()
        let mkAnswer = await call(b, ["op": "filesDirMake", "parent": shoot.path, "name": "Picks"]) as? [String: Any]
        let mk = try XCTUnwrap(mkAnswer)
        XCTAssertEqual(mk["ok"] as? Bool, true)
        let picks = try XCTUnwrap(mk["path"] as? String)
        let mkOut = await call(b, ["op": "filesDirMake", "parent": outside.path, "name": "x"]) as? [String: Any]
        XCTAssertEqual(mkOut?["ok"] as? Bool, false)
        let raw = shoot.appendingPathComponent("DSC00001.ARW").path
        let items: [[String: String]] = [["from": raw, "to": picks], ["from": raw, "to": outside.path], ["from": outside.appendingPathComponent("secret.txt").path, "to": picks]]
        let cAnswer = await call(b, ["op": "filesCopyInto", "items": items]) as? [String: Any]
        let c = try XCTUnwrap(cAnswer)
        XCTAssertEqual((c["done"] as? [[String: String]])?.map { $0["to"] ?? "" }, [picks + "/DSC00001.ARW"])
        XCTAssertEqual((c["errs"] as? [Any])?.count, 2, "nothing copied outside, nothing copied from outside")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: picks + "/DSC00001.ARW")), try Data(contentsOf: URL(fileURLWithPath: raw)))
        XCTAssertTrue(fm.fileExists(atPath: picks + "/DSC00001.xmp"), "the sidecar comes with it")
        XCTAssertTrue(fm.fileExists(atPath: raw), "a copy, never a move")
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("DSC00001.ARW").path))
        // Only what Lumina wrote may go to the Trash.
        let t = await call(b, ["op": "filesTrash", "paths": [shoot.appendingPathComponent("DSC00002.ARW").path]]) as? [String: Any]
        XCTAssertEqual(t?["ok"] as? Bool, false)
        XCTAssertTrue(fm.fileExists(atPath: shoot.appendingPathComponent("DSC00002.ARW").path))
        // A folder renamed in place; never the shoot's own folder, never outside.
        let rnAnswer = await call(b, ["op": "filesDirRename", "path": picks, "name": "Keepers"]) as? [String: Any]
        let rn = try XCTUnwrap(rnAnswer)
        XCTAssertEqual(rn["path"] as? String, shoot.appendingPathComponent("Keepers").path)
        let rnShoot = await call(b, ["op": "filesDirRename", "path": shoot.path, "name": "x"]) as? [String: Any]
        let rnOut = await call(b, ["op": "filesDirRename", "path": outside.path, "name": "x"]) as? [String: Any]
        XCTAssertEqual(rnShoot?["ok"] as? Bool, false)
        XCTAssertEqual(rnOut?["ok"] as? Bool, false)
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
        let opts: [String: Any] = ["roots": [shoot.path, outside.path], "after": NSNull(), "limit": 10]
        let sAnswer = await call(b, ["op": "filesDirSearch", "q": "KEEP", "opts": opts]) as? [String: Any]
        let s = try XCTUnwrap(sAnswer)
        XCTAssertEqual((s["hits"] as? [[String: String]])?.map { $0["name"] ?? "" }, ["Keepers"])
        XCTAssertTrue(s["next"] is NSNull)
    }

    func testSaveToAFolderAndShowInFinder() async throws {
        let b = try await bridge()
        let to = shoot.appendingPathComponent("Out", isDirectory: true)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        let b64 = Data("<x:xmpmeta xmp:Rating=\"5\"/>".utf8).base64EncodedString()
        let wAnswer = await call(b, ["op": "writeSidecars", "root": "shoot", "dir": to.path, "files": [["name": "DSC00001.xmp", "b64": b64]]]) as? [String: Any]
        let w = try XCTUnwrap(wAnswer)
        XCTAssertEqual(w["n"] as? Int, 1)
        XCTAssertEqual(w["path"] as? String, to.path)
        XCTAssertEqual(try String(contentsOf: to.appendingPathComponent("DSC00001.xmp"), encoding: .utf8), "<x:xmpmeta xmp:Rating=\"5\"/>")
        XCTAssertEqual(try String(contentsOf: shoot.appendingPathComponent("DSC00001.xmp"), encoding: .utf8), "<x:xmpmeta xmp:Rating=\"2\"/>", "the sidecar beside the RAW is untouched")
        let text = await call(b, ["op": "filesSavedText", "path": to.appendingPathComponent("DSC00001.xmp").path]) as? String
        XCTAssertEqual(text, "<x:xmpmeta xmp:Rating=\"5\"/>")
        let notSaved = await call(b, ["op": "filesSavedText", "path": shoot.appendingPathComponent("DSC00001.xmp").path])
        XCTAssertTrue(notSaved is NSNull, "only what Handoff saved")
        let list: [[String: Any]] = [["id": "a", "at": Date().timeIntervalSince1970 * 1000, "paths": [to.appendingPathComponent("DSC00001.xmp").path]],
                                     ["id": "b", "at": 0, "paths": [outside.appendingPathComponent("secret.txt").path]]]
        let chk = await call(b, ["op": "filesSavedCheck", "list": list]) as? [String: String]
        XCTAssertEqual(chk, ["a": "ok", "b": "missing"], "a file outside is not looked at")
        // Outside the folders Lumina may look in: nothing written.
        let noAnswer = await call(b, ["op": "writeSidecars", "root": "shoot", "dir": outside.path, "files": [["name": "DSC00001.xmp", "b64": b64]]]) as? [String: Any]
        let no = try XCTUnwrap(noAnswer)
        XCTAssertEqual(no["n"] as? Int, 0)
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("DSC00001.xmp").path))
        // Ask each time: the panel's folder (not the shoot's, not a card).
        let askAnswer = await call(b, ["op": "writeSidecars", "root": "shoot", "ask": true, "files": [["name": "DSC00002.xmp", "b64": b64]]]) as? [String: Any]
        let ask = try XCTUnwrap(askAnswer)
        XCTAssertEqual(ask["path"] as? String, dest.path)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("DSC00002.xmp").path))
        // Show in Finder: only inside.
        let r = await call(b, ["op": "filesReveal", "paths": [to.path, outside.path]]) as? [String: Any]
        XCTAssertEqual(r?["n"] as? Int, 1)
        XCTAssertEqual(shown.last?.map(\.path), [to.path])
        let r2 = await call(b, ["op": "filesReveal", "paths": [outside.path]]) as? [String: Any]
        XCTAssertEqual(r2?["ok"] as? Bool, false)
    }
}
