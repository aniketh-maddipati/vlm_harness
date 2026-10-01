import AppKit
import Foundation

/// Runs one scenario file: a page, a window size, and a list of steps. Every step is followed by a
/// liveness check; any page error, console.error, invariant break, hang or web-process crash fails
/// the run. Output: `<out>/report.json`, `events.jsonl`, snapshots, state dumps, downloads.
@MainActor
final class Runner {
    struct StepReport: Encodable { let i: Int; let op: String; let ms: Double; let ok: Bool; let note: String? }
    struct Report: Encodable {
        let scenario: String
        let pass: Bool
        let skipped: String?
        let failures: [String]
        let steps: [StepReport]
        let resources: [ResourceSampler.Summary]
        let frames: [String: [String: Double]]
        let downloads: [String]
        let dialogs: [String]
        let seconds: Double
    }

    let scenarioURL: URL
    let spec: [String: Any]
    let outDir: URL
    private var host: ProbeHost!
    private let sampler = ResourceSampler()
    private var steps: [StepReport] = []
    private var failures: [String] = []
    private var frames: [String: [String: Double]] = [:]
    private var scale: Double = 1
    private lazy var disks = DiskImages(root: outDir.appendingPathComponent("disks", isDirectory: true))
    private(set) var skipped: String?

    init(scenario: URL, outDir: URL) throws {
        scenarioURL = scenario
        let data = try Data(contentsOf: scenario)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProbeError("scenario must be a JSON object") }
        spec = obj
        self.outDir = outDir
    }

    private func path(_ key: String, default d: String) -> URL {
        let p = (spec[key] as? String) ?? d
        return p.hasPrefix("/") ? URL(fileURLWithPath: p) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(p)
    }

    func run(echo: Bool) async -> Bool {
        let t0 = Date()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        do {
            let size = (spec["size"] as? [Double]) ?? [1280, 800]
            scale = (spec["scale"] as? Double) ?? 1
            var config: [String: Any] = [:]
            if spec["storageWrites"] as? Bool == false { config["noStorageWrites"] = true }
            if let clock = spec["clock"] as? String {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.timeZone = .current
                guard let d = f.date(from: clock) else { throw ProbeError("bad clock \(clock)") }
                config["clockBase"] = d.timeIntervalSince1970 * 1000
            }
            // LUMINA_PROBE_MODE=app runs a prototype scenario through the app's plumbing (e.g. the
            // camera edge cases through the native read, to compare with the page's own read).
            let app = (ProcessInfo.processInfo.environment["LUMINA_PROBE_MODE"] ?? spec["mode"] as? String) == "app"
            host = try await ProbeHost.make(size: CGSize(width: size[0], height: size[1]),
                                            pageRoot: path("pageRoot", default: app ? "Lumina/Sets/Web" : "design/handoff/lumina-cull"),
                                            vendorRoot: path("vendorRoot", default: app ? "Lumina/Sets/Web" : "design/handoff/vendor"),
                                            plumbing: app ? path("plumbing", default: "Lumina/Sets/Web/plumbing.js") : nil,
                                            supportDir: path("supportDir", default: outDir.appendingPathComponent("support", isDirectory: true).path),
                                            outDir: outDir, config: config, appConfig: spec["app"] as? [String: Any] ?? [:])
            host.echo = echo
            sampler.start(interval: ((spec["sampleMs"] as? Double) ?? 250) / 1000) { [host] in
                [(getpid(), "probe"), (host!.webProcessID, "web")]
            }
            try await host.load((spec["page"] as? String) ?? "Lumina Sets v5.dc.html", query: spec["query"] as? String)
            try await waitFor("return window.__probe && __probe.ready()", timeout: 30, what: "page ready")

            for (i, step) in ((spec["steps"] as? [[String: Any]]) ?? []).enumerated() {
                let op = step["do"] as? String ?? "?"
                let s0 = Date()
                if echo { FileHandle.standardError.write("→ #\(i) \(op)\n".data(using: .utf8)!) }
                var note: String?
                var ok = true
                do {
                    note = try await perform(op, step)
                    try await checkAlive(strictInvariants: step["invariants"] as? Bool ?? true)
                } catch let skip as ProbeSkip {
                    skipped = skip.reason
                    break
                } catch {
                    ok = false
                    note = "\(error)"
                    failures.append("step \(i) \(op): \(error)")
                }
                if !host.errors.isEmpty {
                    ok = false
                    failures.append(contentsOf: host.errors.map { "step \(i) \(op): \($0)" })
                    host.errorsDrained()
                }
                steps.append(StepReport(i: i, op: op, ms: Date().timeIntervalSince(s0) * 1000, ok: ok, note: note))
                if !ok && (spec["stopOnFailure"] as? Bool ?? true) { break }
            }
        } catch {
            failures.append("setup: \(error)")
        }
        sampler.stop()
        disks.detachAll()
        try? await checkBudgets()
        return finish(seconds: Date().timeIntervalSince(t0))
    }

    // MARK: Steps

    private func perform(_ op: String, _ s: [String: Any]) async throws -> String? {
        switch op {
        case "key":
            let k = try str(s, "k")
            let times = s["times"] as? Int ?? 1
            let gap = s["gapMs"] as? Double ?? 0
            for _ in 0..<times {
                try host.key(k, shift: s["shift"] as? Bool ?? false, cmd: s["cmd"] as? Bool ?? false,
                             alt: s["alt"] as? Bool ?? false, ctrl: s["ctrl"] as? Bool ?? false)
                try await settle(gap)
            }
            try await settle(s["settleMs"] as? Double ?? 60)
        case "keyDown":
            try host.key(try str(s, "k"), shift: s["shift"] as? Bool ?? false, cmd: s["cmd"] as? Bool ?? false, up: false)
            try await settle(s["settleMs"] as? Double ?? 60)
        case "keyUp":
            try host.key(try str(s, "k"), shift: s["shift"] as? Bool ?? false, cmd: s["cmd"] as? Bool ?? false, down: false)
            try await settle(s["settleMs"] as? Double ?? 60)
        case "hold":
            let k = try str(s, "k")
            try host.key(k, shift: s["shift"] as? Bool ?? false, up: false)
            try await settle(s["ms"] as? Double ?? 400)
            if let name = s["snap"] as? String { try await snap(name) }
            if let name = s["state"] as? String { try await dumpState(name) }
            try host.key(k, shift: s["shift"] as? Bool ?? false, down: false)
            try await settle(60)
        case "type":
            for ch in try str(s, "text") { try host.key(String(ch)); try await settle(s["gapMs"] as? Double ?? 10) }
        case "click", "dblclick":
            let p = try await point(s)
            var flags: NSEvent.ModifierFlags = []
            if s["cmd"] as? Bool ?? false { flags.insert(.command) }
            if s["shift"] as? Bool ?? false { flags.insert(.shift) }
            let n = op == "dblclick" ? 2 : 1
            for c in 1...n {
                host.mouse(.leftMouseDown, at: p, clicks: c, flags: flags)
                host.mouse(.leftMouseUp, at: p, clicks: c, flags: flags)
            }
            try await settle(s["settleMs"] as? Double ?? 80)
        case "drag":
            let from = try pt(s["from"]), to = try pt(s["to"])
            let n = s["steps"] as? Int ?? 12
            host.mouse(.leftMouseDown, at: from)
            for i in 1...n {
                let t = Double(i) / Double(n)
                host.mouse(.leftMouseDragged, at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                try await settle(16)
            }
            host.mouse(.leftMouseUp, at: to)
            try await settle(80)
        case "wheel":
            let p = try await point(s)
            let frames = s["frames"] as? Int ?? 120
            let dy = Int32(s["dy"] as? Int ?? 40)
            let name = s["name"] as? String ?? "wheel"
            // tiles: also sample Cull's tiles every frame (blank on screen, thumbnail upscale ratio).
            // snapAt: frame numbers to snapshot mid-scroll (<name>-f<n>.png; the snapshot pauses the wheel).
            let tiles = s["tiles"] as? Bool ?? false, snapAt = Set(s["snapAt"] as? [Int] ?? [])
            _ = try await host.js("__probe.framesStart()" + (tiles ? "; __probe.tilesStart()" : ""))
            for f in 0..<frames {
                host.scrollWheel(at: p, dy: dy); try await settle(16)
                if snapAt.contains(f) { try await snap("\(name)-f\(f)") }
            }
            let r = try await host.js("return __probe.framesStop()") as? [String: Double] ?? [:]
            frames_(name, r, budget: s["p95Ms"] as? Double)
            var note = "p95 \(r["p95"] ?? 0) ms, \(Int(r["over33"] ?? 0)) frames > 33 ms"
            if tiles {
                let t = try await host.js("return __probe.tilesStop()") as? [String: Double] ?? [:]
                self.frames["\(name).tiles"] = t
                note += String(format: " · blank %.1f%% of on-screen tiles (%.1f%% of frames, worst %.1f%%) · upscale min %.2f median %.2f (tile %.0f px, dpr %.0f)",
                               t["blankPct"] ?? 0, t["blankFramesPct"] ?? 0, t["worstBlankPct"] ?? 0, t["upscaleMin"] ?? 0, t["upscaleMedian"] ?? 0, t["tile"] ?? 0, t["dpr"] ?? 0)
                if let cap = s["maxBlankPct"] as? Double, (t["blankPct"] ?? 0) > cap { failures.append("tiles \(name): \(t["blankPct"] ?? 0)% blank > \(cap)%") }
                if let floor = s["minUpscale"] as? Double, (t["upscaleMin"] ?? 0) < floor { failures.append("tiles \(name): thumbnails magnified, upscale min \(t["upscaleMin"] ?? 0) < \(floor)") }
            }
            return note
        case "wait":
            try await settle(s["ms"] as? Double ?? 100)
        case "waitFor":
            try await waitFor(try str(s, "js"), timeout: (s["timeoutMs"] as? Double ?? 10000) / 1000, what: s["what"] as? String ?? "condition")
        case "js":
            let r = try await host.js(try str(s, "src"), timeout: (s["timeoutMs"] as? Double ?? 10000) / 1000)
            return r.map { "\($0)" }
        case "expect":
            let r = try await host.js(try str(s, "js"))
            if let want = s["equals"] {
                guard jsonEqual(r, want) else { throw ProbeError("expected \(want), got \(r ?? "nil")") }
            } else if !truthy(r) {
                throw ProbeError("expected truthy: \(s["js"] ?? "")  got \(r ?? "nil")")
            }
        case "snap":
            try await snap(try str(s, "name"))
        case "state":
            try await dumpState(try str(s, "name"))
        case "dump":
            // Any JSON the page can compute, saved as <name>.json (e.g. every photo's measures).
            let r = try await host.js(try str(s, "js"), timeout: (s["timeoutMs"] as? Double ?? 30000) / 1000)
            let text = try (r as? String) ?? String(data: try JSONSerialization.data(withJSONObject: r ?? NSNull(), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]), encoding: .utf8)!
            try text.write(to: outDir.appendingPathComponent("\(try str(s, "name")).json"), atomically: true, encoding: .utf8)
        case "compare":
            return try await compare(s)
        case "openFolder":
            let url = URL(fileURLWithPath: try str(s, "path"))
            guard FileManager.default.fileExists(atPath: url.path) else { throw ProbeError("no such folder \(url.path)") }
            host.pendingOpenPanel = [url]
            if (s["via"] as? String ?? "key") == "key" { try host.key("o", cmd: true) } else { _ = try await host.js("__probe.logic().openFolder()") }
            // until: "shown" returns once Cull shows its first rows, while the folder is still being read.
            if s["until"] as? String == "shown" {
                try await waitFor("const l=__probe.logic(); return !!(l.real && l.real.length && l.state.view === 'cull' && l.state.realLoad)",
                                  timeout: (s["timeoutMs"] as? Double ?? 300_000) / 1000, what: "first rows shown")
                return "shown while reading"
            }
            try await waitFor("const l=__probe.logic(); return !!(l.real && !l.state.realLoad)",
                              timeout: (s["timeoutMs"] as? Double ?? 900_000) / 1000, what: "folder loaded")
            let info = try await host.js("return JSON.stringify(__probe.logic().state.realInfo)")
            return info.map { "\($0)" }
        case "diskImage":
            let from = (s["from"] as? String).map { _ in URL(fileURLWithPath: (try? str(s, "from")) ?? "") }
            let m = try disks.create(name: try str(s, "name"), sizeMB: s["sizeMB"] as? Int ?? 64, fs: s["fs"] as? String ?? "ExFAT",
                                     from: from, trimBytes: s["trimBytes"] as? Int, repeatTo: s["count"] as? Int)
            if s["readonly"] as? Bool ?? false { try disks.detach(name: try str(s, "name")); try await settle(300); try disks.attach(name: try str(s, "name"), readonly: true) }
            return m.path
        case "attach":
            if s["ifPulled"] as? Bool ?? false, disks.mounted.contains(try str(s, "name")) { return "already in" }
            return try disks.attach(name: try str(s, "name"), readonly: s["readonly"] as? Bool ?? false).path
        case "detach":
            let name = try str(s, "name")
            if let after = s["afterMs"] as? Double {
                // Pull it while the next steps run (mid-read / mid-export).
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000))
                    do { try self.disks.detach(name: name); self.host.log("disk", "pulled \(name)") } catch { self.host.log("disk", "pull failed: \(error)") }
                }
            } else {
                try disks.detach(name: name)
            }
        case "startCards":
            guard let bridge = host.bridge else { throw ProbeError("startCards needs app mode") }
            // Only this run's own disk images count as cards: never the user's real card.
            let norm = { (u: URL) -> String in
                let p = u.standardizedFileURL.path
                return p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p
            }
            let mine = norm(outDir.appendingPathComponent("disks"))
            bridge.cards.accepts = { norm($0).hasPrefix(mine + "/") }
            bridge.cards.onLog = { [host] in host?.log("cards", $0) }
            host.log("cards", "accepting under \(mine)")
            bridge.cards.start()
        case "nativeOpen":
            // The app's own path: bridge.open(url) (menu ⌘O, recents, "Cull this card").
            guard let bridge = host.bridge else { throw ProbeError("nativeOpen needs app mode") }
            bridge.open(URL(fileURLWithPath: try str(s, "path")))
            try await waitFor("const l=__probe.logic(); return !!(l.real && !l.state.realLoad)", timeout: (s["timeoutMs"] as? Double ?? 60000) / 1000, what: "folder loaded via bridge.open")
        case "menuOpen":
            // File ▸ Open: the menu calls __lumina.openFolder() through evaluateJavaScript.
            host.pendingOpenPanel = [URL(fileURLWithPath: try str(s, "path"))]
            host.webView.evaluateJavaScript("window.__lumina && __lumina.openFolder()", completionHandler: nil)
            try await waitFor("const l=__probe.logic(); return !!(l.real && !l.state.realLoad)", timeout: (s["timeoutMs"] as? Double ?? 60000) / 1000, what: "folder loaded via menu")
        case "reload":
            try await host.load((spec["page"] as? String) ?? "Lumina Sets v5.dc.html", query: spec["query"] as? String)
            try await waitFor("return window.__probe && __probe.ready()", timeout: 30, what: "page ready after reload")
            try await settle(s["settleMs"] as? Double ?? 600)
        case "logged":
            // Something the page or bridge reported, e.g. a toast that has already faded.
            let kind = s["kind"] as? String, match = try str(s, "match")
            guard let e = host.events.last(where: { (kind == nil || $0.kind == kind) && $0.text.contains(match) }) else {
                throw ProbeError("nothing logged matching '\(match)'")
            }
            return String(e.text.prefix(160))
        case "destinations":
            host.chooser.destinations = try strs(s, "paths").map { URL(fileURLWithPath: $0) }
        case "copyTree":
            let from = URL(fileURLWithPath: try str(s, "from")), to = URL(fileURLWithPath: try str(s, "to"))
            try? FileManager.default.removeItem(at: to)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: from, to: to)
        case "move":
            // What Finder does: rename or move a file. Only this run's own copies, never anything else.
            try FileManager.default.moveItem(at: try own(str(s, "from")), to: try own(str(s, "to")))
        case "remove":
            try FileManager.default.removeItem(at: try own(str(s, "path")))
        case "mkdir":
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: try str(s, "path")), withIntermediateDirectories: true)
        case "writeFile":
            let url = URL(fileURLWithPath: try str(s, "path"))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(try str(s, "text").utf8).write(to: url)
        case "fs":
            return try fsExpect(s)
        case "xmpMerged":
            return try await xmpMerged(s)
        case "killExport":
            return try await killExport(s)
        case "nativeExport":
            return try await nativeExport(s)
        case "refusals":
            let n = host.chooser.refusals.count
            if let want = s["count"] as? Int, want != n { throw ProbeError("expected \(want) refused destinations, got \(n): \(host.chooser.refusals)") }
            return host.chooser.refusals.joined(separator: " | ")
        case "lookParity":
            let rows = try await LookParity.run(host: host, image: URL(fileURLWithPath: try str(s, "image")),
                                                recipes: s["recipes"] as? [[String: Double]] ?? [], width: s["width"] as? Int ?? 600, outDir: outDir)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(rows).write(to: outDir.appendingPathComponent("look-parity.json"))
            let cap = s["maxMeanDE"] as? Double ?? 1
            let space = s["space"] as? String ?? "sRGB"
            let bad = rows.filter { $0.space == space && $0.meanDE >= cap }
            let lines = rows.map { "\($0.space) \($0.css): ΔE mean \(String(format: "%.2f", $0.meanDE)) p95 \(String(format: "%.2f", $0.p95DE)) max \(String(format: "%.2f", $0.maxDE))" }
            if !bad.isEmpty { throw ProbeError("mean ΔE ≥ \(cap) in \(space):\n  " + lines.joined(separator: "\n  ")) }
            return "\n  " + lines.joined(separator: "\n  ")
        case "editDrag", "editParity", "raw9", "editConsistency":
            // The Edit canvas and RAW 9 measures (EditSteps.swift). Gates apply unless LUMINA_EDIT_GATE=0.
            let o: EditSteps.Outcome
            switch op {
            case "editDrag": o = try await EditSteps.drag(host: host, s)
            case "editParity": o = try await EditSteps.parity(host: host, s, outDir: outDir)
            case "editConsistency": o = try await ConsistencySteps.run(host: host, s, folder: URL(fileURLWithPath: try str(s, "folder")), outDir: outDir)
            default: o = try await EditSteps.raw9(host: host, s, folder: URL(fileURLWithPath: try str(s, "folder")), outDir: outDir)
            }
            failures.append(contentsOf: o.failures)
            for (k, v) in o.frames { frames[k] = v }
            return o.note
        case "confirm":
            host.confirmAnswer = s["answer"] as? Bool ?? false
        case "fuzz":
            return try await fuzz(s)
        case "invariants":
            try await checkAlive(strictInvariants: true)
        default:
            throw ProbeError("unknown step '\(op)'")
        }
        return nil
    }

    // MARK: Files

    /// {path, exists?, count?(files under a dir matching `glob`), same?(byte-equal to another file),
    ///  contains?, notContains?}
    private func fsExpect(_ s: [String: Any]) throws -> String {
        let url = URL(fileURLWithPath: try str(s, "path"))
        let fm = FileManager.default
        if let want = s["exists"] as? Bool, fm.fileExists(atPath: url.path) != want {
            throw ProbeError("\(url.path) \(want ? "missing" : "should not exist")")
        }
        if let want = s["count"] as? Int {
            let glob = s["glob"] as? String ?? "*"
            let rx = try NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: glob).replacingOccurrences(of: "\\*", with: ".*") + "$")
            let all = (fm.enumerator(atPath: url.path)?.allObjects as? [String]) ?? []
            let hits = all.filter { rx.firstMatch(in: ($0 as NSString).lastPathComponent, range: NSRange(location: 0, length: ($0 as NSString).lastPathComponent.utf16.count)) != nil }
            guard hits.count == want else { throw ProbeError("\(url.lastPathComponent)/\(glob): expected \(want), found \(hits.count) \(hits.sorted().prefix(12))") }
            return "\(hits.count) × \(glob)"
        }
        if let other = s["same"] as? String {
            guard try Data(contentsOf: url) == Data(contentsOf: URL(fileURLWithPath: try str(s, "same"))) else { throw ProbeError("\(url.lastPathComponent) differs from \(other)") }
        }
        if s["contains"] != nil || s["notContains"] != nil {
            let text = try String(contentsOf: url, encoding: .utf8)
            if let c = s["contains"] as? String, !text.contains(c) { throw ProbeError("\(url.lastPathComponent) lacks '\(c)'") }
            if let c = s["notContains"] as? String, text.contains(c) { throw ProbeError("\(url.lastPathComponent) has '\(c)'") }
        }
        return "ok"
    }

    /// Lightroom hand-off (checklist F6 / L2). `dir`: where the sidecars were written. `originals`:
    /// the sidecars as Lightroom wrote them. `expectJs`: the page's own answer, `{file: {rating,
    /// label}}` (label null = leave what was there). Each written sidecar must parse, carry that
    /// rating and label, and — with rating and label taken out — be byte-identical to Lightroom's.
    private func xmpMerged(_ s: [String: Any]) async throws -> String {
        let dir = URL(fileURLWithPath: try str(s, "dir")), orig = URL(fileURLWithPath: try str(s, "originals"))
        guard let want = try await host.js(try str(s, "expectJs")) as? [String: [String: Any]], !want.isEmpty else { throw ProbeError("expectJs gave no files") }
        let strip = { (t: String) -> String in
            var t = t
            for rx in [#"\s*xmp:(Rating|Label)="[^"]*""#, #"\s*<xmp:(Rating|Label)>[^<]*</xmp:(Rating|Label)>"#, #"\s*xmlns:xmp="http://ns.adobe.com/xap/1.0/""#] {
                t = t.replacingOccurrences(of: rx, with: "", options: .regularExpression)
            }
            return t
        }
        let field = { (t: String, name: String) -> String? in
            for rx in ["xmp:\(name)=\"([^\"]*)\"", "<xmp:\(name)>([^<]*)</xmp:\(name)>"] {
                if let m = t.range(of: rx, options: .regularExpression) {
                    let hit = String(t[m]); return hit.replacingOccurrences(of: rx, with: "$1", options: .regularExpression)
                }
            }
            return nil
        }
        var lines: [String] = []
        for (file, w) in want.sorted(by: { $0.key < $1.key }) {
            let url = dir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { throw ProbeError("\(file) was not written") }
            let parser = XMLParser(data: data)
            guard parser.parse() else { throw ProbeError("\(file) doesn't parse: \(parser.parserError.map { "\($0)" } ?? "?")") }
            let rating = field(text, "Rating"), label = field(text, "Label")
            if let r = w["rating"] as? String, rating != r { throw ProbeError("\(file): rating \(rating ?? "none"), want \(r)") }
            let o = orig.appendingPathComponent(file)
            var note = "\(file): \(rating ?? "-")★ \(label ?? "")"
            if let od = try? Data(contentsOf: o), let ot = String(data: od, encoding: .utf8) {
                let wantLabel = (w["label"] as? String) ?? field(ot, "Label")
                if label != wantLabel { throw ProbeError("\(file): label \(label ?? "none"), want \(wantLabel ?? "none")") }
                guard strip(text) == strip(ot) else {
                    let a = strip(ot).components(separatedBy: "\n"), b = strip(text).components(separatedBy: "\n")
                    let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                    throw ProbeError("\(file): more than rating/label changed, first at line \(i + 1): \(a.indices.contains(i) ? a[i] : "∅") → \(b.indices.contains(i) ? b[i] : "∅")")
                }
                let crs = ot.components(separatedBy: "crs:").count - 1
                note += " · \(crs) crs: settings kept byte for byte"
            } else if let l = w["label"] as? String, label != l {
                throw ProbeError("\(file): label \(label ?? "none"), want \(l)")
            }
            // A second reader: exiftool, when installed, must read the same stars.
            if let exif = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                let p = Process(), out = Pipe()
                p.executableURL = URL(fileURLWithPath: exif); p.arguments = ["-s3", "-XMP:Rating", url.path]; p.standardOutput = out
                try p.run(); p.waitUntilExit()
                let got = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if got != rating { throw ProbeError("\(file): exiftool reads rating \(got ?? "nil"), file says \(rating ?? "nil")") }
                note += " · exiftool agrees"
            }
            lines.append(note)
        }
        return "\n  " + lines.joined(separator: "\n  ")
    }

    /// Kill mid-handoff (checklist F10, gate 8). A real process runs the app's export (RAW copies +
    /// .xmp sidecars, half of them replacing an older sidecar) and is SIGKILLed at seeded points:
    /// before the first file, inside a file, between files. After each kill the app's launch recovery
    /// runs, then the destination must hold only: finished files (verified bytes), untouched old
    /// sidecars, and .lumina-bak copies of the old bytes. Every .xmp must parse. Then the export is
    /// run again and must complete with every file right.
    private func killExport(_ s: [String: Any]) async throws -> String {
        let fm = FileManager.default
        let from = URL(fileURLWithPath: try str(s, "from"))
        let raws = try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(s["count"] as? Int ?? 6)
        guard !raws.isEmpty else { throw ProbeError("no ARWs in \(from.path)") }
        let xmp = { (r: Int, who: String) in
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Rating=\"\(r)\" xmp:CreatorTool=\"\(who)\"/></rdf:RDF></x:xmpmeta>\n"
        }
        var items: [[String: String]] = [], want: [String: Data] = [:], old: [String: Data] = [:]
        for (i, raw) in raws.enumerated() {
            let stem = raw.deletingPathExtension().lastPathComponent
            items.append(["name": "RAW/\(raw.lastPathComponent)", "copy": raw.path])
            want["RAW/\(raw.lastPathComponent)"] = try Data(contentsOf: raw)
            items.append(["name": "\(stem).xmp", "text": xmp(3 + i % 3, "Lumina")])
            want["\(stem).xmp"] = Data(xmp(3 + i % 3, "Lumina").utf8)
            if i % 2 == 0 { old["\(stem).xmp"] = Data(xmp(1, "Adobe Lightroom").utf8) }
        }
        let worker = Bundle.main.executableURL!
        var rng = SplitMix(seed: UInt64(s["seed"] as? Int ?? 8))
        let kills = s["kills"] as? Int ?? 16
        var phases: [String: Int] = [:], leftovers = 0, recoveredTemps = 0

        func allFiles(_ d: URL) -> [String] { (fm.enumerator(atPath: d.path)?.allObjects as? [String] ?? []).filter { !$0.hasSuffix("/") && !((try? fm.attributesOfItem(atPath: d.appendingPathComponent($0).path)[.type] as? FileAttributeType) == .typeDirectory) } }
        func runWorker(_ plan: URL) throws -> Process {
            let p = Process(); p.executableURL = worker; p.arguments = ["export-worker", plan.path]
            p.standardOutput = FileHandle.nullDevice; try p.run(); return p
        }
        func journal(_ dir: URL) -> SetsExportJournal.Entry? {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }.first.flatMap { try? dec.decode(SetsExportJournal.Entry.self, from: Data(contentsOf: $0)) }
        }
        /// What may be in the destination, and each file's bytes must be one of the allowed states.
        func verify(_ dest: URL, done: Set<String>, complete: Bool, _ tag: String) throws {
            for f in allFiles(dest) {
                let data = try Data(contentsOf: dest.appendingPathComponent(f))
                if f.hasSuffix(".xmp") && !XMLParser(data: data).parse() { throw ProbeError("\(tag): \(f) is torn (doesn't parse)") }
                if f.hasSuffix(SetsFileOps.backupSuffix) {
                    let owner = String(f.dropLast(SetsFileOps.backupSuffix.count))
                    guard let o = old[owner], o == data else { throw ProbeError("\(tag): \(f) isn't the old \(owner)") }
                } else if let w = want[f] {
                    if data == w { continue }
                    if complete || done.contains(f) { throw ProbeError("\(tag): \(f) is marked done but its bytes are wrong") }
                    guard old[f] == data else { throw ProbeError("\(tag): \(f) is neither the old file nor the new one (\(data.count) bytes)") }
                } else {
                    throw ProbeError("\(tag): stray file \(f) left in the destination")
                }
            }
            for name in done where !fm.fileExists(atPath: dest.appendingPathComponent(name).path) { throw ProbeError("\(tag): journal says \(name) is done, it isn't there") }
            if complete { for name in want.keys where !fm.fileExists(atPath: dest.appendingPathComponent(name).path) { throw ProbeError("\(tag): \(name) missing after the export finished") } }
        }

        for n in 0..<kills {
            let base = outDir.appendingPathComponent("kill/\(n)"), dest = base.appendingPathComponent("dest"), jdir = base.appendingPathComponent("journal")
            try? fm.removeItem(at: base)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for (name, data) in old { try data.write(to: dest.appendingPathComponent(name)) }
            let plan = base.appendingPathComponent("plan.json")
            try JSONSerialization.data(withJSONObject: ["destination": dest.path, "journalDir": jdir.path, "items": items, "label": "lr"]).write(to: plan)
            // Kill once the journal shows k files done, then a little later: lands before, inside or between files.
            let k = Int(rng.next() % UInt64(items.count)), extra = rng.unit() * 60
            let p = try runWorker(plan)
            let t0 = Date()
            while p.isRunning, (journal(jdir)?.done.count ?? -1) < k, Date().timeIntervalSince(t0) < 60 { try await settle(1) }
            try await settle(extra)
            let killed = p.isRunning
            if killed { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            let temps = allFiles(dest).filter { $0.contains(".lumina-tmp-") }.count
            leftovers += temps
            let before = journal(jdir)
            let phase = !killed ? "finished before the kill" : temps > 0 ? "inside a file" : (before?.done.count ?? 0) == 0 ? "before the first file" : "between files"
            phases[phase, default: 0] += 1
            // Next launch.
            let rec = SetsExportJournal.recover(in: jdir)
            recoveredTemps += rec.reduce(0) { $0 + ($1.tempsRemoved ?? 0) }
            let entry = journal(jdir)
            if killed, entry?.ok != true, entry?.recovered == nil { throw ProbeError("kill \(n): journal not marked recovered") }
            try verify(dest, done: Set(entry?.done ?? []), complete: entry?.ok == true, "kill \(n) (\(phase), k=\(k))")
            // Export again: must finish, with every file right and the old sidecars kept once.
            let again = try runWorker(plan); again.waitUntilExit()
            guard again.terminationStatus == 0, journal(jdir)?.ok == true else { throw ProbeError("kill \(n): export again failed") }
            try verify(dest, done: Set(want.keys), complete: true, "kill \(n) re-export")
            for name in old.keys where !fm.fileExists(atPath: dest.appendingPathComponent(name + SetsFileOps.backupSuffix).path) { throw ProbeError("kill \(n): \(name).lumina-bak missing") }
            try? fm.removeItem(at: dest.appendingPathComponent("RAW"))       // keep the evidence folder small
        }
        if recoveredTemps != leftovers { throw ProbeError("\(leftovers) temp files left by kills, recovery removed \(recoveredTemps)") }
        return "\(kills) kills · " + phases.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + " · \(leftovers) temp files left by kills, all removed on relaunch"
    }

    /// The app's export job run directly, no page: `from` (ARWs to copy, first `count`), `dest`,
    /// `sources` (folders being culled). `fill: {path, mb, afterMs}` writes a filler file while it
    /// runs (the disk fills up mid-copy). Expect with `n` and `failedContains`.
    private func nativeExport(_ s: [String: Any]) async throws -> String {
        let from = URL(fileURLWithPath: try str(s, "from")), dest = URL(fileURLWithPath: try str(s, "dest"))
        let raws = try FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(s["count"] as? Int ?? 3)
        var items: [SetsExportJob.Item] = raws.map { .copy(name: "RAW/\($0.lastPathComponent)", source: $0) }
        items.append(.bytes(name: "note.xmp", data: Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8)))
        let sources = try (s["sources"] as? [String] ?? []).map { try str(["v": $0], "v") }.map { URL(fileURLWithPath: $0) }
        let job = SetsExportJob(label: "both", destination: dest, items: items)
        let jdir = outDir.appendingPathComponent("journal-\(UUID().uuidString.prefix(6))")
        let task = Task.detached { job.run(journal: SetsExportJournal(directory: jdir), sources: sources) }
        if let fill = s["fill"] as? [String: Any] {
            try await settle(fill["afterMs"] as? Double ?? 20)
            let url = URL(fileURLWithPath: try str(fill, "path"))
            let mb = fill["mb"] as? Int ?? 50
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let h = try FileHandle(forWritingTo: url)
            for _ in 0..<mb { if (try? h.write(contentsOf: Data(count: 1 << 20))) == nil { break } }
            try? h.close()
        }
        let r = await task.value
        let note = "\(r.n) written · failed: \(r.failed.joined(separator: " | "))"
        if let n = s["n"] as? Int, n != r.n { throw ProbeError("expected \(n) written, got \(note)") }
        if let c = s["failedContains"] as? String, !r.failed.joined().contains(c) { throw ProbeError("expected a failure containing '\(c)', got \(note)") }
        // Whatever was written is complete and verified; nothing half-written anywhere under dest.
        for case let f as String in FileManager.default.enumerator(atPath: dest.path) ?? NSEnumerator() {
            if f.contains(".lumina-tmp-") { throw ProbeError("temp file left: \(f)") }
            if f.hasPrefix("RAW/"), let src = raws.first(where: { $0.lastPathComponent == (f as NSString).lastPathComponent }),
               try SetsFileOps.sha256(file: dest.appendingPathComponent(f)) != SetsFileOps.sha256(file: src) { throw ProbeError("\(f) differs from its original") }
        }
        return note
    }

    // MARK: Fuzzer

    /// Seeded key/mouse storm. Replays exactly from the seed; the last 60 inputs are kept in the
    /// report so a failure can be turned into a scenario. `chaos: {disk, rate}` also pulls and
    /// re-inserts that disk image at random (app mode: a card yanked mid-read, mid-cull, mid-export).
    private func fuzz(_ s: [String: Any]) async throws -> String {
        var rng = SplitMix(seed: UInt64(s["seed"] as? Int ?? 1))
        let count = s["count"] as? Int ?? 1000
        let checkEvery = s["checkEvery"] as? Int ?? 20
        let gaps = s["gapMs"] as? [Double] ?? [0, 40]
        let exclude = Set(s["exclude"] as? [String] ?? [])
        let keys = (s["keys"] as? [String] ?? Keys.pageKeys).filter { !exclude.contains($0) }
        let mouseRate = s["mouseRate"] as? Double ?? 0.08
        let chaos = s["chaos"] as? [String: Any]
        let chaosDisk = chaos?["disk"] as? String, chaosRate = chaos?["rate"] as? Double ?? 0
        let size = host.webView.bounds.size
        var trail: [String] = []
        var pulls = 0
        for n in 0..<count {
            let roll = rng.unit()
            var input: String
            if let disk = chaosDisk, rng.unit() < chaosRate {
                if disks.mounted.contains(disk) { try disks.detach(name: disk); input = "PULL \(disk)"; pulls += 1 }
                else { try disks.attach(name: disk, readonly: false); input = "INSERT \(disk)" }
                host.log("disk", input)
            } else if roll < mouseRate {
                let p = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
                if rng.unit() < 0.25 {
                    let q = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
                    input = "drag \(Int(p.x)),\(Int(p.y))→\(Int(q.x)),\(Int(q.y))"
                    host.mouse(.leftMouseDown, at: p)
                    for i in 1...6 { host.mouse(.leftMouseDragged, at: CGPoint(x: p.x + (q.x - p.x) * Double(i) / 6, y: p.y + (q.y - p.y) * Double(i) / 6)) }
                    host.mouse(.leftMouseUp, at: q)
                } else {
                    input = "click \(Int(p.x)),\(Int(p.y))"
                    host.mouse(.leftMouseDown, at: p); host.mouse(.leftMouseUp, at: p)
                }
            } else {
                let k = keys[Int(rng.next() % UInt64(keys.count))]
                let shift = rng.unit() < 0.18
                // v5: ⌘1–3 steps, ⌘A keep row, ⌘R Finder, ⌘Z undo; ⌥←→ skip a stack.
                let cmd = ["z", "1", "2", "3", "a", "r"].contains(k) && rng.unit() < 0.3
                let alt = ["ArrowLeft", "ArrowRight"].contains(k) && rng.unit() < 0.2
                input = (cmd ? "⌘" : "") + (alt ? "⌥" : "") + (shift ? "⇧" : "") + k
                if ["z", " ", "ArrowLeft", "ArrowRight"].contains(k) && !cmd && rng.unit() < 0.3 {
                    // held key: down, some time, up (Z 100%, Space large, arrows repeat)
                    try host.key(k, shift: shift, up: false)
                    try await settle(rng.unit() * 400)
                    try host.key(k, shift: shift, down: false)
                    input += " (held)"
                } else {
                    try host.key(k, shift: shift, cmd: cmd, alt: alt)
                }
            }
            trail.append(input)
            if trail.count > 60 { trail.removeFirst() }
            try await settle(gaps[0] + rng.unit() * (gaps[1] - gaps[0]))
            if n % checkEvery == checkEvery - 1 || !host.errors.isEmpty {
                do { try await checkAlive(strictInvariants: true) } catch {
                    try? await snap("fuzz-failure")
                    throw ProbeError("after input #\(n) (seed \(s["seed"] ?? 1)): \(error)\n  last inputs: \(trail.joined(separator: " · "))")
                }
                if !host.errors.isEmpty {
                    try? await snap("fuzz-failure")
                    throw ProbeError("after input #\(n) (seed \(s["seed"] ?? 1)): \(host.errors.joined(separator: "; "))\n  last inputs: \(trail.joined(separator: " · "))")
                }
            }
        }
        let st = try await host.js("const s=__probe.logic().state; return s.view+' · '+Object.keys(s.marks||{}).length+' marked · undo '+(s.undo||[]).length")
        return "\(count) inputs survived\(chaosDisk != nil ? " · \(pulls) card pulls" : "") · \(st ?? "")"
    }

    // MARK: Helpers

    private func settle(_ ms: Double) async throws {
        guard ms > 0 else { await Task.yield(); return }
        try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }

    private func waitFor(_ js: String, timeout: TimeInterval, what: String) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if host.webProcessCrashed { throw ProbeError("web process crashed while waiting for \(what)") }
            if truthy(try? await host.js(js, timeout: 5)) { return }
            try await settle(50)
        }
        throw ProbeError("timed out after \(Int(timeout))s waiting for \(what)")
    }

    private func checkAlive(strictInvariants: Bool) async throws {
        if host.webProcessCrashed { throw ProbeError("web process crashed") }
        let r = try await host.js("return __probe.invariants()", timeout: 5) as? [String] ?? ["invariants unavailable"]
        if strictInvariants, !r.isEmpty { throw ProbeError("invariant: \(r.joined(separator: "; "))") }
    }

    private func snap(_ name: String) async throws {
        let img = try await host.snapshot(scale: scale)
        try Pixels.writePNG(img, to: outDir.appendingPathComponent("\(name).png"))
        let masks = try await host.js("return JSON.stringify(__probe.masks())") as? String ?? "[]"
        try masks.write(to: outDir.appendingPathComponent("\(name).masks.json"), atomically: true, encoding: .utf8)
    }

    private func dumpState(_ name: String) async throws {
        let json = try await host.js("return JSON.stringify(__probe.state(), null, 1)") as? String ?? "null"
        try json.write(to: outDir.appendingPathComponent("\(name).state.json"), atomically: true, encoding: .utf8)
    }

    private func compare(_ s: [String: Any]) async throws -> String {
        let name = try str(s, "name")
        let against = URL(fileURLWithPath: try str(s, "against"))
        try await snap(name)
        let mine = try Pixels.readPNG(outDir.appendingPathComponent("\(name).png"))
        let ref = try Pixels.readPNG(against)
        var masks = try JSONDecoder().decode([Pixels.Rect].self, from: Data(contentsOf: outDir.appendingPathComponent("\(name).masks.json")))
        let refMasks = against.deletingPathExtension().appendingPathExtension("masks.json")
        if let d = try? Data(contentsOf: refMasks), let m = try? JSONDecoder().decode([Pixels.Rect].self, from: d) { masks += m }
        let r = Pixels.diff(mine, ref, masks: masks, scale: scale, tolerance: s["tolerance"] as? Int ?? 0,
                            heatmap: outDir.appendingPathComponent("\(name).diff.png"))
        let data = try JSONEncoder().encode(r)
        try data.write(to: outDir.appendingPathComponent("\(name).diff.json"))
        let allowed = s["maxDiff"] as? Int ?? 0
        if r.sizeMismatch { throw ProbeError("size mismatch \(mine.width)×\(mine.height) vs \(ref.width)×\(ref.height)") }
        if r.differing > allowed { throw ProbeError("\(r.differing) px differ (allowed \(allowed)), bbox \(r.bbox ?? [])") }
        return "\(r.differing) px differ"
    }

    private func frames_(_ name: String, _ r: [String: Double], budget: Double?) {
        frames[name] = r
        if let budget, (r["p95"] ?? 0) > budget { failures.append("frames \(name): p95 \(r["p95"] ?? 0) ms > \(budget) ms") }
    }

    private func checkBudgets() async throws {
        guard let b = spec["budgets"] as? [String: Double] else { return }
        for s in sampler.summary() {
            if let cap = b["\(s.who)PeakMB"], s.peakMB > cap { failures.append("memory: \(s.who) peaked at \(Int(s.peakMB)) MB > \(Int(cap)) MB") }
            if let cap = b["\(s.who)MeanCPU"], s.meanCPU > cap { failures.append("cpu: \(s.who) mean \(Int(s.meanCPU))% > \(Int(cap))%") }
        }
    }

    private func point(_ s: [String: Any]) async throws -> CGPoint {
        if let text = s["text"] as? String {
            // The innermost visible element whose own text is exactly `text`.
            let t = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let js = "const want='\(t)'; let best=null; for (const el of document.querySelectorAll('body *')) { if ((el.textContent||'').trim()!==want) continue; const r=el.getBoundingClientRect(); if (r.width<1||r.height<1) continue; if (!best||r.width*r.height<best.w*best.h) best={x:r.left,y:r.top,w:r.width,h:r.height}; } return best;"
            guard let r = try await host.js(js) as? [String: Double] else { throw ProbeError("no visible element with text '\(text)'") }
            return CGPoint(x: r["x"]! + r["w"]! / 2, y: r["y"]! + r["h"]! / 2)
        }
        if let sel = s["sel"] as? String {
            let escaped = sel.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            guard let r = try await host.js("return __probe.rect('\(escaped)')") as? [String: Double] else { throw ProbeError("no element \(sel)") }
            return CGPoint(x: r["x"]! + r["w"]! / 2 + (s["dx"] as? Double ?? 0), y: r["y"]! + r["h"]! / 2 + (s["dy"] as? Double ?? 0))
        }
        return CGPoint(x: s["x"] as? Double ?? 0, y: s["y"] as? Double ?? 0)
    }

    private func pt(_ v: Any?) throws -> CGPoint {
        guard let a = v as? [Double], a.count == 2 else { throw ProbeError("point must be [x, y]") }
        return CGPoint(x: a[0], y: a[1])
    }

    /// A path inside this scenario's output folder, or an error: file-changing steps can't reach
    /// a real card or the user's folders.
    private func own(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard SetsIngest.plainPath(url).hasPrefix(SetsIngest.plainPath(outDir) + "/") else { throw ProbeError("\(path) is outside this run's folder: refused") }
        return url
    }

    private func strs(_ s: [String: Any], _ k: String) throws -> [String] {
        guard let a = s[k] as? [String] else { throw ProbeError("step needs '\(k)' list") }
        return try a.map { try str(["v": $0], "v") }
    }

    /// `${OUT}` is this scenario's output folder. `${VAR}` expands from the environment. An unset variable skips the scenario — reported as
    /// SKIP, never as a pass.
    private func str(_ s: [String: Any], _ k: String) throws -> String {
        guard var v = s[k] as? String else { throw ProbeError("step needs '\(k)'") }
        v = v.replacingOccurrences(of: "${OUT}", with: outDir.path)
        v = v.replacingOccurrences(of: "${DISKS}", with: outDir.appendingPathComponent("disks/vol").path)
        while let r = v.range(of: #"\$\{[A-Z0-9_]+\}"#, options: .regularExpression) {
            let name = String(v[r].dropFirst(2).dropLast())
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { throw ProbeSkip(reason: "\(name) is not set") }
            v.replaceSubrange(r, with: value)
        }
        return v
    }

    private func truthy(_ v: Any?) -> Bool {
        switch v {
        case nil, is NSNull: return false
        case let b as Bool: return b
        case let n as NSNumber: return n.doubleValue != 0
        case let s as String: return !s.isEmpty
        default: return true
        }
    }

    private func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
        let enc = { (x: Any?) -> Data? in try? JSONSerialization.data(withJSONObject: [x ?? NSNull()], options: .sortedKeys) }
        return enc(a) == enc(b)
    }

    private func finish(seconds: Double) -> Bool {
        let pass = failures.isEmpty
        let report = Report(scenario: scenarioURL.path, pass: pass, skipped: skipped, failures: failures, steps: steps, resources: sampler.summary(),
                            frames: frames, downloads: host?.downloads ?? [], dialogs: host?.dialogs ?? [], seconds: seconds)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(report).write(to: outDir.appendingPathComponent("report.json"))
        if let host {
            let lines = host.events.compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
            try? lines.joined(separator: "\n").write(to: outDir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        }
        let name = scenarioURL.deletingPathExtension().lastPathComponent
        if let skipped { print("SKIP  \(name)  (\(skipped))"); return pass }
        print("\(pass ? "PASS" : "FAIL")  \(name)  \(String(format: "%.1f", seconds))s  \(steps.count) steps")
        for s in steps where s.note != nil { print("   \(s.ok ? "·" : "✗") #\(s.i) \(s.op): \(s.note!)") }
        for s in sampler.summary() { print("   \(s.who): peak \(Int(s.peakMB)) MB, cpu mean \(Int(s.meanCPU))% peak \(Int(s.peakCPU))%") }
        for (k, r) in frames where !k.hasSuffix(".tiles") { print("   frames \(k): p50 \(r["p50"] ?? 0) p95 \(r["p95"] ?? 0) max \(r["max"] ?? 0) ms") }
        for f in failures { print("   FAIL \(f)") }
        return pass
    }
}

extension ProbeHost {
    func errorsDrained() { clearErrors() }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

struct ProbeSkip: Error { let reason: String }
