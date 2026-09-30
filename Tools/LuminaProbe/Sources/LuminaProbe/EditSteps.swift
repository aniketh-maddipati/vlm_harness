import AppKit
import CoreImage
import Darwin
import ImageIO

/// The Edit canvas and RAW 9 probe steps (`probe.sh edit`, `probe.sh raw9`): thumb-event-to-
/// presented-frame latency over a scripted drag, dropped frames, the rest render after drag end,
/// bases resident; preview vs export ΔE; RAW 9 time-to-first-tile and full region, export time
/// and memory per decoder version, the per-file fallback, and region tiles vs export ΔE per
/// decoder version. Each returns a note plus the failures it found; the Runner merges them.
@MainActor
enum EditSteps {
    struct Outcome { var note: String; var failures: [String] = []; var frames: [String: [String: Double]] = [:] }

    static var gate: Bool { ProcessInfo.processInfo.environment["LUMINA_EDIT_GATE"] != "0" }

    /// A 2 s drag on one slider at `hz` values per second through `lumina.edit.look`, then the
    /// Mac's numbers. Native path: latency is look event (page clock) → drawable presented;
    /// image path: look event → `luminaEditImage` shown, measured in the page.
    static func drag(host: ProbeHost, _ s: [String: Any]) async throws -> Outcome {
        let key = s["slider"] as? String ?? "ev"
        let from = s["from"] as? Double ?? -1, to = s["to"] as? Double ?? 1
        let ms = s["ms"] as? Double ?? 2000, hz = s["hz"] as? Double ?? 120
        let js = """
        const key = '\(key)', from = \(from), to = \(to), ms = \(ms), hz = \(hz);
        await lumina.edit.stats(true);
        const sent = [], shown = []; const prevHook = window.luminaEditImage;
        window.luminaEditImage = (u, seq, tier) => { shown.push({ seq, tier, t: performance.now() }); if (prevHook) prevHook(u, seq, tier); };
        lumina.edit.dragStart();
        const t0 = performance.now(); let n = 0;
        while (performance.now() - t0 < ms) {
          const f = (performance.now() - t0) / ms, v = from + (to - from) * f;
          const seq = lumina.edit.look(key + ':' + v.toFixed(2), { drag: true }); sent.push({ seq, t: performance.now() }); n++;
          await new Promise(r => setTimeout(r, 1000 / hz));
        }
        const tEnd = performance.now(); lumina.edit.dragEnd();
        await new Promise(r => setTimeout(r, 700));
        window.luminaEditImage = prevHook;
        const st = await lumina.edit.stats(false), state = lumina.edit.state();
        // Image path: each look is served by the first image shown with a seq ≥ its own.
        const lat = []; for (const e of sent) { const im = shown.find(i => i.seq >= e.seq && i.t >= e.t); if (im) lat.push(im.t - e.t); }
        lat.sort((a, b) => a - b); const q = p => lat.length ? lat[Math.min(lat.length - 1, Math.floor(p * lat.length))] : 0;
        const rest = shown.filter(i => i.t >= tEnd && i.tier === 'base')[0];
        return Object.assign({}, st, { looks: n, state, pageLatency: { n: lat.length, p50: q(0.5), p95: q(0.95), max: lat[lat.length - 1] || 0, restMs: rest ? rest.t - tEnd : null, images: shown.length } });
        """
        guard let r = try await host.js(js, timeout: ms / 1000 + 20) as? [String: Any] else { throw ProbeError("editDrag: no stats") }
        let path = r["path"] as? String ?? "image"
        let native = path == "native"
        let p50 = native ? r["latencyP50"] as? Double ?? 0 : (r["pageLatency"] as? [String: Any])?["p50"] as? Double ?? 0
        let p95 = native ? r["latencyP95"] as? Double ?? 0 : (r["pageLatency"] as? [String: Any])?["p95"] as? Double ?? 0
        let mx = native ? r["latencyMax"] as? Double ?? 0 : (r["pageLatency"] as? [String: Any])?["max"] as? Double ?? 0
        let dropped = r["droppedFrames"] as? Int ?? 0
        let rest = native ? r["lastRestMs"] as? Double ?? 0 : (r["pageLatency"] as? [String: Any])?["restMs"] as? Double ?? 0
        let sched = r["schedule"] as? [String: Any] ?? [:]
        let bases = r["bases"] as? [String: Any] ?? [:]
        let looks = r["looks"] as? Int ?? 0
        let n = native ? (r["latencyMs"] as? [Double])?.count ?? 0 : (r["pageLatency"] as? [String: Any])?["n"] as? Int ?? 0
        var o = Outcome(note: String(format: "%@ · %d looks · latency p50 %.1f p95 %.1f max %.1f ms (%d samples) · dropped %d · rest %.0f ms · renders small %d base %d coalesced %d · bases %d photos %.0f MB",
                                     path, looks, p50, p95, mx, n, dropped, rest, sched["small"] as? Int ?? 0, sched["base"] as? Int ?? 0, sched["coalesced"] as? Int ?? 0,
                                     bases["residentPhotos"] as? Int ?? 0, Double(bases["bytes"] as? Int ?? 0) / 1_048_576))
        o.frames["edit-\(key)"] = ["p50": p50, "p95": p95, "max": mx, "dropped": Double(dropped), "rest": rest, "looks": Double(looks), "samples": Double(n), "native": native ? 1 : 0]
        guard gate, native else { return o }
        let p95Cap = ProcessInfo.processInfo.environment["LUMINA_EDIT_P95"].flatMap(Double.init) ?? s["p95Ms"] as? Double
        if let cap = p95Cap, p95 > cap { o.failures.append("editDrag \(key): latency p95 \(String(format: "%.1f", p95)) ms > \(cap) ms") }
        if n == 0 { o.failures.append("editDrag \(key): no presented frames were measured") }
        if let cap = s["maxDropped"] as? Int, dropped > cap { o.failures.append("editDrag \(key): \(dropped) dropped frames during the drag (allowed \(cap))") }
        if let cap = s["restMs"] as? Double, rest > cap { o.failures.append("editDrag \(key): rest render \(String(format: "%.0f", rest)) ms after drag end > \(cap) ms") }
        if let cap = s["maxPhotos"] as? Int ?? Optional(3), (bases["residentPhotos"] as? Int ?? 0) > cap { o.failures.append("editDrag: \(bases["residentPhotos"] ?? 0) photos' bases resident > \(cap)") }
        if let cap = s["maxBaseMB"] as? Double ?? Optional(300), Double(bases["bytes"] as? Int ?? 0) / 1_048_576 > cap { o.failures.append("editDrag: bases \(bases["bytes"] ?? 0) bytes > \(cap) MB") }
        return o
    }

