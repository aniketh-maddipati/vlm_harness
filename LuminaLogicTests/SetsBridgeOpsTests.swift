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
/// green on main and goes on checking everything else. Inputs that crash the app process cannot
/// run in this process: `testCrashingInputs` runs them only with `LUMINA_BRIDGE_CRASH_CASES=1`
/// (see `Tests/probe/fuzz/run.sh bridge-crash` and `docs/release/stress/Q4-hostile.md`).
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
        "ready": ["missing"], "cullCard": [], "openFolder": [], "prefetch": ["items"], "near": ["a", "b"], "ingestStats": [],
        "shootOpened": ["name", "n", "date", "bodies"], "shootHeader": [], "decoderUpdate": [],
        "canvasEnter": ["rel", "model", "look", "prev", "next", "preview", "prevPreview", "nextPreview"], "canvasLeave": [],
        "canvasLayout": ["x", "y", "w", "h", "visible", "dpr"], "canvasLook": ["look", "drag", "key", "roi", "t", "seq"],
        "canvasDrag": ["start"], "canvasLoupe": ["on", "roi"], "canvasStats": ["reset"],
        "saveSession": ["id", "json", "summary"], "recents": [], "reopen": ["id"], "workingFiles": ["id"], "removeShoot": ["id"],
        "writeInto": ["label", "files"], "readSidecars": ["root", "files"], "writeSidecars": ["root", "files"], "reveal": ["path"],
        "setPrefs": ["prefs"], "checkAccess": [], "reopenDenied": [], "reopenCurrent": [],
    ]

    /// Inputs known to stop the app process (Swift traps), run only by `testCrashingInputs`.
    private func crashes(_ op: String, _ field: String, _ name: String) -> Bool {
        op == "canvasLook" && field == "seq" && ["huge", "inf", "negInf", "nan", "1e300"].contains(name)
    }

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
        for (op, fields) in Self.fields.sorted(by: { $0.key < $1.key }) {
            // Missing everything, and the op alone with a wrong-typed op name next to it.
            for body in [["op": op], ["op": op, "op2": NSNull()]] as [[String: Any]] {
                _ = await call(b, body); calls += 1
            }
            for field in fields {
                for (name, v) in values() + numbers() where !crashes(op, field, name) {
                    var body: [String: Any] = ["op": op]
                    for f in fields where f != field { if let g = good[f] { body[f] = g } }
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
        let known = violations.filter { $0.hasPrefix("reveal.") }
        let rest = violations.filter { !$0.hasPrefix("reveal.") }
        XCTAssertEqual(rest, [], "refusals answered as refusals")
        // T8 / S4: `reveal` shows any absolute path that exists (and falls back to the open folder).
        XCTExpectFailure("T8 · S4: reveal takes any absolute path", strict: false) {
            XCTAssertEqual(known, [], "reveal stays inside the opened folders")
        }
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
            guard let url = revealed.popLast() else { return nil }
            return url.path == shoot.path || url.path.hasPrefix(shoot.path + "/") ? nil : "revealed \(url.path)"
        case ("canvasEnter", "rel"):
            return e == nil ? "entered a hostile rel" : nil
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
    func testWriteIntoHostileFiles() async throws {
        let (b, _) = try await bridge(canvas: false)
        let before = snapshot()
        let bytes = Data("x".utf8).base64EncodedString()
        let cases: [[String: Any]] = [
            ["name": "../\(marker).txt", "b64": bytes], ["name": "/tmp/\(marker).txt", "b64": bytes], ["name": "a/../../\(marker)", "b64": bytes],
            ["name": "\(marker)\u{0}.txt", "b64": bytes], ["name": "sub/\(marker).txt", "b64": bytes], ["name": Self.tenMB, "b64": bytes],
            ["name": String(repeating: "é", count: 200), "b64": bytes], ["name": "\(marker).copy", "src": "../outside/secret.txt"],
            ["name": "\(marker).copy", "src": outside.appendingPathComponent("secret.txt").path], ["name": "\(marker).jpg", "jpg": ["src": "/etc/hosts", "css": Self.tenMB]],
            ["name": "\(marker).jpg", "look": ["src": "shoot/../outside/DSC09999.ARW", "look": "ev:+1", "px": -1]],
            ["name": "\(marker).bin", "b64": 42], ["name": 7, "b64": bytes], ["name": "\(marker)-ok.txt", "b64": bytes],
        ]
        var outcomes: [String] = []
        for c in cases {
            let (r, _) = await call(b, ["op": "writeInto", "label": Self.tenMB.prefix(1000) + "<img src=x onerror=alert(1)>", "files": [c]])
            outcomes.append(String(describing: (r as? [String: Any])?["say"] ?? (r as? [String: Any])?["n"] ?? r).prefix(120).description)
        }
        print("writeInto hostile:", outcomes)
        XCTAssertEqual(strays(), [], "an export name led out of the destination")
        XCTAssertEqual(snapshot(), before)
        let leaked = fm.enumerator(atPath: dest.path)?.compactMap { $0 as? String }.filter { p in
            let full = dest.appendingPathComponent(p)
            return (try? String(contentsOf: full, encoding: .utf8))?.contains(Self.canary) == true
        } ?? []
        XCTAssertEqual(leaked, [], "a copy from outside the opened folders")
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
        XCTExpectFailure("T5 · open: shootOpened's date / photos go into index.json at any size", strict: false) {
            XCTAssertLessThan(size, 1 << 20, "the recents index stays small whatever the page sends")
        }
    }

    // MARK: Inputs that stop the process

    /// Run only in a process of its own (`LUMINA_BRIDGE_CRASH_CASES=<case>`): each case is expected
    /// to trap, and the crash report is the evidence. `bash Tests/probe/fuzz/run.sh bridge-crash`.
    func testCrashingInputs() async throws {
        guard let which = ProcessInfo.processInfo.environment["LUMINA_BRIDGE_CRASH_CASES"] else {
            throw XCTSkip("traps the process: set LUMINA_BRIDGE_CRASH_CASES (seqHuge, seqInf, seqNaN, layoutInf, loupeInf) to run one")
        }
        let (b, _) = try await bridge(canvas: !which.hasSuffix("Inf") || which.hasPrefix("seq"))
        switch which {
        case "seqHuge": _ = await call(b, ["op": "canvasLook", "look": "ev:+0.1", "seq": 1e300])
        case "seqInf": _ = await call(b, ["op": "canvasLook", "look": "ev:+0.1", "seq": Double.infinity])
        case "seqNaN": _ = await call(b, ["op": "canvasLook", "look": "ev:+0.1", "seq": Double.nan])
        case "layoutInf":
            // The native canvas (a Metal view in a host view), as the app has it.
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            b.attachCanvas(host: host)
            _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "look": ""])
            _ = await call(b, ["op": "canvasLayout", "x": 0, "y": 0, "w": 1e308, "h": 1e308, "dpr": 2, "visible": true])
        case "loupeInf":
            // The loupe's region on the native canvas, with a rect the page measured as Infinity.
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            b.attachCanvas(host: host)
            _ = await call(b, ["op": "canvasEnter", "rel": "shoot/DSC00001.ARW", "look": ""])
            _ = await call(b, ["op": "canvasLayout", "x": 0, "y": 0, "w": 400, "h": 300, "dpr": 2, "visible": true])
            try await Task.sleep(nanoseconds: 1_000_000_000)
            _ = await call(b, ["op": "canvasLoupe", "on": true, "roi": ["x": -Double.infinity, "y": 0.0, "w": Double.infinity, "h": 1e308]])
            _ = await call(b, ["op": "canvasLook", "look": "ev:+0.2", "roi": ["x": 0.0, "y": 0.0, "w": Double.infinity, "h": Double.infinity], "key": true])
            try await Task.sleep(nanoseconds: 1_000_000_000)
        default: throw XCTSkip("unknown case \(which)")
        }
        print("LUMINA_BRIDGE_CRASH_CASES=\(which): survived")
    }
}
