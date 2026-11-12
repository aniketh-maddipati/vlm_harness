import AppKit
import CoreImage
import Foundation

/// `editZoom` (`probe.sh zoom`): a pinch on the native Edit canvas from fit to each of `zooms`
/// (×, relative to fit), the page's rest after it, then what the canvas shows once it is sharp.
/// Per zoom: (a) time from the rest to the first frame drawn from detail at the zoom's real
/// resolution (`stats().lastSharpMs`), (b) sharpness, the Laplacian variance of the canvas's
/// picture vs the same region of a full-size export placed the same way (and their ΔE), and
/// (c) frame latency during the pinch (placement → frame; refreshes missed with one waiting).
/// The pinch is driven through `zoom(to:)` exactly as plumbing's `canvasZoom` does, at `hz`.
@MainActor
enum ZoomSteps {
    static func run(host: ProbeHost, _ s: [String: Any], outDir: URL) async throws -> EditSteps.Outcome {
        guard let bridge = host.bridge, let canvas = bridge.canvas else { throw ProbeError("editZoom needs app mode") }
        guard canvas.path == .native else { return EditSteps.Outcome(note: "image path: no native canvas, nothing to zoom") }
        guard let entry = canvas.currentEntry, let size = canvas.drawableSize, size.width > 1 else { throw ProbeError("editZoom: no bases on the canvas yet") }
        guard let st = try await host.js("return lumina.edit.state()") as? [String: Any], let rel = st["rel"] as? String, let url = bridge.resolve(rel) else { throw ProbeError("editZoom: nothing on the canvas") }
        let zooms = s["zooms"] as? [Double] ?? [2, 4]
        let pinchMs = s["pinchMs"] as? Double ?? 400, hz = s["hz"] as? Double ?? 120
        let restAfter = s["restAfterMs"] as? Double ?? 300          // plumbing's ZOOM_REST
        let sharpWait = s["sharpTimeoutMs"] as? Double ?? 5000
        let cx = s["cx"] as? Double ?? 0.45, cy = s["cy"] as? Double ?? 0.42
        let pa = entry.baseSize.width / max(1, entry.baseSize.height), ca = size.width / max(1, size.height)
        let w0 = max(1, ca / pa), h0 = max(1, pa / ca)
        func roi(_ f: Double) -> LookCanvasSchedule.ROI {
            let w = w0 / f, h = h0 / f
            let x = w < 1 ? min(max(0, cx - w / 2), 1 - w) : 0.5 - w / 2
            let y = h < 1 ? min(max(0, cy - h / 2), 1 - h) : 0.5 - h / 2
            return LookCanvasSchedule.ROI(x: x, y: y, w: w, h: h)
        }

        // The export the canvas is compared with: the look at full size on the pinned decoder.
        let look = canvas.currentLook
        let parsed = try Look.parse(look)
        let pipe = try SetsLookExport.pipeline()
        let decoder = canvas.currentRegionDecoder
        let t0 = Date()
        let dev = try LookPipeline.develop(url: url, longEdge: nil, rules: pipe.rules, decoderVersion: decoder, nr: parsed.nr, dust: parsed.dust)
        let exported = pipe.output(pipe.apply(parsed, to: dev))
        let exportExtent = exported.extent
        var o = EditSteps.Outcome(note: "")
        var lines = [String(format: "%@ · raw %d export %d×%d (graph %.0f ms) · canvas %d×%d px", rel, decoder ?? 0, Int(exportExtent.width), Int(exportExtent.height), Date().timeIntervalSince(t0) * 1000, Int(size.width), Int(size.height))]
        var report: [String: Any] = ["rel": rel, "decoder": decoder ?? 0, "drawable": [size.width, size.height], "look": look]
        var results: [[String: Any]] = []

        for z in zooms {
            // Back to fit, the canvas at rest there.
            canvas.zoom(to: nil, rest: true)
            try await Task.sleep(nanoseconds: 600_000_000)
            canvas.resetMeasures()
            let before = canvas.snapshot()
            let sharpBefore = before["lastSharpMs"] as? Double
            let sharpCountBefore = before["sharpCount"] as? Int ?? 0
            // The pinch: eased from 1 to z, one placement per 1/hz s, then the page's quiet before rest.
            let p0 = Date()
            var n = 0
            while true {
                let f = min(1, Date().timeIntervalSince(p0) * 1000 / pinchMs)
                let e = 1 - pow(1 - f, 3)
                canvas.zoom(to: roi(1 + (z - 1) * e))
                n += 1
                if f >= 1 { break }
                try await Task.sleep(nanoseconds: UInt64(1e9 / hz))
            }
            try await Task.sleep(nanoseconds: UInt64(restAfter * 1e6))
            let pinch = canvas.snapshot()
            let lat = (pinch["zoomLatencyMs"] as? [Double] ?? []).sorted()
            let q = { (p: Double) -> Double in lat.isEmpty ? 0 : lat[min(lat.count - 1, Int(Double(lat.count) * p))] }
            let missed = pinch["zoomMissed"] as? Int ?? 0, busy = pinch["zoomBusy"] as? Int ?? 0
            let settledFrames = pinch["settledFrames"] as? Int ?? 0
            // Rest: time to the first frame drawn from detail (a canvas without it never says so).
            let r0 = Date()
            canvas.zoom(to: roi(z), rest: true)
            var sharpMs: Double?
            let supportsSharp = sharpBefore != nil
            if supportsSharp {
                while Date().timeIntervalSince(r0) * 1000 < sharpWait {
                    try await Task.sleep(nanoseconds: 10_000_000)
                    let snap = canvas.snapshot()
                    if (snap["sharpCount"] as? Int ?? 0) > sharpCountBefore, let ms = snap["lastSharpMs"] as? Double { sharpMs = ms; break }
                }
            } else {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
            let after = canvas.snapshot()
            guard let shown = canvas.renderShown() else { o.failures.append("editZoom ×\(z): the canvas rendered nothing"); continue }
            // The export, placed the way compose places the zoomed region.
            let r = roi(z)
            let vis = CGRect(x: exportExtent.minX + r.x * exportExtent.width, y: exportExtent.minY + (1 - r.y - r.h) * exportExtent.height, width: r.w * exportExtent.width, height: r.h * exportExtent.height)
            let k = min(size.width / vis.width, size.height / vis.height)
            let ox = ((size.width - vis.width * k) / 2).rounded(), oy = ((size.height - vis.height * k) / 2).rounded()
            let placed = exported.cropped(to: vis).transformed(by: CGAffineTransform(translationX: -vis.minX, y: -vis.minY).concatenating(CGAffineTransform(scaleX: k, y: k)).concatenating(CGAffineTransform(translationX: ox, y: oy)))
            guard let ref = pipe.context.createCGImage(placed, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { o.failures.append("editZoom ×\(z): export render failed"); continue }
            // The photo's part of the drawable, less a 10 % border (top-left origin for the bitmaps).
            let photoBox = CGRect(x: ox, y: size.height - oy - vis.height * k, width: vis.width * k, height: vis.height * k).insetBy(dx: vis.width * k * 0.1, dy: vis.height * k * 0.1)
            let a = laplacianVariance(shown, in: photoBox), b = laplacianVariance(ref, in: photoBox)
            let de = LookParity.stats(shown, ref)
            try Pixels.writePNG(shown, to: outDir.appendingPathComponent("zoom-\(Int(z))x-canvas.png"))
            try Pixels.writePNG(ref, to: outDir.appendingPathComponent("zoom-\(Int(z))x-export.png"))
            let ratio = b > 0 ? a / b : 0
            let fullScale = k       // drawable px per export px
            results.append(["zoom": z, "drawablePerExportPx": fullScale, "placements": n, "pinchLatencyP50": q(0.5), "pinchLatencyP95": q(0.95), "pinchLatencyMax": lat.last ?? 0,
                            "pinchFrames": lat.count, "pinchMissed": missed, "pinchBusy": busy, "settledFrames": settledFrames, "sharpMs": sharpMs ?? -1,
                            "lapCanvas": a, "lapExport": b, "sharpRatio": ratio, "deMedian": de.median, "deP95": de.p95,
                            "detailScale": after["detailScale"] ?? 0, "regionTiles": (after["tiles"] as? [String: Any])?["resident"] ?? 0, "tilesMB": Double((after["tiles"] as? [String: Any])?["bytes"] as? Int ?? 0) / 1_048_576])
            lines.append(String(format: "×%.0f (%.2f drawable px per export px): pinch %d placements, frames %d, latency p50 %.1f p95 %.1f max %.1f ms, missed %d busy %d (settled frames %d) · sharp %@ · Laplacian var canvas %.5f export %.5f ratio %.2f · ΔE median %.2f p95 %.2f",
                                z, fullScale, n, lat.count, q(0.5), q(0.95), lat.last ?? 0, missed, busy, settledFrames, sharpMs.map { String(format: "%.0f ms", $0) } ?? (supportsSharp ? "never" : "n/a"), a, b, ratio, de.median, de.p95))
            guard EditSteps.gate else { continue }
            if let cap = s["p95Ms"] as? Double, q(0.95) > cap { o.failures.append(String(format: "editZoom ×%.0f: pinch frame latency p95 %.1f ms > %.0f", z, q(0.95), cap)) }
            if let cap = s["maxMissed"] as? Int, missed > cap { o.failures.append("editZoom ×\(z): \(missed) refreshes missed during the pinch (allowed \(cap))") }
            if lat.isEmpty { o.failures.append("editZoom ×\(z): no pinch frames were measured") }
            if let min = s["minSharpRatio"] as? Double, ratio < min { o.failures.append(String(format: "editZoom ×%.0f: sharpness %.2f of the export's < %.2f", z, ratio, min)) }
            if let cap = s["maxSharpMs"] as? Double, (sharpMs ?? .infinity) > cap { o.failures.append("editZoom ×\(z): sharp after \(sharpMs.map { String(format: "%.0f ms", $0) } ?? "never") > \(Int(cap)) ms") }
        }
        canvas.zoom(to: nil, rest: true)
        report["zooms"] = results
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: outDir.appendingPathComponent("zoom.json"))
        for r in results {
            let z = r["zoom"] as? Double ?? 0
            o.frames["zoom-\(Int(z))x"] = ["p50": r["pinchLatencyP50"] as? Double ?? 0, "p95": r["pinchLatencyP95"] as? Double ?? 0, "dropped": Double(r["pinchMissed"] as? Int ?? 0),
                                          "sharpMs": r["sharpMs"] as? Double ?? -1, "sharpRatio": r["sharpRatio"] as? Double ?? 0]
        }
        o.note = "\n  " + lines.joined(separator: "\n  ")
        return o
    }

    /// The variance of the 4-neighbour Laplacian of luma (0 … 1) inside `box` (top-left origin).
    static func laplacianVariance(_ image: CGImage, in box: CGRect) -> Double {
        let px = Pixels.rgba(image)
        let w = image.width, h = image.height
        let x0 = max(1, Int(box.minX)), x1 = min(w - 2, Int(box.maxX)), y0 = max(1, Int(box.minY)), y1 = min(h - 2, Int(box.maxY))
        guard x1 > x0, y1 > y0 else { return 0 }
        func y(_ i: Int, _ j: Int) -> Double {
            let k = 4 * (j * w + i)
            return (0.2126 * Double(px[k]) + 0.7152 * Double(px[k + 1]) + 0.0722 * Double(px[k + 2])) / 255
        }
        var sum = 0.0, sum2 = 0.0, n = 0.0
        for j in y0...y1 {
            for i in x0...x1 {
                let l = 4 * y(i, j) - y(i - 1, j) - y(i + 1, j) - y(i, j - 1) - y(i, j + 1)
                sum += l; sum2 += l * l; n += 1
            }
        }
        let m = sum / n
        return sum2 / n - m * m
    }
}