    /// The canvas's current look rendered from `base` vs the export of the same look at the same
    /// size (ΔE2000 median ≤ `maxMedianDE`, default 0.5).
    static func parity(host: ProbeHost, _ s: [String: Any], outDir: URL) async throws -> Outcome {
        guard let bridge = host.bridge, let canvas = bridge.canvas else { throw ProbeError("editParity needs app mode") }
        guard let entry = canvas.currentEntry, let preview = canvas.renderToImage() else { throw ProbeError("editParity: no bases on the canvas yet") }
        guard let st = try await host.js("return lumina.edit.state()") as? [String: Any], let rel = st["rel"] as? String, let url = bridge.resolve(rel) else { throw ProbeError("editParity: nothing on the canvas") }
        let look = st["look"] as? String ?? ""
        let px = Int(max(entry.baseSize.width, entry.baseSize.height))
        let export: CGImage
        let pipe = try SetsLookExport.pipeline()
        if entry.source == "jpeg", let p = canvas.currentPreview {
            // The RAW can't be developed here (synthetic fixtures): the export path on the same embedded JPEG.
            let dev = try LookPipeline.developPreview(url: url, offset: p.offset, length: p.length, orientation: p.orientation, longEdge: px)
            let img = pipe.apply(try Look.parse(look), to: dev)
            guard let cg = pipe.context.createCGImage(pipe.clamped(img), from: img.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw ProbeError("export render failed") }
            export = cg
        } else {
            let (data, _) = try SetsLookExport.render(raw: url, look: look, px: px, format: "png", decoder: entry.decoder)
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ProbeError("export PNG unreadable") }
            export = cg
        }
        try Pixels.writePNG(preview, to: outDir.appendingPathComponent("parity-canvas.png"))
        try Pixels.writePNG(export, to: outDir.appendingPathComponent("parity-export.png"))
        let de = LookParity.stats(preview, export)
        let cap = s["maxMedianDE"] as? Double ?? 0.5
        var o = Outcome(note: String(format: "canvas (%@, raw %d) vs export at %d px: ΔE median %.3f mean %.3f p95 %.3f max %.2f over %d px (%d×%d vs %d×%d)",
                                     entry.source, entry.decoder ?? 0, px, de.median, de.mean, de.p95, de.max, de.pixels, preview.width, preview.height, export.width, export.height))
        try JSONEncoder().encode(de).write(to: outDir.appendingPathComponent("parity.json"))
        if abs(preview.width - export.width) > 2 || abs(preview.height - export.height) > 2 { o.failures.append("editParity: sizes differ \(preview.width)×\(preview.height) vs \(export.width)×\(export.height)") }
        if de.median > cap { o.failures.append("editParity: ΔE median \(String(format: "%.3f", de.median)) > \(cap)") }
        return o
    }

    /// RAW 9 (§8): on the first `count` ARWs of `folder`: the decoder map, time-to-first-tile and
    /// time-to-full-region for the loupe, export time and memory per decoder version, the forced
    /// fallback on one file, and region tiles vs export ΔE per decoder version.
    static func raw9(host: ProbeHost, _ s: [String: Any], folder: URL, outDir: URL) async throws -> Outcome {
        guard let bridge = host.bridge, let canvas = bridge.canvas else { throw ProbeError("raw9 needs app mode") }
        let fm = FileManager.default
        let raws = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(s["count"] as? Int ?? 2)
        guard let first = raws.first else { throw ProbeError("no ARWs in \(folder.path)") }
        let roiD = s["roi"] as? [String: Double] ?? ["x": 0.4, "y": 0.4, "w": 0.2, "h": 0.2]
        let roi = LookCanvasSchedule.ROI(x: roiD["x"] ?? 0.4, y: roiD["y"] ?? 0.4, w: roiD["w"] ?? 0.2, h: roiD["h"] ?? 0.2)
        var report: [String: Any] = ["folder": folder.path, "files": raws.map(\.lastPathComponent), "canvas": canvas.path.rawValue,
                                     "os": ProcessInfo.processInfo.operatingSystemVersionString, "memoryGB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                                     "thermal": LookDecoderProbe.thermalLevel(ProcessInfo.processInfo.thermalState), "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled]
        var o = Outcome(note: "")
        let versions = LookPipeline.supportedDecoderVersions(url: first)
        report["supported"] = versions
        guard !versions.isEmpty else {
            report["raw"] = false
            try write(report, to: outDir)
            o.note = "\(first.lastPathComponent) is not a RAW Core Image reads (synthetic fixture?): RAW 9 checks need real ARWs in LUMINA_EDIT_DIR · fallback path: n/a"
            return o
        }
        let rules = canvas.pipeline.rules
        let info = LookDecoderProbe.probe(url: first, rules: rules)
        report["capability"] = ["supported": info.supported, "raw9": info.raw9, "fastest": info.fastest ?? 0, "developMs512": info.developMs] as [String: Any]
        let newest = info.newest ?? versions.max()!
        let older = LookRawPolicy.fallback(after: newest, supported: info.supported)
        let rel = folder.lastPathComponent + "/" + first.lastPathComponent
        var lines: [String] = ["decoders \(info.supported) raw9=\(info.raw9) fastest=\(info.fastest ?? 0) (512 px: \(info.developMs))"]

        // Region tiles at the newest version (the loupe's tier), first tile and full region.
        var regions: [[String: Any]] = []
        for v in [newest] + (older.map { [$0] } ?? []) {
            canvas.tiles.drop()
            let region = try await regionRender(canvas.tiles, rel: rel, url: first, decoder: v, roi: roi, seq: v)
            regions.append(["decoder": v, "firstTileMs": region.firstTileMs, "fullMs": region.totalMs, "tiles": region.tiles, "fromCache": region.fromCache,
                            "rect": [Int(region.rect.minX), Int(region.rect.minY), Int(region.rect.width), Int(region.rect.height)],
                            "facts": ["sharpness": region.facts.sharpness, "clipHi": region.facts.clipHi, "clipLo": region.facts.clipLo, "source": region.facts.source]])
            lines.append(String(format: "raw %d region %d tiles: first tile %.0f ms, full %.0f ms · sharpness %.4f clip hi %.4f lo %.4f", v, region.tiles, region.firstTileMs, region.totalMs, region.facts.sharpness, region.facts.clipHi, region.facts.clipLo))
            // Panning reuses tiles: the same region again is all cache hits.
            let again = try await regionRender(canvas.tiles, rel: rel, url: first, decoder: v, roi: roi, seq: v + 100)
            if again.fromCache != again.tiles { o.failures.append("raw9: the second pass over the same region rendered \(again.tiles - again.fromCache) tiles again") }
            if v == newest, gate {
                if let cap = s["firstTileMs"] as? Double, region.firstTileMs > cap { o.failures.append("raw9: first tile \(Int(region.firstTileMs)) ms > \(Int(cap)) ms") }
                if let cap = s["fullMs"] as? Double, region.totalMs > cap { o.failures.append("raw9: full region \(Int(region.totalMs)) ms > \(Int(cap)) ms") }
            }
        }
        report["regions"] = regions

        // Export per file, per version: time and footprint.
        var exports: [[String: Any]] = []
        for url in raws {
            let mp = LookPipeline.nativeSize(url: url).map { Int(($0.width * $0.height / 1e6).rounded()) } ?? 0
            for v in Set([older, newest].compactMap { $0 }).sorted() {
                let before = footprintMB()
                let t0 = Date()
                do {
                    let (data, out) = try SetsLookExport.render(raw: url, look: "ev:+0.30 con:+10", px: nil, format: "jpg", decoder: v)
                    let after = footprintMB()
                    exports.append(["file": url.lastPathComponent, "mp": mp, "decoder": v, "ms": Int(Date().timeIntervalSince(t0) * 1000), "bytes": data.count, "footprintBeforeMB": before, "footprintAfterMB": after, "used": out.label])
                    lines.append(String(format: "export %@ (%d MP) raw %d: %d ms · footprint %.0f → %.0f MB", url.lastPathComponent, mp, v, Int(Date().timeIntervalSince(t0) * 1000), before, after))
                } catch {
                    exports.append(["file": url.lastPathComponent, "mp": mp, "decoder": v, "error": "\(error)"])
                    o.failures.append("raw9: export of \(url.lastPathComponent) with raw \(v) failed: \(error)")
                }
            }
        }
        report["exports"] = exports

        // The fallback path, forced: a version this Mac doesn't have on one file.
        do {
            let (_, out) = try SetsLookExport.render(raw: first, look: "", px: 1024, format: "jpg", decoder: 99)
            report["fallback"] = ["forced": 99, "fellBackFrom": out.fellBackFrom ?? 0, "used": out.decoder ?? 0, "reason": out.reason ?? "", "label": out.label] as [String: Any]
            lines.append("fallback: forced raw 99 on \(first.lastPathComponent) → \(out.label)")
            if out.fellBackFrom != 99 || out.decoder != newest { o.failures.append("raw9: the forced failure did not fall back to raw \(newest): \(out.label)") }
        } catch {
            o.failures.append("raw9: the forced failure did not fall back: \(error)")
        }

        // Parity per decoder version: region tiles vs the export graph at the same region.
        var parity: [[String: Any]] = []
        let cap = s["maxMedianDE"] as? Double ?? 0.5
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        for v in info.supported {
            let region = try await regionRender(canvas.tiles, rel: rel, url: first, decoder: v, roi: roi, seq: 1000 + v)
            let pipe = canvas.pipeline
            let tilesImg = pipe.apply(Look(), to: LookPipeline.Developed(image: region.image, asShot: region.asShot), crop: false)
            let dev = try LookPipeline.develop(url: first, longEdge: nil, rules: pipe.rules, decoderVersion: v)
            let exportImg = pipe.apply(Look(), to: dev)
            guard let a = pipe.context.createCGImage(pipe.clamped(tilesImg), from: region.rect, format: .RGBA8, colorSpace: srgb),
                  let b = pipe.context.createCGImage(pipe.clamped(exportImg), from: region.rect, format: .RGBA8, colorSpace: srgb) else { o.failures.append("raw9: region render failed for raw \(v)"); continue }
            let de = LookParity.stats(a, b)
            parity.append(["decoder": v, "median": de.median, "mean": de.mean, "p95": de.p95, "max": de.max, "pixels": de.pixels])
            lines.append(String(format: "parity raw %d: region tiles vs export ΔE median %.3f p95 %.3f max %.2f", v, de.median, de.p95, de.max))
            if de.median > cap { o.failures.append("raw9: raw \(v) region tiles vs export ΔE median \(String(format: "%.3f", de.median)) > \(cap)") }
            if v == newest { try Pixels.writePNG(a, to: outDir.appendingPathComponent("region-tiles-raw\(v).png")); try Pixels.writePNG(b, to: outDir.appendingPathComponent("region-export-raw\(v).png")) }
        }
        report["parity"] = parity
        report["raw"] = true
        try write(report, to: outDir)
        o.note = "\n  " + lines.joined(separator: "\n  ")
        return o
    }

    private static func regionRender(_ tiles: LookRegionTiles, rel: String, url: URL, decoder: Int, roi: LookCanvasSchedule.ROI, seq: Int) async throws -> LookRegionTiles.Region {
        try await withCheckedThrowingContinuation { c in
            tiles.region(rel: rel, url: url, decoder: decoder, nr: nil, roi: roi, seq: seq, first: { _ in }, done: { c.resume(with: $0) })
        }
    }

    private static func write(_ report: [String: Any], to outDir: URL) throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: outDir.appendingPathComponent("raw9.json"))
    }

    /// phys_footprint of this process, MB.
    static func footprintMB() -> Double {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : 0
    }
}
