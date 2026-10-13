import CryptoKit
import WebKit
import XCTest
@testable import Lumina

/// Threat model T1 / T8, stress matrix 7 (Q4): every op of the page's `lumina` message handler,
/// called through `SetsBridge.userContentController(_:didReceive:)` exactly as WebKit calls it,
/// with wrong types, missing fields, 10 MB strings, `..`, absolute paths, NUL bytes, non-hex shoot
/// ids, negative, huge and non-finite numbers.
///
/// Holds: the test process survives every call; nothing is written outside the run's temp folder
/// (and inside it, only to the store, the export destination the chooser hands back, or a `.xmp`
/// beside its RAW); no byte of the canaries outside the opened folder is read back to the page;
/// refusals come back as refusals (false / null / 0 / an error), never as a success.
///
/// Open findings are marked `XCTExpectFailure` with the task that fixes them, so the table stays
/// green on main and goes on checking everything else. `reveal` (F8) was one until S4: it is an
/// ordinary case now, with `testRevealOnlyInsideOpenedFoldersAndTheLastExport`. The numbers that used to stop the app
/// process (Q4-hostile F1, F2: `Int(_:)` on a non-finite or huge double) are ordinary cases now:
/// every number the page sends is read through `SetsNumber` (`docs/release/stress/Q4-hostile.md`).
///
/// Temp folders only. `openSettings` is not called (it opens System Settings on the desktop);
/// `reveal` goes to a recorder, never Finder; `setPrefs` writes the host app's defaults and the
/// test puts the value it found back.
@MainActor
final class SetsBridgeOpsTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var support: URL!
    private var shoot: URL!
    private var outside: URL!
    private var dest: URL!
    private var marker = ""
    private var savedPrefs: Any?
    private var revealed: [URL] = []

    /// Answers the folder panel from a queue and the export panel with `dest` (nil = Cancel).
    @MainActor final class Chooser: SetsChooser {
        var sources: [URL] = []
        var dest: URL?
        var destinationAsks = 0
        func chooseSource(allowsDirectories: Bool) async -> URL? { sources.isEmpty ? nil : sources.removeFirst() }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? {
            destinationAsks += 1
            return destinationAsks > 3 ? nil : dest            // a refusal loop ends as Cancel
        }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { nil }
    }

    /// What WebKit hands the bridge: only `body` (and the handler's name) is read.
    final class Message: WKScriptMessage {
        private let payload: Any
        init(_ payload: Any) { self.payload = payload; super.init() }
        override var body: Any { payload }
        override var name: String { "lumina" }
    }

    static let tenMB = String(repeating: "A", count: 10 << 20)
    static let canary = "CANARY-OUTSIDE-THE-SHOOT"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sets-ops-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        support = root.appendingPathComponent("support", isDirectory: true)
        shoot = root.appendingPathComponent("shoot", isDirectory: true)
        outside = root.appendingPathComponent("outside", isDirectory: true)
        dest = root.appendingPathComponent("dest", isDirectory: true)
        marker = "LUMINA-HOSTILE-\(UUID().uuidString.prefix(8))"
        for d in [support!, shoot!, outside!, dest!] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        for i in 1...2 { try Data(repeating: UInt8(i), count: 4096).write(to: shoot.appendingPathComponent(String(format: "DSC%05d.ARW", i))) }
        try Data("<x:xmpmeta xmp:Rating=\"2\"/>".utf8).write(to: shoot.appendingPathComponent("DSC00001.xmp"))
        try Data("<x:xmpmeta>\(Self.canary)</x:xmpmeta>".utf8).write(to: outside.appendingPathComponent("victim.xmp"))
        try Data(repeating: 9, count: 4096).write(to: outside.appendingPathComponent("DSC09999.ARW"))
        try Data(Self.canary.utf8).write(to: outside.appendingPathComponent("secret.txt"))
        savedPrefs = UserDefaults.standard.object(forKey: SetsBridge.prefsKey)
        revealed = []
    }

    override func tearDownWithError() throws {
        if let savedPrefs { UserDefaults.standard.set(savedPrefs, forKey: SetsBridge.prefsKey) } else { UserDefaults.standard.removeObject(forKey: SetsBridge.prefsKey) }
        try? fm.removeItem(at: root)
        for t in ["/tmp", "/private/tmp", fm.temporaryDirectory.path] { try? fm.removeItem(atPath: t + "/" + marker) }
    }

    // MARK: Harness

    private func access() -> SetsAccess {
        SetsAccess(calls: SetsAccess.Calls(start: { _ in true }, stop: { _ in },
                                           resolve: { data in (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false) },
                                           bookmark: { Data($0.path.utf8) },
                                           exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }))
    }

    /// A bridge with `shoot` opened through the page's own op (listed, registered, shoot id taken).
    private func bridge(opened: Bool = true, canvas: Bool = true) async throws -> (SetsBridge, Chooser) {
        let chooser = Chooser()
        chooser.dest = dest
        let b = SetsBridge(chooser: chooser, supportDir: support, access: access())
        b.reveal = { [unowned self] in revealed.append($0) }
        // The image path (no host view): the controller and its schedule, without a window.
        if canvas { b.attachCanvas(host: nil) }
        if opened {
            chooser.sources = [shoot]
            let (r, e) = await call(b, ["op": "openFolder"])
            XCTAssertNil(e)
            XCTAssertEqual((r as? [String: Any])?["name"] as? String, "shoot")
            let (s, _) = await call(b, ["op": "shootOpened", "name": "shoot", "n": 2, "date": "2026:09:08 10:00:00"])
            XCTAssertNotNil((s as? [String: Any])?["id"] as? String)
        }
        return (b, chooser)
    }

    private func call(_ b: SetsBridge, _ body: Any) async -> (Any?, String?) {
        await b.userContentController(WKUserContentController(), didReceive: Message(body))
    }

    /// Every file under the run's folder outside the store and the export destination, by hash.
    private func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        let e = fm.enumerator(atPath: root.path)
        while let p = e?.nextObject() as? String {
            if p.hasPrefix("support/") || p.hasPrefix("dest/") || p == "support" || p == "dest" { continue }
            let u = root.appendingPathComponent(p)
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            out[p] = (try? Data(contentsOf: u)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "?"
        }
        return out
    }

    /// Files whose name carries this run's marker, anywhere a hostile path could have put one.
    private func strays() -> [String] {
        var hits: [String] = []
        for dir in [root.path, root.deletingLastPathComponent().path, "/tmp", "/private/tmp", NSHomeDirectory()] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.contains(marker) { hits.append(dir + "/" + name) }
        }
        let e = fm.enumerator(atPath: root.path)
        while let p = e?.nextObject() as? String { if p.contains(marker) && !p.hasPrefix("dest/") { hits.append(root.path + "/" + p) } }
        return hits
    }

    /// The hostile values every field is fed, by name.
    private func values() -> [(String, Any)] {
        [("null", NSNull()), ("int", 42), ("negative", -1), ("intMax", Int.max), ("intMin", Int.min), ("huge", 1e308),
         ("bool", true), ("empty", ""), ("dotdot", "../../outside/\(marker)"), ("climb", "shoot/../../../../../../../../tmp/\(marker)"),
         ("absolute", outside.appendingPathComponent(marker).path), ("absoluteFile", outside.appendingPathComponent("secret.txt").path),
         ("nul", "shoot/DSC00001.ARW\u{0}.xmp"), ("tenMB", Self.tenMB), ("nonHexId", "zzzzzzzzzzzzzzzz"), ("upperHexId", "0123456789ABCDEF"),
         ("dotdotId", "../../../outside"), ("array", [1, "a", NSNull()]), ("dict", ["a": 1, "o": -5]), ("rtl", "\u{202E}gpj.exe"),
         ("newline", "a\nb\r\n<img src=x onerror=alert(1)>"), ("emoji", "📷🔥" + marker)]
    }

    /// Non-finite and out-of-range doubles: JS sends these (Infinity, NaN, 1e300) as easily as 1.
    private func numbers() -> [(String, Any)] { [("inf", Double.infinity), ("negInf", -Double.infinity), ("nan", Double.nan), ("1e300", 1e300), ("negZero", -0.0)] }

    /// The fields each op reads (SetsBridge.swift, `userContentController`). `openSettings` is left
    /// out on purpose (it opens System Settings).
    static let fields: [String: [String]] = [
        "ready": ["missing"], "cullCard": [], "openFolder": [], "prefetch": ["items"], "near": ["a", "b"], "auto": ["rel"], "ingestStats": [],
        "shootOpened": ["name", "n", "date", "bodies"], "shootHeader": [], "decoderUpdate": [],
        "canvasEnter": ["rel", "model", "look", "prev", "next", "preview", "prevPreview", "nextPreview"], "canvasLeave": [],
        "canvasLayout": ["x", "y", "w", "h", "visible", "dpr", "holes"], "canvasLook": ["look", "drag", "key", "roi", "t", "seq"],
        "canvasDrag": ["start"], "canvasLoupe": ["on", "roi"], "canvasStats": ["reset"],
        "saveSession": ["id", "json", "summary"], "recents": [], "reopen": ["id"], "workingFiles": ["id"], "removeShoot": ["id"],
        "writeInto": ["label", "files"], "readSidecars": ["root", "files"], "writeSidecars": ["root", "files"], "reveal": ["path"],
        "setPrefs": ["prefs"], "checkAccess": [], "reopenDenied": [], "reopenCurrent": [],
    ]

    // MARK: The table

    /// Every op × every field × every hostile value, one field at a time, the others valid.
    func testEveryOpEveryFieldEveryHostileValue() async throws {
        let (b, chooser) = try await bridge()
        let id = try XCTUnwrap(b.shootId)
        let before = snapshot()
        var calls = 0
        var violations: [String] = []
        // Valid values for the fields not under test, so a hostile one is the only thing wrong.
        let good: [String: Any] = ["id": id, "json": "{}", "name": "shoot", "root": "shoot", "rel": "shoot/DSC00001.ARW", "path": "shoot/DSC00001.ARW",
                                   "look": "ev:+0.30", "files": [] as [Any], "items": [] as [Any], "label": "Hostile", "prefs": ["rating": 3]]
        // Per op, where the op needs a real rect to reach the field.
        let goodFor: [String: [String: Any]] = [
            "canvasLayout": ["x": 100, "y": 50, "w": 400, "h": 300, "visible": true, "dpr": 2, "holes": [["x": 120, "y": 60, "w": 50, "h": 20]]],
        ]
        for (op, fields) in Self.fields.sorted(by: { $0.key < $1.key }) {
            // Missing everything, and the op alone with a wrong-typed op name next to it.
            for body in [["op": op], ["op": op, "op2": NSNull()]] as [[String: Any]] {
                _ = await call(b, body); calls += 1
            }
            for field in fields {
                for (name, v) in values() + numbers() {
                    var body: [String: Any] = ["op": op]
                    for f in fields where f != field { if let g = goodFor[op]?[f] ?? good[f] { body[f] = g } }
                    body[field] = v
                    chooser.destinationAsks = 0
                    let (r, e) = await call(b, body); calls += 1
                    if let why = refusalBroken(op: op, field: field, value: v, result: r, error: e) { violations.append("\(op).\(field)=\(name): \(why)") }
                    let now = snapshot()
                    if now != before {
                        violations.append("\(op).\(field)=\(name): files outside the store changed: \(Set(now.keys).symmetricDifference(before.keys).sorted()) / \(now.filter { before[$0.key] != $0.value }.keys.sorted())")
                        break
                    }
                }
            }
        }
        // The whole message wrong: not a dictionary, no op, an unknown op, a 10 MB op.
        for body in [NSNull(), "ready", 42, [1, 2], ["no-op": 1], ["op": 42], ["op": "nope"], ["op": Self.tenMB]] as [Any] {
            let (r, e) = await call(b, body); calls += 1
            if r != nil, !(r is NSNull) { violations.append("bad message \(type(of: body)) answered \(String(describing: r).prefix(80))") }
            XCTAssertNotNil(e)
        }
        print("SetsBridgeOpsTests: \(calls) calls, \(Self.fields.count) ops, \(values().count + numbers().count) hostile values per field")
        XCTAssertEqual(strays(), [], "a hostile path wrote outside the run's folder")
        XCTAssertEqual(snapshot(), before, "the shoot and the canaries are unchanged")
        // Includes `reveal` (T8 · S4, Q4 finding F8): nothing outside the opened folder is shown.
        XCTAssertEqual(violations, [], "refusals answered as refusals")
    }

    /// What a refusal looks like, per op, when `field` holds a hostile value. nil = fine.
    private func refusalBroken(op: String, field: String, value v: Any, result r: Any?, error e: String?) -> String? {
        let truthy = (r as? Bool) == true
        switch (op, field) {
        case ("saveSession", "id"), ("removeShoot", "id"), ("reopen", "id"):
            return truthy ? "accepted a hostile id" : nil
        case ("workingFiles", "id"):
            return ((r as? Int64) ?? Int64((r as? Int) ?? 0)) != 0 ? "sized a hostile id" : nil
        case ("saveSession", "json"):
            return truthy && !(v is String) ? "stored a session that is not a string" : nil
        case ("readSidecars", "root"), ("writeSidecars", "root"):
            return r != nil && !(r is NSNull) ? "answered for a root that is not an opened folder" : nil
        case ("reveal", "path"):
            guard let url = revealed.popLast() else { return truthy ? "answered true and showed nothing" : nil }
            if !truthy { return "showed \(url.path) and answered false" }
            return url.path == shoot.path || url.path.hasPrefix(shoot.path + "/") ? nil : "revealed \(url.path)"
        case ("canvasEnter", "rel"):
            return e == nil ? "entered a hostile rel" : nil
        case ("auto", "rel"):
            // lumina.auto: the only RAW-shaped rel in the table is a 4 KB junk file Core Image can't develop.
            return r != nil && !(r is NSNull) ? "an Auto for a hostile rel" : nil
        default:
            return nil
        }
    }

    // MARK: Structured payloads: files, previews, rects

    /// Save with hostile sidecar names: nothing but a `.xmp` beside its RAW inside the shoot.
    func testWriteSidecarsHostileNames() async throws {
        let (b, _) = try await bridge(canvas: false)
        let before = snapshot()
        let b64 = Data("<x:xmpmeta xmp:Rating=\"5\"/>".utf8).base64EncodedString()
        let names = ["../outside/victim.xmp", "../outside/\(marker).xmp", outside.appendingPathComponent("victim.xmp").path, "/tmp/\(marker).xmp",
                     "DSC00001.ARW", "DSC00002.arw", "DSC00001.ARW\u{0}.xmp", "DSC00002\u{0}.xmp", "./DSC00001.xmp", "sub/../DSC00001.xmp", "",
                     "DSC00001.xmp/", ".xmp", "..xmp", String(repeating: "x", count: 300) + ".xmp", Self.tenMB + ".xmp", "DSC09999.xmp",
                     "\u{202E}pmx.DSC00002", "DSC00002.XMP\n", "<img src=x onerror=alert(1)>.xmp"]
        var files: [[String: Any]] = names.map { ["name": $0, "b64": b64] }
        files.append(["name": 42, "b64": b64]); files.append(["name": "DSC00002.xmp", "b64": 42]); files.append(["name": "DSC00002.xmp", "b64": "!!!not base64"])
        files.append(["name": "DSC00002.xmp", "b64": b64, "base": Self.tenMB])
        let (r, _) = await call(b, ["op": "writeSidecars", "root": "shoot", "files": files])
        let out = try XCTUnwrap(r as? [String: Any])
        print("writeSidecars hostile:", out["n"] ?? "?", "written,", (out["errors"] as? [[String: String]] ?? []).map { "\($0["name"]?.prefix(40) ?? "") · \($0["reason"] ?? "")" })
        XCTAssertEqual(strays(), [])
        // Only the shoot's own sidecars may have changed or appeared; the RAWs and the canaries never.
        let now = snapshot()
        for (p, h) in before where !p.hasSuffix(".xmp") || p.hasPrefix("outside/") { XCTAssertEqual(now[p], h, "\(p) changed") }
        for p in now.keys where before[p] == nil {
            XCTAssertTrue(p.hasPrefix("shoot/") && (p.lowercased().hasSuffix(".xmp") || p.hasSuffix(SetsFileOps.backupSuffix)), "unexpected new file \(p.debugDescription)")
            let stem = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            XCTAssertTrue(p.hasSuffix(SetsFileOps.backupSuffix) || SetsFileOps.hasRaw(named: stem, in: shoot), "a sidecar with no RAW beside it: \(p.debugDescription)")
        }
    }

    /// The pre-save read never hands back a byte from outside the opened folder.
    func testReadSidecarsStaysInside() async throws {
        let (b, _) = try await bridge(canvas: false)
        let rels = ["../outside/victim.xmp", outside.appendingPathComponent("victim.xmp").path, "./../outside/victim.xmp", "DSC00001.xmp\u{0}/../../outside/victim.xmp",
                    "../outside/secret.txt", "../../../../../../../../etc/hosts", "/etc/hosts", Self.tenMB, "", "DSC00001.xmp"]
        let (r, _) = await call(b, ["op": "readSidecars", "root": "shoot", "files": rels])
        let list = try XCTUnwrap(r as? [[String: Any]])
        XCTAssertEqual(list.count, rels.count)
        for item in list {
            let text = item["text"] as? String ?? ""
            XCTAssertFalse(text.contains(Self.canary), "read outside the shoot: \(String(describing: item["name"]).prefix(80))")
            XCTAssertFalse(text.contains("localhost"), "read /etc/hosts")
        }
        XCTAssertEqual(list.last?["text"] as? String, "<x:xmpmeta xmp:Rating=\"2\"/>", "the shoot's own sidecar still reads")
    }

    /// Export with hostile names and sources: written only into the destination, or refused.
    /// Since S4 an export takes sidecar bytes named `.xmp` and look renders named as images:
    /// every other name, and v3's `src` (copy) and `jpg` (CSS look) items, write nothing.
    func testWriteIntoHostileFiles() async throws {
        let (b, chooser) = try await bridge(canvas: false)
        let before = snapshot()
        let bytes = Data("x".utf8).base64EncodedString()
        let cases: [[String: Any]] = [
            ["name": "../\(marker).txt", "b64": bytes], ["name": "/tmp/\(marker).txt", "b64": bytes], ["name": "a/../../\(marker)", "b64": bytes],
            ["name": "../\(marker).xmp", "b64": bytes], ["name": "/tmp/\(marker).xmp", "b64": bytes], ["name": "a/../../\(marker).xmp", "b64": bytes],
            ["name": "\(marker)\u{0}.txt", "b64": bytes], ["name": "\(marker).txt\u{0}.xmp", "b64": bytes], ["name": "\(marker).xmp\u{0}.txt", "b64": bytes],
            ["name": "sub/\(marker).txt", "b64": bytes], ["name": Self.tenMB, "b64": bytes], ["name": Self.tenMB + ".xmp", "b64": bytes],
            ["name": String(repeating: "é", count: 200), "b64": bytes], ["name": "\(marker).copy", "src": "../outside/secret.txt"],
            ["name": "\(marker).copy", "src": outside.appendingPathComponent("secret.txt").path], ["name": "\(marker).ARW", "src": "shoot/DSC00001.ARW"],
            ["name": "\(marker).jpg", "jpg": ["src": "/etc/hosts", "css": Self.tenMB]], ["name": "\(marker).jpg", "jpg": ["src": "shoot/DSC00001.ARW", "css": "none"]],
            ["name": "\(marker).jpg", "look": ["src": "shoot/../outside/DSC09999.ARW", "look": "ev:+1", "px": -1]],
            ["name": "\(marker).sh", "look": ["src": "shoot/DSC00001.ARW", "look": "ev:+1"]], ["name": "\(marker)", "look": ["src": "shoot/DSC00001.ARW", "look": ""]],
            ["name": "\(marker).bin", "b64": 42], ["name": 7, "b64": bytes], ["name": "\(marker)-ok.txt", "b64": bytes], ["name": "\(marker).xmp.app", "b64": bytes],
            ["name": "\(marker)-ok.xmp", "b64": bytes], ["name": "sub/\(marker)-ok.XMP", "b64": bytes],
        ]
        var outcomes: [String] = []
        for c in cases {
            chooser.destinationAsks = 0
            let (r, _) = await call(b, ["op": "writeInto", "label": Self.tenMB.prefix(1000) + "<img src=x onerror=alert(1)>", "files": [c]])
            outcomes.append(String(describing: (r as? [String: Any])?["say"] ?? (r as? [String: Any])?["n"] ?? r).prefix(120).description)
        }
        print("writeInto hostile:", outcomes)
        XCTAssertEqual(strays(), [], "an export name led out of the destination")
        XCTAssertEqual(snapshot(), before)
        let written = (fm.enumerator(atPath: dest.path)?.compactMap { $0 as? String } ?? []).filter { p in
            (try? dest.appendingPathComponent(p).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        let leaked = written.filter { p in
            let full = dest.appendingPathComponent(p)
            return (try? String(contentsOf: full, encoding: .utf8))?.contains(Self.canary) == true
        }
        XCTAssertEqual(leaked, [], "a copy from outside the opened folders")
        // On disk, as the file system names them: only the two sidecars, nothing with another extension.
        XCTAssertEqual(written.sorted(), ["\(marker)-ok.xmp", "sub/\(marker)-ok.XMP"], "only .xmp bytes land in the destination")
    }

    /// S4 (threat model T8): what an export takes. Look renders named .jpg / .jpeg / .tif / .tiff /
    /// .png and bytes named .xmp; v3's `src` and `jpg` items are refused before a folder is asked for.
    func testWriteIntoTakesOnlyLookRendersAndSidecarBytes() async throws {
        let (b, chooser) = try await bridge(canvas: false)
        let before = snapshot()
        let bytes = Data("<x:xmpmeta/>".utf8).base64EncodedString()
        func export(_ file: [String: Any]) async -> [String: Any] {
            ((await call(b, ["op": "writeInto", "label": "jpeg", "files": [file]])).0 as? [String: Any]) ?? [:]
        }
        // A source outside the opened folder: an image name gets as far as the path check
        // ("can't find"), any other name stops at the name.
        let outsideLook: [String: Any] = ["src": "shoot/../outside/DSC09999.ARW", "look": "ev:+0.30"]
        for ext in ["jpg", "JPG", "jpeg", "tif", "tiff", "png"] {
            let r = await export(["name": "JPEG/DSC00001.\(ext)", "look": outsideLook])
            XCTAssertEqual(r["aborted"] as? Bool, true, ext)
            XCTAssertTrue((r["say"] as? String ?? "").contains("can't find"), "\(ext): \(r)")
        }
        for name in ["DSC00001.xmp", "DSC00001.ARW", "DSC00001.txt", "DSC00001.jpg.sh", "DSC00001", "DSC00001.heic", "DSC00001.jpg\u{0}.sh"] {
            let r = await export(["name": name, "look": ["src": "shoot/DSC00001.ARW", "look": "ev:+0.30"]])
            XCTAssertEqual(r["say"] as? String, "export stopped · bad file name", name.debugDescription)
        }
        for name in ["DSC00001.jpg", "DSC00001.ARW", "DSC00001.txt", "DSC00001", "DSC00001.xmp.sh", "DSC00001.sh\u{0}.xmp"] {
            let r = await export(["name": name, "b64": bytes])
            XCTAssertEqual(r["say"] as? String, "export stopped · bad file name", name.debugDescription)
        }
        // v3's items: a RAW copied out, the CSS look. Not items any more, whatever they name.
        for file in [["name": "RAW/DSC00001.ARW", "src": "shoot/DSC00001.ARW"], ["name": "DSC00001.jpg", "jpg": ["src": "shoot/DSC00001.ARW", "css": "none", "px": "full"]],
                     ["name": "DSC00001.xmp"], ["name": "DSC00001.xmp", "b64": "!!!not base64"]] as [[String: Any]] {
            let r = await export(file)
            XCTAssertEqual(r["aborted"] as? Bool, true, "\(file)")
            XCTAssertNil(r["n"], "\(file)")
        }
        XCTAssertEqual(chooser.destinationAsks, 0, "nothing refused got as far as the folder panel")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dest.path), [])
        // Sidecar bytes still land, in the folder the user picks.
        let ok = await export(["name": "DSC00001.xmp", "b64": bytes])
        XCTAssertEqual(ok["n"] as? Int, 1, "\(ok)")
        XCTAssertEqual(chooser.destinationAsks, 1)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dest.path), ["DSC00001.xmp"])
        XCTAssertEqual(snapshot(), before)
    }

    /// S4 (Q4 finding F8): Show in Finder opens an opened folder, something inside one, or the
    /// last export's folder. Any other path answers false and shows nothing; there is no
    /// fallback to the open folder.
    func testRevealOnlyInsideOpenedFoldersAndTheLastExport() async throws {
        let (b, _) = try await bridge(canvas: false)
        let sibling = root.appendingPathComponent("shoot2", isDirectory: true)       // "…/shoot" is a prefix of its path
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: shoot.appendingPathComponent("link.txt"), withDestinationURL: outside.appendingPathComponent("secret.txt"))
        func reveal(_ path: Any) async -> (ok: Bool, url: URL?) {
            revealed = []
            let (r, e) = await call(b, ["op": "reveal", "path": path])
            XCTAssertNil(e)
            return (r as? Bool == true, revealed.last)
        }
        let raw = shoot.appendingPathComponent("DSC00001.ARW")
        for (path, want) in [("shoot", shoot!), ("shoot/DSC00001.ARW", raw), (shoot.path, shoot!), (shoot.path + "/", shoot!), (raw.path, raw)] as [(String, URL)] {
            let r = await reveal(path)
            XCTAssertTrue(r.ok, path)
            XCTAssertEqual(r.url?.resolvingSymlinksInPath().path, want.path, path)
        }
        let refused: [Any] = ["", "nope", "DSC00001.ARW", "~/Pictures/shoot", "shoot/../outside/secret.txt", "../outside/secret.txt", "shoot/link.txt", "shoot/missing.ARW",
                              outside.path, outside.appendingPathComponent("secret.txt").path, shoot.path + "/../outside/secret.txt", shoot.path + "/link.txt",
                              shoot.path + "/missing.ARW", sibling.path, root.path, dest.path, support.path, "/", "/etc/hosts", "/Applications", NSHomeDirectory(),
                              42, NSNull(), ["shoot"], Self.tenMB, "/" + Self.tenMB]
        for path in refused {
            let r = await reveal(path)
            XCTAssertFalse(r.ok, "\(String(describing: path).prefix(120))")
            XCTAssertNil(r.url, "\(String(describing: path).prefix(120))")
        }
        // After an export the folder the user picked for it, and what is in it; still nothing else.
        let bytes = Data("<x:xmpmeta/>".utf8).base64EncodedString()
        let (out, _) = await call(b, ["op": "writeInto", "label": "jpeg", "files": [["name": "DSC00001.xmp", "b64": bytes]]])
        XCTAssertEqual((out as? [String: Any])?["n"] as? Int, 1)
        for url in [dest!, dest.appendingPathComponent("DSC00001.xmp")] {
            let r = await reveal(url.path)
            XCTAssertTrue(r.ok, url.path)
            XCTAssertEqual(r.url?.resolvingSymlinksInPath().path, url.path)
        }
        for path in [outside.path, root.path, support.path, dest.path + "/../outside/secret.txt", "/etc/hosts"] {
            let r = await reveal(path)
            XCTAssertFalse(r.ok, path)
            XCTAssertNil(r.url, path)
        }
    }

    /// Previews named by the page (prefetch, near, canvasEnter): offsets and lengths of every kind.
    func testHostilePreviewRanges() async throws {
        let (b, _) = try await bridge()
        let ranges: [(Any, Any)] = [(0, 0), (-1, 10), (10, -1), (Int.max, 10), (1, Int.max), (1, 2 << 30), (Int.max, Int.max), ("12", "x"), (1e308, 1e308), (Double.nan, Double.infinity), (NSNull(), NSNull()), (4000, 4096)]
        var items: [[String: Any]] = []
        for (o, l) in ranges { for p in ["shoot/DSC00001.ARW", "../outside/DSC09999.ARW", "shoot/../outside/DSC09999.ARW", "/etc/hosts", "shoot/\u{0}"] { items.append(["p": p, "o": o, "l": l, "ori": [0, 6, 65535, -3, Double.nan][items.count % 5]]) } }
        let (n, _) = await call(b, ["op": "prefetch", "items": items])
        XCTAssertEqual(n as? Int, items.count)
        // 10,000 junk items in one call: accepted and dropped, not held.
        _ = await call(b, ["op": "prefetch", "items": (0..<10_000).map { ["p": "shoot/x\($0)", "o": $0 + 1, "l": 64 << 20] }])
        for (i, a) in items.enumerated() where i % 7 == 0 {
            let (d, _) = await call(b, ["op": "near", "a": a, "b": items[(i + 3) % items.count]])
            XCTAssertTrue(d == nil || d is NSNull, "a distance for a hostile preview pair \(a)")
        }
        for a in items.prefix(12) {
            _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "preview": a, "prev": "../outside/DSC09999.ARW", "prevPreview": a, "next": a, "look": Self.tenMB])
        }
        _ = await call(b, ["op": "canvasLeave"])
        try await Task.sleep(nanoseconds: 500_000_000)       // the prefetch queue has run its reads
        let stats = b.ingest.snapshot
        XCTAssertLessThanOrEqual(stats.largestRead, SetsIngest.headBytes, "no read past a 4 KB file's end, no 2 GB buffer")
        XCTAssertEqual(stats.opensAfterGone, 0)
    }

    /// `lumina.auto` (BRIDGE-v0.02 §1): only a RAW inside an opened folder is measured; anything else
    /// is null without a decode. A RAW that can't be developed is null too, and decoded once, not on every ask.
    func testAutoMeasuresOnlyRawsInsideTheShoot() async throws {
        let (b, _) = try await bridge(canvas: false)
        let rels: [Any] = ["shoot/DSC00001.ARW", "shoot/DSC00001.ARW", "shoot/DSC00001.xmp", "../outside/DSC09999.ARW", "shoot/../outside/DSC09999.ARW",
                           outside.appendingPathComponent("DSC09999.ARW").path, "outside/DSC09999.ARW", "shoot/NOPE.ARW", "", "shoot/DSC00001.ARW\u{0}",
                           Self.tenMB, 42, Double.nan, true, NSNull(), ["shoot/DSC00001.ARW"], ["rel": "shoot/DSC00001.ARW"]]
        for rel in rels {
            let (r, e) = await call(b, ["op": "auto", "rel": rel])
            XCTAssertNil(e)
            XCTAssertTrue(r == nil || r is NSNull, "an Auto for \(String(describing: rel).prefix(60))")
        }
        let (none, _) = await call(b, ["op": "auto"])
        XCTAssertTrue(none == nil || none is NSNull)
        XCTAssertEqual(b.auto.measured, 1, "only the shoot's own ARW reached a decode, once (its failure is cached)")
    }

    /// `canvasLayout`'s `holes` (the page's chrome over the photo): up to 16 `{x, y, w, h}`; 10,000 of
    /// them, and members that are not rects, answer like any layout and leave the canvas as it was.
    /// On the image path and on the native canvas (a Metal view in a host view).
    func testHostileCanvasHoles() async throws {
        let (img, _) = try await bridge()
        let (nat, _) = try await bridge(canvas: false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        nat.attachCanvas(host: host)
        let rect = CGRect(x: 100, y: 50, width: 400, height: 300)
        let valid: [String: Any] = ["x": 120, "y": 60, "w": 50, "h": 20]
        let many: [[String: Any]] = (0..<10_000).map { ["x": 100 + $0 % 300, "y": 50 + $0 % 200, "w": 30, "h": 10] }
        XCTAssertEqual(LookCanvasHoles.parse(many, in: rect).count, LookCanvasHoles.maxCount, "10,000 holes: the first 16 are read")
        var deep: Any = [Any]()
        for _ in 0..<1000 { deep = [deep] }
        let nums: [Any] = [Double.nan, Double.infinity, -Double.infinity, 1e308, -1e308, Int.max, Int.min, "12", true, NSNull(), [1], ["a": 1], -50, 0]
        let numNames = ["nan", "inf", "-inf", "1e308", "-1e308", "intMax", "intMin", "string", "bool", "null", "array", "dict", "negative", "zero"]
        var lists: [(String, Any)] = [("10,000 holes", many), ("10,000 non-rects", [Any](repeating: 7, count: 10_000)), ("not a list", "holes"), ("dict", ["x": 1]),
                                      ("nested arrays", [[1, 2, 3, 4], [[valid]], [[], [[]]]]), ("deep nest", deep), ("members", ["x", 42, NSNull(), [valid], true] as [Any]),
                                      ("huge string", [["x": Self.tenMB, "y": Self.tenMB, "w": Self.tenMB, "h": Self.tenMB]])]
        for field in ["x", "y", "w", "h"] {
            for (n, v) in zip(numNames, nums) {
                var h = valid; h[field] = v
                lists.append(("\(field)=\(n)", [h, valid]))
            }
        }
        lists.append(("every number hostile", nums.map { ["x": $0, "y": $0, "w": $0, "h": $0] }))
        for (name, holes) in lists {
            for b in [img, nat] {
                let (r, e) = await call(b, ["op": "canvasLayout", "x": 100, "y": 50, "w": 400, "h": 300, "dpr": 2, "visible": true, "holes": holes])
                XCTAssertNil(e, name)
                XCTAssertNotNil((r as? [String: Any])?["path"], name)
            }
            let kept = LookCanvasHoles.parse(holes, in: rect)
            XCTAssertLessThanOrEqual(kept.count, LookCanvasHoles.maxCount, name)
            for k in kept { XCTAssertTrue(CGRect(origin: .zero, size: rect.size).contains(k) && k.width > 0 && k.height > 0, "\(name): \(k)") }
        }
        // A hostile list on a rect that is itself refused: hidden, no holes read.
        let (r, e) = await call(nat, ["op": "canvasLayout", "x": Double.nan, "y": 0, "w": 400, "h": 300, "dpr": 2, "visible": true, "holes": many])
        XCTAssertNil(e)
        XCTAssertNotNil((r as? [String: Any])?["path"])
        let (s, _) = await call(nat, ["op": "canvasStats"])
        XCTAssertNotNil((s as? [String: Any])?["path"], "the stats still encode")
        _ = await call(nat, ["op": "canvasLayout", "x": 0, "y": 0, "w": 0, "h": 0, "visible": false])
        _ = await call(img, ["op": "canvasLeave"]); _ = await call(nat, ["op": "canvasLeave"])
    }

    /// Canvas rects and regions with non-finite and huge numbers, on the image path.
    func testHostileCanvasGeometry() async throws {
        let (b, _) = try await bridge()
        _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "look": ""])
        let nums: [Any] = [Double.infinity, -Double.infinity, Double.nan, 1e308, -1e308, -1, 0, Int.max, "12", NSNull()]
        for v in nums {
            _ = await call(b, ["op": "canvasLayout", "x": v, "y": v, "w": v, "h": v, "dpr": v, "visible": true])
            _ = await call(b, ["op": "canvasLook", "look": "ev:+0.5", "roi": ["x": v, "y": v, "w": v, "h": v], "t": v, "drag": true])
            _ = await call(b, ["op": "canvasLoupe", "on": true, "roi": ["x": v, "y": v, "w": v, "h": v]])
            _ = await call(b, ["op": "canvasLoupe", "on": false])
        }
        let (s, _) = await call(b, ["op": "canvasStats", "reset": true])
        XCTAssertNotNil(s as? [String: Any])
        _ = await call(b, ["op": "canvasLeave"])
    }

    /// shootOpened stores what the page says about the shoot in the recents index.
    func testShootOpenedFieldsAreBounded() async throws {
        let (b, _) = try await bridge(canvas: false)
        _ = await call(b, ["op": "shootOpened", "name": "shoot", "n": Int.max, "date": Self.tenMB, "bodies": ["ILCE": "../outside/DSC09999.ARW", Self.tenMB: "shoot/DSC00001.ARW"]])
        let index = support.appendingPathComponent("shoots/index.json")
        let size = (try? index.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        print("index.json after a 10 MB date: \(size) bytes")
        let (recents, _) = await call(b, ["op": "recents"])
        XCTAssertEqual((recents as? [[String: Any]])?.count, 1)
        XCTAssertLessThan(size, 1 << 20, "the recents index stays small whatever the page sends")
        XCTAssertEqual((recents as? [[String: Any]])?.first?["d"] as? String, String(repeating: "A", count: SetsShootStore.Cap.date), "the date is cut at the cap")
        // The summary's `last` goes the same way, on every saved session.
        let id = try XCTUnwrap(b.shootId)
        let (saved, _) = await call(b, ["op": "saveSession", "id": id, "json": "{}", "summary": ["n": 2, "dec": 1, "kp": 1, "last": Self.tenMB]])
        XCTAssertEqual(saved as? Bool, true)
        let after = (try? index.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        XCTAssertLessThan(after, 1 << 20, "a 10 MB `last` is cut too (index.json is \(after) bytes)")
        XCTAssertEqual(SetsShootStore(supportDir: support).index().first?.last?.count, SetsShootStore.Cap.name)
        // A 10 MB model name is not a body: never measured, never kept in the shoot's header.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(b.header.bodies.keys.allSatisfy { $0.utf8.count <= SetsBridge.maxModelBytes }, "no body under a 10 MB name")
        let header = support.appendingPathComponent("shoots/\(id)/\(LookShootHeader.fileName)")
        XCTAssertLessThan((try? header.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0, 1 << 20)
    }

    // MARK: Numbers (Q4a: F1, F2)

    /// `SetsNumber`: what every numeric field of a message and every query number is read with.
    func testNumbersFromThePageAreFiniteAndInRange() {
        let hostile: [Any] = [Double.infinity, -Double.infinity, Double.nan, 1e300, -1e300, 1e308, Double.greatestFiniteMagnitude, UInt64.max, Int.min,
                              true, false, "12", "", NSNull(), [1], ["x": 1], -1]
        for v in hostile {
            XCTAssertNil(SetsNumber.int(v, in: 0...100), "\(v)")
            XCTAssertNil(SetsNumber.double(v, in: 0...100), "\(v)")
            XCTAssertEqual(SetsNumber.seq(v), 0, "\(v)")
            XCTAssertNil(SetsNumber.pageClock(v), "\(v)")
            XCTAssertNil(SetsNumber.count(v), "\(v)")
            XCTAssertNil(SetsNumber.roi(["x": 0.1, "y": 0.1, "w": v, "h": 0.5])?.w, "\(v)")
            XCTAssertNil(SetsNumber.canvasRect(["x": 0, "y": 0, "w": v, "h": 300]), "\(v)")
            XCTAssertTrue((0.5...8).contains(SetsNumber.dpr(v)), "\(v)")
        }
        XCTAssertNil(SetsNumber.int(1.5, in: 0...100), "a fraction is not a whole number")
        XCTAssertEqual(SetsNumber.seq(1.5), 0)
        // In range, whatever the number's type: an Int, a whole Double, an NSNumber.
        XCTAssertEqual(SetsNumber.int(42, in: 0...100), 42)
        XCTAssertEqual(SetsNumber.int(42.0, in: 0...100), 42)
        XCTAssertEqual(SetsNumber.int(NSNumber(value: 42 as UInt8), in: 0...100), 42)
        XCTAssertEqual(SetsNumber.int(-0.0, in: 0...100), 0)
        XCTAssertEqual(SetsNumber.int(Int.max, in: 0...Int.max), Int.max)
        XCTAssertEqual(SetsNumber.double(0.25, in: 0...1), 0.25)
        XCTAssertEqual(SetsNumber.double(3, in: 0...10), 3)
        // Text only where a field takes it (a query, the preview's o / l / ori).
        XCTAssertEqual(SetsNumber.int("12", in: 0...100, text: true), 12)
        XCTAssertNil(SetsNumber.int("99999999999999999999", in: 0...100, clamp: true, text: true))
        XCTAssertNil(SetsNumber.int("1e3", in: 0...10_000, text: true))
        XCTAssertNil(SetsNumber.int(" 12", in: 0...100, text: true))
        // Clamping: finite values only. A whole number past Int's range goes to the nearer end.
        XCTAssertEqual(SetsNumber.int(1e300, in: 0...100, clamp: true), 100)
        XCTAssertEqual(SetsNumber.int(-1e300, in: 0...100, clamp: true), 0)
        XCTAssertEqual(SetsNumber.int(UInt64.max, in: 0...100, clamp: true), 100)
        XCTAssertEqual(SetsNumber.int(-7, in: 0...100, clamp: true), 0)
        XCTAssertEqual(SetsNumber.double(1e308, in: 0...100, clamp: true), 100)
        XCTAssertNil(SetsNumber.int(Double.infinity, in: 0...100, clamp: true))
        XCTAssertNil(SetsNumber.int(Double.nan, in: 0...100, clamp: true))
        XCTAssertNil(SetsNumber.int(1.5, in: 0...100, clamp: true))
        XCTAssertNil(SetsNumber.double(Double.infinity, in: 0...100, clamp: true))
        XCTAssertNil(SetsNumber.double(Double.nan, in: 0...100, clamp: true))
        // The fields. What a real page sends reads as it always did.
        XCTAssertEqual(SetsNumber.seq(7), 7)
        XCTAssertEqual(SetsNumber.seq(7.0), 7)
        XCTAssertEqual(SetsNumber.seq("7"), 0)
        XCTAssertEqual(SetsNumber.seq("7", text: true), 7)
        XCTAssertEqual(SetsNumber.seq(SetsNumber.maxSafeInteger), SetsNumber.maxSafeInteger)
        XCTAssertEqual(SetsNumber.seq(Int.max), 0)
        XCTAssertEqual(SetsNumber.pageClock(123_456.789), 123_456.789)
        XCTAssertEqual(SetsNumber.fileRange(33_280), 33_280)
        XCTAssertEqual(SetsNumber.fileRange("33280"), 33_280)
        XCTAssertEqual(SetsNumber.fileRange(Int(UInt32.max)), Int(UInt32.max))
        for v in [Int(UInt32.max) + 1, Int.max, -1, 1e308, Double.nan, "x", NSNull()] as [Any] { XCTAssertEqual(SetsNumber.fileRange(v), 0, "\(v)") }
        for (v, want) in [(6, 6), ("8", 8), (0, 0), (65_535, 65_535), (65_536, 1), (-3, 1), (Double.nan, 1), (1e300, 1)] as [(Any, Int)] { XCTAssertEqual(SetsNumber.orientation(v), want, "\(v)") }
        XCTAssertEqual(SetsNumber.dpr(2), 2)
        XCTAssertEqual(SetsNumber.dpr(1.5), 1.5)
        XCTAssertEqual(SetsNumber.dpr(1e308), 8)
        XCTAssertEqual(SetsNumber.dpr(-2), 0.5)
        XCTAssertEqual(SetsNumber.dpr(Double.nan), 1)
        XCTAssertEqual(SetsNumber.canvasRect(["x": 320, "y": 48.5, "w": 1200, "h": 800]), CGRect(x: 320, y: 48.5, width: 1200, height: 800))
        XCTAssertEqual(SetsNumber.canvasRect([:]), .zero, "a missing field is 0, as before")
        XCTAssertEqual(SetsNumber.canvasRect(["x": -40, "y": -10, "w": SetsNumber.maxCanvasEdge, "h": 0])?.width, 16_384)
        for bad in [["w": -1], ["h": 16_385], ["x": 1e308], ["y": -Double.infinity], ["w": Double.nan], ["x": "12"]] as [[String: Any]] { XCTAssertNil(SetsNumber.canvasRect(bad), "\(bad)") }
        XCTAssertEqual(SetsNumber.roi(["x": 0.25, "y": 0.5, "w": 0.125, "h": 0.25])?.w, 0.125)
        XCTAssertEqual(SetsNumber.roi(["x": 0, "y": 0, "w": 1, "h": 1])?.h, 1)
        XCTAssertNil(SetsNumber.roi(["x": 0, "y": 0, "w": 0, "h": 1]))
        // Zoomed out, the page's canvas box reaches beyond the photo.
        XCTAssertEqual(SetsNumber.roi(["x": -2.5, "y": -1.5, "w": 6, "h": 4])?.x, -2.5)
        XCTAssertNil(SetsNumber.roi(["x": 65, "y": 0, "w": 1, "h": 1]))
        XCTAssertNil(SetsNumber.roi(["x": Double.nan, "y": 0, "w": 1, "h": 1]))
        XCTAssertNil(SetsNumber.roi(NSNull()))
        XCTAssertEqual(SetsNumber.count(100_000), 100_000)
        XCTAssertNil(SetsNumber.count(100_001))
        XCTAssertEqual(SetsNumber.exportEdge(2048), 2048)
        XCTAssertEqual(SetsNumber.exportEdge("2048"), 2048)
        XCTAssertEqual(SetsNumber.exportEdge(Int.max), 65_536)
        for v in [0, -1, Double.nan, 1e300, "full", NSNull()] as [Any] { XCTAssertNil(SetsNumber.exportEdge(v), "\(v)") }
        for (v, want) in [("1024", 1024), ("1", 64), ("99999", 8192), ("-5", 64), ("", 1024), ("NaN", 1024), ("1e300", 1024), ("99999999999999999999", 1024)] { XCTAssertEqual(SetsNumber.renderEdge(v), want, v) }
        XCTAssertEqual(SetsNumber.renderEdge(nil), 1024)
        for (v, want) in [("9", 9), ("8", 8), ("0", nil), ("-1", nil), ("100", nil), ("9.5", nil), ("Infinity", nil)] as [(String, Int?)] { XCTAssertEqual(SetsNumber.decoder(v), want, v) }
        XCTAssertNil(SetsNumber.decoder(nil))
    }

    /// F1: `canvasLook` with a `seq` or a `t` that is not a number a counter or a clock can hold.
    /// The look is still scheduled (its own sequence number comes back); the page's is read as 0.
    func testCanvasLookTakesAnySeqAndClock() async throws {
        let (b, _) = try await bridge()
        _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "look": ""])
        var last = 0
        for v in [1e300, Double.infinity, -Double.infinity, Double.nan, -1e300, 1e308, 1.5, -1, Int.max, Int.min, UInt64.max, true, "7", NSNull()] as [Any] {
            for key in [false, true] {
                let (r, e) = await call(b, ["op": "canvasLook", "look": "ev:+0.10", "seq": v, "t": v, "key": key])
                XCTAssertNil(e)
                let seq = try XCTUnwrap(r as? Int, "seq \(v)")
                XCTAssertGreaterThan(seq, last, "seq \(v): the look was scheduled")
                last = seq
            }
        }
        let (r, _) = await call(b, ["op": "canvasLook", "look": "ev:+0.20", "seq": 12, "t": 1234.5])
        XCTAssertGreaterThan(try XCTUnwrap(r as? Int), last, "a real seq after the hostile ones")
        let (s, _) = await call(b, ["op": "canvasStats"])
        XCTAssertNotNil((s as? [String: Any])?["path"], "the stats still encode: no NaN reached them")
        _ = await call(b, ["op": "canvasLeave"])
    }

    /// F2: `canvasLayout` on the native canvas (a Metal view in a host view, as the app has it)
    /// with rects no display holds. They hide the canvas and leave its size alone; a real rect
    /// after them lays out as before. Without a Metal device (a CI runner) the controller is on
    /// the image path and only survival and the pixel ratio are checked.
    func testHostileLayoutOnTheNativeCanvas() async throws {
        let (b, _) = try await bridge(canvas: false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        b.attachCanvas(host: host)
        let canvas = try XCTUnwrap(b.canvas)
        let native = canvas.path == .native
        print("testHostileLayoutOnTheNativeCanvas: canvas path \(canvas.path.rawValue)")
        _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "look": ""])
        func stats() async -> [String: Any] { ((await call(b, ["op": "canvasStats"])).0 as? [String: Any]) ?? [:] }
        func good() async throws {
            let (r, _) = await call(b, ["op": "canvasLayout", "x": 100, "y": 50, "w": 400, "h": 300, "dpr": 2, "visible": true])
            XCTAssertEqual((r as? [String: Any])?["path"] as? String, canvas.path.rawValue)
            let s = await stats()
            XCTAssertEqual(s["dpr"] as? Double, 2)
            guard native else { return }
            XCTAssertEqual(s["canvas"] as? [Int], [800, 600])
            XCTAssertEqual(s["visible"] as? Bool, true)
            let view = try XCTUnwrap(host.subviews.first)
            XCTAssertEqual(view.frame, NSRect(x: 100, y: 250, width: 400, height: 300))
            XCTAssertFalse(view.isHidden)
        }
        func hidden(_ what: String) async {
            let s = await stats()
            XCTAssertEqual(s["dpr"] as? Double, 2, "\(what): the pixel ratio is the last real one")
            guard native else { return }
            XCTAssertEqual(s["canvas"] as? [Int], [800, 600], "\(what): the drawable keeps its size")
            XCTAssertEqual(s["visible"] as? Bool, false, what)
            XCTAssertEqual(host.subviews.first?.isHidden, true, what)
            XCTAssertEqual(host.subviews.first?.frame, NSRect(x: 100, y: 250, width: 400, height: 300), what)
        }
        try await good()
        // Through the bridge: the former crash (w / h = 1e308) and its relatives.
        let rects: [[String: Any]] = [
            ["x": 0, "y": 0, "w": 1e308, "h": 1e308], ["x": 0, "y": 0, "w": Double.infinity, "h": Double.infinity], ["x": 0, "y": 0, "w": Double.nan, "h": 300],
            ["x": Double.nan, "y": 0, "w": 400, "h": 300], ["x": 0, "y": -Double.infinity, "w": 400, "h": 300], ["x": 1e300, "y": 0, "w": 400, "h": 300],
            ["x": 0, "y": 0, "w": -400, "h": 300], ["x": 0, "y": 0, "w": 400, "h": 16_385], ["x": 0, "y": 0, "w": Int.max, "h": Int.max], ["x": "0", "y": 0, "w": 400, "h": 300],
        ]
        for r in rects {
            var body: [String: Any] = ["op": "canvasLayout", "dpr": 2, "visible": true]
            body.merge(r) { $1 }
            let (out, e) = await call(b, body)
            XCTAssertNil(e)
            XCTAssertEqual((out as? [String: Any])?["path"] as? String, canvas.path.rawValue)
            await hidden("\(r)")
            try await good()
        }
        // A pixel ratio that is not one is clamped (0.5 … 8) or read as 1; the rect still lays out.
        for (dpr, want) in [(1e308, 8.0), (Double.infinity, 1), (Double.nan, 1), (-2, 0.5), (0, 0.5)] as [(Double, Double)] {
            _ = await call(b, ["op": "canvasLayout", "x": 100, "y": 50, "w": 400, "h": 300, "dpr": dpr, "visible": true])
            let s = await stats()
            XCTAssertEqual(s["dpr"] as? Double, want, "dpr \(dpr)")
            if native { XCTAssertEqual(s["canvas"] as? [Int], [Int(400 * want), Int(300 * want)], "dpr \(dpr)") }
            try await good()
        }
        // The controller on its own, whoever calls it: the same rects without the bridge's reading.
        let direct: [(CGRect, CGFloat)] = [
            (CGRect(x: 0, y: 0, width: 1e308, height: 1e308), 2), (.infinite, 2), (.null, 2), (CGRect(x: 0, y: 0, width: CGFloat.nan, height: 300), 2),
            (CGRect(x: CGFloat.infinity, y: 0, width: 400, height: 300), 2), (CGRect(origin: .zero, size: CGSize(width: -400, height: 300)), 2),
            (CGRect(x: 0, y: 0, width: 400, height: 300), .nan), (CGRect(x: 0, y: 0, width: 400, height: 300), .infinity), (CGRect(x: 0, y: 0, width: 400, height: 300), 0),
            (CGRect(x: 0, y: 0, width: 400, height: 300), -2), (CGRect(x: 0, y: 0, width: 400, height: 300), 1e308), (CGRect(x: 1e9, y: 0, width: 400, height: 300), 2),
        ]
        for (rect, dpr) in direct {
            XCTAssertFalse(LookCanvasController.layable(rect, dpr: dpr), "\(rect) @\(dpr)")
            canvas.layout(rect: rect, visible: true, dpr: dpr)
            await hidden("direct \(rect) @\(dpr)")
            try await good()
        }
        // A real rect at the limit: laid out, the drawable no larger than Metal's texture edge.
        XCTAssertTrue(LookCanvasController.layable(CGRect(x: 0, y: 0, width: 16_384, height: 9000), dpr: 2))
        canvas.layout(rect: CGRect(x: 0, y: 0, width: 9000, height: 100), visible: false, dpr: 2)
        if native {
            let s = await stats()
            XCTAssertEqual(s["canvas"] as? [Int], [16_384, 200])
        }
        try await good()
        // The loupe and a zoomed look with regions that are not regions: read as "no region".
        for v in [Double.infinity, -Double.infinity, Double.nan, 1e308, -1e308] {
            _ = await call(b, ["op": "canvasLoupe", "on": true, "roi": ["x": -v, "y": 0.0, "w": v, "h": 1e308]])
            _ = await call(b, ["op": "canvasLook", "look": "ev:+0.2", "roi": ["x": 0.0, "y": 0.0, "w": v, "h": v], "key": true, "seq": v, "t": v])
        }
        try await Task.sleep(nanoseconds: 300_000_000)          // a few display refreshes with the canvas showing
        let after = await stats()
        XCTAssertEqual(after["region"] as? Bool, false)
        _ = await call(b, ["op": "canvasLoupe", "on": false])
        _ = await call(b, ["op": "canvasLayout", "x": 0, "y": 0, "w": 0, "h": 0, "visible": false])
        _ = await call(b, ["op": "canvasLeave"])
    }

    /// A session summary's counts go into the recents index: only counts a shoot can have.
    func testSessionSummaryCountsAreBounded() async throws {
        let (b, _) = try await bridge(canvas: false)
        let id = try XCTUnwrap(b.shootId)
        func recent() async -> [String: Any] { (((await call(b, ["op": "recents"])).0 as? [[String: Any]])?.first) ?? [:] }
        let (ok, _) = await call(b, ["op": "saveSession", "id": id, "json": "{}", "summary": ["n": 2, "dec": 2, "kp": 1, "last": "today"]])
        XCTAssertEqual(ok as? Bool, true)
        var r = await recent()
        XCTAssertEqual([r["n"] as? Int, r["dec"] as? Int, r["kp"] as? Int], [2, 2, 1])
        for v in [1e300, Double.infinity, Double.nan, -1, Int.max, Int.min, 100_001, 1.5, true, "3", NSNull()] as [Any] {
            let (ok, e) = await call(b, ["op": "saveSession", "id": id, "json": "{}", "summary": ["n": v, "dec": v, "kp": v]])
            XCTAssertEqual(ok as? Bool, true, "\(v): the session itself is saved")
            XCTAssertNil(e)
            r = await recent()
            XCTAssertEqual([r["n"] as? Int, r["dec"] as? Int, r["kp"] as? Int], [2, 2, 1], "\(v): the counts stay what they were")
        }
    }

    /// Settings are stored as JSON: a number JSON can't hold (NaN, Infinity) is refused, and the
    /// stored settings stay. `JSONSerialization` raises on one, which stopped the app.
    func testSetPrefsRefusesNumbersJSONCannotHold() async throws {
        let (b, _) = try await bridge(opened: false, canvas: false)
        let (ok, _) = await call(b, ["op": "setPrefs", "prefs": ["rating": 3]])
        XCTAssertEqual(ok as? Bool, true)
        let stored = UserDefaults.standard.string(forKey: SetsBridge.prefsKey)
        XCTAssertEqual(SetsBridge.prefs?["rating"] as? Int, 3)
        for prefs in [["rating": Double.nan], ["rating": Double.infinity], ["a": ["b": [1, -Double.infinity]]], ["rating": 1e308, "x": Double.nan]] as [[String: Any]] {
            let (r, e) = await call(b, ["op": "setPrefs", "prefs": prefs])
            XCTAssertEqual(r as? Bool, false, "\(prefs)")
            XCTAssertNil(e)
            XCTAssertEqual(UserDefaults.standard.string(forKey: SetsBridge.prefsKey), stored, "\(prefs)")
        }
        let (again, _) = await call(b, ["op": "setPrefs", "prefs": ["rating": 4, "big": 1e308]])
        XCTAssertEqual(again as? Bool, true)
        XCTAssertEqual(SetsBridge.prefs?["rating"] as? Int, 4)
    }
}
