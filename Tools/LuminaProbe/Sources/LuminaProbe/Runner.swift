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
            if let clock = spec["clock"] as? String {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.timeZone = .current
                guard let d = f.date(from: clock) else { throw ProbeError("bad clock \(clock)") }
                config["clockBase"] = d.timeIntervalSince1970 * 1000
            }
            let app = (spec["mode"] as? String) == "app"
            host = try await ProbeHost.make(size: CGSize(width: size[0], height: size[1]),
                                            pageRoot: path("pageRoot", default: app ? "Lumina/Sets/Web" : "design/handoff/lumina-cull"),
                                            vendorRoot: path("vendorRoot", default: app ? "Lumina/Sets/Web" : "design/handoff/vendor"),
                                            plumbing: app ? path("plumbing", default: "Lumina/Sets/Web/plumbing.js") : nil,
                                            supportDir: outDir.appendingPathComponent("support", isDirectory: true),
                                            outDir: outDir, config: config)
            host.echo = echo
            sampler.start(interval: ((spec["sampleMs"] as? Double) ?? 250) / 1000) { [host] in
                [(getpid(), "probe"), (host!.webProcessID, "web")]
            }
            try await host.load((spec["page"] as? String) ?? "Lumina Sets v3.dc.html")
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
            _ = try await host.js("__probe.framesStart()")
            for _ in 0..<frames { host.scrollWheel(at: p, dy: dy); try await settle(16) }
            let r = try await host.js("return __probe.framesStop()") as? [String: Double] ?? [:]
            frames_(s["name"] as? String ?? "wheel", r, budget: s["p95Ms"] as? Double)
            return "p95 \(r["p95"] ?? 0) ms, \(Int(r["over33"] ?? 0)) frames > 33 ms"
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
        case "compare":
            return try await compare(s)
        case "openFolder":
            let url = URL(fileURLWithPath: try str(s, "path"))
            guard FileManager.default.fileExists(atPath: url.path) else { throw ProbeError("no such folder \(url.path)") }
            host.pendingOpenPanel = [url]
            if (s["via"] as? String ?? "key") == "key" { try host.key("o", cmd: true) } else { _ = try await host.js("__probe.logic().openFolder()") }
            try await waitFor("const l=__probe.logic(); return !!(l.real && !l.state.realLoad)",
                              timeout: (s["timeoutMs"] as? Double ?? 900_000) / 1000, what: "folder loaded")
            let info = try await host.js("return JSON.stringify(__probe.logic().state.realInfo)")
            return info.map { "\($0)" }
        case "destinations":
            host.chooser.destinations = try strs(s, "paths").map { URL(fileURLWithPath: $0) }
        case "copyTree":
            let from = URL(fileURLWithPath: try str(s, "from")), to = URL(fileURLWithPath: try str(s, "to"))
            try? FileManager.default.removeItem(at: to)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: from, to: to)
        case "mkdir":
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: try str(s, "path")), withIntermediateDirectories: true)
        case "writeFile":
            let url = URL(fileURLWithPath: try str(s, "path"))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(try str(s, "text").utf8).write(to: url)
        case "fs":
            return try fsExpect(s)
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

    // MARK: Fuzzer

    /// Seeded key/mouse storm. Replays exactly from the seed; the last 60 inputs are kept in the
    /// report so a failure can be turned into a scenario.
    private func fuzz(_ s: [String: Any]) async throws -> String {
        var rng = SplitMix(seed: UInt64(s["seed"] as? Int ?? 1))
        let count = s["count"] as? Int ?? 1000
        let checkEvery = s["checkEvery"] as? Int ?? 20
        let gaps = s["gapMs"] as? [Double] ?? [0, 40]
        let exclude = Set(s["exclude"] as? [String] ?? [])
        let keys = (s["keys"] as? [String] ?? Keys.pageKeys).filter { !exclude.contains($0) }
        let mouseRate = s["mouseRate"] as? Double ?? 0.08
        let size = host.webView.bounds.size
        var trail: [String] = []
        for n in 0..<count {
            let roll = rng.unit()
            var input: String
            if roll < mouseRate {
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
                let cmd = ["z", "[", "]"].contains(k) && rng.unit() < 0.3
                input = (cmd ? "⌘" : "") + (shift ? "⇧" : "") + k
                if ["g", "l", " ", "a"].contains(k) && rng.unit() < 0.3 {
                    // held key: down, some time, up (G 100%, L flag, Space large, A auto)
                    try host.key(k, shift: shift, up: false)
                    try await settle(rng.unit() * 400)
                    try host.key(k, shift: shift, down: false)
                    input += " (held)"
                } else {
                    try host.key(k, shift: shift, cmd: cmd)
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
        return "\(count) inputs survived · \(st ?? "")"
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

    private func strs(_ s: [String: Any], _ k: String) throws -> [String] {
        guard let a = s[k] as? [String] else { throw ProbeError("step needs '\(k)' list") }
        return try a.map { try str(["v": $0], "v") }
    }

    /// `${OUT}` is this scenario's output folder. `${VAR}` expands from the environment. An unset variable skips the scenario — reported as
    /// SKIP, never as a pass.
    private func str(_ s: [String: Any], _ k: String) throws -> String {
        guard var v = s[k] as? String else { throw ProbeError("step needs '\(k)'") }
        v = v.replacingOccurrences(of: "${OUT}", with: outDir.path)
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
        for (k, r) in frames { print("   frames \(k): p50 \(r["p50"] ?? 0) p95 \(r["p95"] ?? 0) max \(r["max"] ?? 0) ms") }
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
