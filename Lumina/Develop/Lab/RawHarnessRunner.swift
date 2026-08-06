import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic headless harness — `--raw-harness [output-dir]`.
///
/// Runs unit checks (generation ordering, intent domains, XMP merge safety)
/// plus live measurements on real ARW fixtures (session prepare, RAW-stage
/// cache behavior, interactive/settled/1:1 timings, preview↔export fidelity,
/// Lightroom handoff with exiftool verification). Writes a JSON report and
/// PNG evidence, then exits.
@MainActor
enum RawHarnessRunner {

    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--raw-harness") else { return false }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let outDir: URL
        if let idx = args.firstIndex(of: "--raw-harness"),
           args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/raw-perf", isDirectory: true)
        }

        var finished = false
        var exitCode: Int32 = 0
        Task {
            exitCode = await run(outDir: outDir)
            finished = true
        }
        while !finished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    // MARK: - Main run

    private static func run(outDir: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "build": buildConfiguration(),
            "mappingVersion": PreparedRawSession.decoderMappingVersion,
            "workingSpaceVersion": DevelopColorPolicy.workingSpaceVersion,
        ]
        var failures = 0

        report["unitChecks"] = unitChecks(failures: &failures)
        report["xmpMerge"] = xmpMergeChecks(failures: &failures)

        if let dir = DevelopLabFixtures.resolveRawDirectory(),
           let raw = DevelopLabFixtures.discoverRAWFiles(in: dir, limit: 1).first {
            report["fixture"] = raw.path
            report["live"] = await liveChecks(rawURL: raw, outDir: outDir, failures: &failures)
            report["liveFrames"] = await writeLiveFrameSequence(rawURL: raw, outDir: outDir, failures: &failures)
        } else {
            report["live"] = ["status": "blocked", "reason": "no RAW fixture directory (LUMINA_DEVELOP_RAW_DIR)"]
        }

        report["failures"] = failures
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outDir.appendingPathComponent("raw_harness_report.json"))
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - Pure unit checks

    private static func unitChecks(failures: inout Int) -> [[String: Any]] {
        var results: [[String: Any]] = []
        func expect(_ condition: Bool, _ name: String) {
            results.append(["name": name, "pass": condition])
            if !condition { failures += 1 }
        }

        // Latest-wins ordering
        expect(RenderGenerationOrdering.shouldPresent(candidate: 5, presented: nil), "gen: first result presents")
        expect(RenderGenerationOrdering.shouldPresent(candidate: 6, presented: 5), "gen: newer presents")
        expect(!RenderGenerationOrdering.shouldPresent(candidate: 4, presented: 5), "gen: stale rejected")

        // Intent domain separation
        let base = EditRecipe()
        let lookOnly = base.updating { $0.contrast = 25 }
        let rawChange = base.updating { $0.exposure = 0.5 }
        expect(base.rawIntent.fingerprint == lookOnly.rawIntent.fingerprint,
               "intents: look change preserves RawIntent")
        expect(base.lookIntent.fingerprint != lookOnly.lookIntent.fingerprint,
               "intents: look change alters LookIntent")
        expect(base.rawIntent.fingerprint != rawChange.rawIntent.fingerprint,
               "intents: exposure invalidates RawIntent")
        expect(base.geometryIntent.fingerprint == rawChange.geometryIntent.fingerprint,
               "intents: exposure preserves GeometryIntent")

        // Untrusted controls do not touch any render-relevant intent
        let disabled = base.updating { $0.whites = 50; $0.blacks = -30; $0.clarity = 40; $0.texture = 20; $0.dehaze = 10 }
        expect(disabled.rawIntent.fingerprint == base.rawIntent.fingerprint
                && disabled.lookIntent.fingerprint == base.lookIntent.fingerprint,
               "honesty: disabled controls render-inert")

        // As-shot WB semantics
        expect(base.rawIntent.isAsShotWhiteBalance, "wb: default is as-shot")
        expect(!base.updating { $0.temperature = 5200 }.rawIntent.isAsShotWhiteBalance, "wb: override detected")

        // Stage-aware cache keys
        func key(_ recipe: EditRecipe, _ quality: DevelopRenderQuality) -> String {
            RawRenderRequest(
                generation: 1, photoID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                rawURL: URL(fileURLWithPath: "/tmp/x.arw"), recipe: recipe, quality: quality
            ).cacheKey
        }
        expect(key(base, .settled) != key(lookOnly, .settled), "cache: look change changes final key")
        expect(key(base, .interactive) != key(base, .settled), "cache: tier separates keys")
        expect(key(base, .settled) == key(base.updating { $0.whites = 80 }, .settled),
               "cache: disabled control does not thrash keys")

        // Retouch (clone heal): fingerprint participates, and the render
        // changes pixels at the spot while leaving distant pixels untouched.
        let spot = RetouchSpot(x: 0.25, y: 0.5, radius: 0.05, sourceDX: 0.3, sourceDY: 0)
        let healed = base.updating { $0.retouch = [spot] }
        expect(base.valueFingerprint != healed.valueFingerprint, "heal: fingerprint includes spots")

        // Left half black, right half white → healing at x=0.25 clones white over black.
        let width = 200, height = 100
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: width / 2, height: height))
        let white = CIImage(color: .white).cropped(to: CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        let composite = white.composited(over: black.composited(over: CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: width, height: height)
        )))
        let healedImage = DevelopRenderGraph.applyRetouch([spot], to: composite)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        func luma(_ image: CIImage, x: Int, y: Int) -> Double {
            var px = [UInt8](repeating: 0, count: 4)
            ctx.render(image, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return Double(px[0]) / 255
        }
        let atSpot = luma(healedImage, x: 50, y: 50)      // was black, donor is white
        let farAway = luma(healedImage, x: 10, y: 90)     // untouched black corner
        expect(atSpot > 0.6, "heal: donor pixels cloned onto spot center")
        expect(farAway < 0.1, "heal: distant pixels untouched")

        return results
    }

    // MARK: - XMP merge checks

    private static func xmpMergeChecks(failures: inout Int) -> [[String: Any]] {
        var results: [[String: Any]] = []
        func expect(_ condition: Bool, _ name: String) {
            results.append(["name": name, "pass": condition])
            if !condition { failures += 1 }
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-xmp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let xmp = dir.appendingPathComponent("shot.xmp")

        let recipe = EditRecipe().updating { $0.exposure = 0.4; $0.contrast = 12; $0.temperature = 5300 }

        do {
            // 1. Fresh create
            let first = try LightroomHandoffService.mergeSidecar(recipe: recipe, at: xmp)
            expect(first == .created, "xmp: fresh sidecar created")

            // 2. Re-merge by Lumina — clean update, no conflict
            let second = try LightroomHandoffService.mergeSidecar(
                recipe: recipe.updating { $0.exposure = 0.6 }, at: xmp
            )
            expect(second == .updated, "xmp: lumina re-merge is clean update")

            // 3. External edit on a managed field + a foreign property
            var contents = try String(contentsOf: xmp, encoding: .utf8)
            contents = contents.replacingOccurrences(
                of: "crs:Exposure2012=\"+0.60\"",
                with: "crs:Exposure2012=\"+1.25\" foreign:CustomLook=\"Kodachrome\" xmlns:foreign=\"http://example.com/ns/\""
            )
            try contents.write(to: xmp, atomically: true, encoding: .utf8)

            let third = try LightroomHandoffService.mergeSidecar(
                recipe: recipe.updating { $0.exposure = 0.7 }, at: xmp
            )
            expect(third == .conflictExternalEdits, "xmp: external edit detected as conflict")

            let merged = try String(contentsOf: xmp, encoding: .utf8)
            expect(merged.contains("Kodachrome"), "xmp: foreign property preserved through merge")
            expect(merged.contains("lumina:LastMergeConflict"), "xmp: conflict recorded in sidecar")
            expect(!merged.contains("crs:Whites2012") && !merged.contains("crs:Clarity2012"),
                   "xmp: disabled controls never emitted")

            // 4. Failure injection: unparseable sidecar → original preserved as
            // backup, fresh sidecar written, flagged as conflict. Never data loss.
            let corrupt = dir.appendingPathComponent("corrupt.xmp")
            try "<xmp broken & unparseable".write(to: corrupt, atomically: true, encoding: .utf8)
            let corruptOutcome = try LightroomHandoffService.mergeSidecar(recipe: recipe, at: corrupt)
            expect(corruptOutcome == .conflictExternalEdits, "xmp: corrupt sidecar surfaces as conflict")
            let backup = corrupt.appendingPathExtension("lumina-backup")
            let backupContents = (try? String(contentsOf: backup, encoding: .utf8)) ?? ""
            expect(backupContents.contains("unparseable"), "xmp: corrupt original preserved as backup")
            let rewritten = try String(contentsOf: corrupt, encoding: .utf8)
            expect(rewritten.contains("lumina:RecipeFingerprint"), "xmp: fresh sidecar written after corruption")
        } catch {
            expect(false, "xmp: merge flow threw \(error)")
        }

        return results
    }

    // MARK: - Live ARW checks

    private static func liveChecks(rawURL: URL, outDir: URL, failures: inout Int) async -> [String: Any] {
        var live: [String: Any] = [:]
        let photoID = UUID()

        // Session prepare + capabilities
        let prepStart = CFAbsoluteTimeGetCurrent()
        let session = await PreparedRawSessionRegistry.shared.session(for: photoID, rawURL: rawURL)
        let (caps, meta) = await session.capabilityReport()
        live["prepareMs"] = round1((CFAbsoluteTimeGetCurrent() - prepStart) * 1000)
        live["capabilities"] = caps.summary
        if let meta {
            live["pixels"] = "\(meta.pixelWidth)x\(meta.pixelHeight)"
            live["megapixels"] = round1(Double(meta.pixelWidth * meta.pixelHeight) / 1_000_000)
        }

        let recipe = EditRecipe().updating {
            $0.exposure = 0.3; $0.contrast = 15; $0.highlights = -25; $0.shadows = 20
            $0.temperature = 5600; $0.sharpness = 40; $0.luminanceNR = 15
        }

        func request(_ recipe: EditRecipe, _ quality: DevelopRenderQuality, region: DevelopRenderRegion = .full) -> RawRenderRequest {
            RawRenderRequest(generation: 0, photoID: photoID, rawURL: rawURL, recipe: recipe, quality: quality, region: region)
        }

        // Interactive cold, then look-only scrubs (RAW-stage cache must hit).
        // Graph construction is lazy — force GPU evaluation the way the Metal
        // destination would, so timings are end-to-end honest.
        let coldStart = CFAbsoluteTimeGetCurrent()
        let cold = await DevelopRenderGraph.render(request(recipe, .interactive))
        if let image = cold.ciImage { forceEvaluate(image) }
        live["interactiveColdMs"] = round1((CFAbsoluteTimeGetCurrent() - coldStart) * 1000)
        live["interactiveFidelity"] = cold.fidelity.rawValue
        if cold.usedProxyFallback { failures += 1; live["interactiveProxyFallback"] = true }

        var scrubTimes: [Double] = []
        var rawStageHits = 0
        for step in 1...20 {
            let scrub = recipe.updating { $0.contrast = Double(step) }
            let start = CFAbsoluteTimeGetCurrent()
            let result = await DevelopRenderGraph.render(request(scrub, .interactive))
            if let image = result.ciImage { forceEvaluate(image) }
            scrubTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if result.rawStageCacheHit { rawStageHits += 1 }
        }
        let sorted = scrubTimes.sorted()
        live["interactiveScrub"] = [
            "count": scrubTimes.count,
            "p50Ms": round1(sorted[sorted.count / 2]),
            "p95Ms": round1(sorted[Int(Double(sorted.count) * 0.95) - 1]),
            "maxMs": round1(sorted.last ?? 0),
            "rawStageCacheHits": rawStageHits,
        ]
        if rawStageHits < 18 { failures += 1; live["rawStageCacheProblem"] = true }

        // Control pixel-difference gates — every exposed control must move pixels.
        live["controlPixelDiffs"] = await controlPixelDiffs(
            photoID: photoID, rawURL: rawURL, failures: &failures
        )

        // Scheduler drain-loop: rapid scrub must publish multiple distinct
        // revisions without waiting for mouse-up (no cancel-discard freeze).
        live["scrubDrain"] = await scrubDrainCheck(
            photoID: photoID, rawURL: rawURL, failures: &failures
        )

        // RawIntent change must miss the RAW-stage cache
        let rawChanged = await DevelopRenderGraph.render(
            request(recipe.updating { $0.exposure = 1.1 }, .interactive)
        )
        live["rawIntentInvalidates"] = !rawChanged.rawStageCacheHit
        if rawChanged.rawStageCacheHit { failures += 1 }

        // Settled + 1:1
        let settled = await DevelopRenderGraph.render(request(recipe, .settled))
        live["settledMs"] = round1(settled.durationMs)
        live["settledFidelity"] = settled.fidelity.rawValue

        // Interactive ↔ settled discontinuity — the visible "settle jump".
        // If the draft-scale decode drifts from the authoritative decode,
        // draft mode must be disabled; this gate keeps that honest.
        // Bitmaps are materialized via forDisplay:false so both frames land
        // in the same (working) color space.
        let iBitmap = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 0, photoID: photoID, rawURL: rawURL, recipe: recipe,
            quality: .interactive, forDisplay: false
        ))
        let sBitmap = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 0, photoID: photoID, rawURL: rawURL, recipe: recipe,
            quality: .settled, forDisplay: false
        ))
        if let iCG = iBitmap.cgImage, let sCG = sBitmap.cgImage,
           let ia = resampleSRGB(iCG, longEdge: 512),
           let sa = resampleSRGB(sCG, longEdge: 512),
           ia.count == sa.count, !ia.isEmpty {
            var sum = 0.0
            for i in stride(from: 0, to: ia.count, by: 4) {
                let dl = 0.2126 * (Double(ia[i]) - Double(sa[i]))
                    + 0.7152 * (Double(ia[i + 1]) - Double(sa[i + 1]))
                    + 0.0722 * (Double(ia[i + 2]) - Double(sa[i + 2]))
                sum += abs(dl)
            }
            let maeLuma = sum / Double(ia.count / 4)
            live["interactiveSettledDiscontinuity"] = [
                "maeLuma_8bit": round2(maeLuma),
                "gate": "fail if > 12",
            ]
            if maeLuma > 12 { failures += 1; live["draftDiscontinuityProblem"] = true }
        }
        let oneToOne = await DevelopRenderGraph.render(
            request(recipe, .oneToOne, region: DevelopRenderRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        )
        live["oneToOneMs"] = round1(oneToOne.durationMs)

        // Fidelity: settled preview vs downsampled export, same recipe
        let export = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 0, photoID: photoID, rawURL: rawURL, recipe: recipe,
            quality: .export, source: .originalRAW, longEdgeCap: 0, forDisplay: false
        ))
        // Graph+bitmap-request time only; authoritative full-export wall time is
        // handoff.totalMs (render + 16-bit ProPhoto TIFF encode + sidecar + receipt).
        live["exportGraphMs"] = round1(export.durationMs)
        live["exportColorSpace"] = export.colorSpaceName
        if let previewCG = settled.cgImage, let exportCG = export.cgImage {
            live["fidelity"] = fidelityCompare(
                preview: previewCG, export: exportCG, outDir: outDir, failures: &failures
            )
        } else {
            live["fidelity"] = ["status": "blocked", "reason": "missing settled or export bitmap"]
            failures += 1
        }

        // Full Lightroom handoff on a scratch copy of the RAW's sidecar space
        live["handoff"] = await handoffCheck(photoID: photoID, rawURL: rawURL, recipe: recipe, outDir: outDir, failures: &failures)

        return live
    }

    private static func fidelityCompare(preview: CGImage, export: CGImage, outDir: URL, failures: inout Int) -> [String: Any] {
        let target = 1024
        guard let a = resampleSRGB(preview, longEdge: target),
              let b = resampleSRGB(export, longEdge: target),
              a.count == b.count, !a.isEmpty else {
            failures += 1
            return ["status": "failed", "reason": "resample mismatch"]
        }
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, maxDelta = 0.0
        var clippedA = 0, clippedB = 0
        let pixels = a.count / 4
        for i in stride(from: 0, to: a.count, by: 4) {
            let dr = abs(Double(a[i]) - Double(b[i]))
            let dg = abs(Double(a[i + 1]) - Double(b[i + 1]))
            let db = abs(Double(a[i + 2]) - Double(b[i + 2]))
            sumR += dr; sumG += dg; sumB += db
            maxDelta = max(maxDelta, max(dr, max(dg, db)))
            if a[i] >= 254 || a[i + 1] >= 254 || a[i + 2] >= 254 || a[i] <= 1 || a[i + 1] <= 1 || a[i + 2] <= 1 { clippedA += 1 }
            if b[i] >= 254 || b[i + 1] >= 254 || b[i + 2] >= 254 || b[i] <= 1 || b[i + 1] <= 1 || b[i + 2] <= 1 { clippedB += 1 }
        }

        // ΔE2000 in Lab (subsampled ×2 for speed — statistically stable at 1024px).
        var deltaEs: [Double] = []
        deltaEs.reserveCapacity(pixels / 2 + 1)
        for i in stride(from: 0, to: a.count, by: 8) {
            let lab1 = srgbToLab(a[i], a[i + 1], a[i + 2])
            let lab2 = srgbToLab(b[i], b[i + 1], b[i + 2])
            deltaEs.append(deltaE2000(lab1, lab2))
        }
        deltaEs.sort()
        let deMean = deltaEs.reduce(0, +) / Double(max(deltaEs.count, 1))
        let deP95 = deltaEs[min(Int(Double(deltaEs.count) * 0.95), deltaEs.count - 1)]

        // Dims derive deterministically from the export image for SSIM + diff PNG.
        let scale = Double(target) / Double(max(export.width, export.height))
        let nw = Int(Double(export.width) * scale), nh = Int(Double(export.height) * scale)
        var ssim: Double?
        if nw * nh * 4 == a.count {
            var lumaA = [Double](repeating: 0, count: nw * nh)
            var lumaB = [Double](repeating: 0, count: nw * nh)
            for p in 0..<(nw * nh) {
                let i = p * 4
                lumaA[p] = 0.2126 * Double(a[i]) + 0.7152 * Double(a[i + 1]) + 0.0722 * Double(a[i + 2])
                lumaB[p] = 0.2126 * Double(b[i]) + 0.7152 * Double(b[i + 1]) + 0.0722 * Double(b[i + 2])
            }
            ssim = ssimLuma(lumaA, lumaB, width: nw, height: nh)
            writeDifferencePNG(a, b, width: nw, height: nh,
                               to: outDir.appendingPathComponent("fidelity_difference.png"))
        }

        writePNG(preview, to: outDir.appendingPathComponent("fidelity_preview.png"), longEdge: target)
        writePNG(export, to: outDir.appendingPathComponent("fidelity_export.png"), longEdge: target)
        var out: [String: Any] = [
            "status": "measured",
            "size": target,
            "maeR_8bit": round2(sumR / Double(pixels)),
            "maeG_8bit": round2(sumG / Double(pixels)),
            "maeB_8bit": round2(sumB / Double(pixels)),
            "maxChannelDelta_8bit": round2(maxDelta),
            "deltaE2000Mean": round2(deMean),
            "deltaE2000P95": round2(deP95),
            "clippedFractionPreview": round2(Double(clippedA) / Double(pixels)),
            "clippedFractionExport": round2(Double(clippedB) / Double(pixels)),
            "note": "settled preview (display space) vs full export (ProPhoto) resampled to sRGB \(target)px; difference PNG amplified ×8",
        ]
        if let ssim { out["ssimLuma"] = round2(ssim) }
        return out
    }

    /// sRGB 8-bit → CIE Lab (D65).
    private static func srgbToLab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (Double, Double, Double) {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double(r8) / 255), g = lin(Double(g8) / 255), b = lin(Double(b8) / 255)
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0) }
        let fx = f(x / 0.95047), fy = f(y), fz = f(z / 1.08883)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// CIEDE2000 color difference.
    private static func deltaE2000(_ lab1: (Double, Double, Double), _ lab2: (Double, Double, Double)) -> Double {
        let (l1, a1, b1) = lab1, (l2, a2, b2) = lab2
        let c1 = sqrt(a1 * a1 + b1 * b1), c2 = sqrt(a2 * a2 + b2 * b2)
        let cBar = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow(25.0, 7))))
        let a1p = a1 * (1 + g), a2p = a2 * (1 + g)
        let c1p = sqrt(a1p * a1p + b1 * b1), c2p = sqrt(a2p * a2p + b2 * b2)
        func hue(_ a: Double, _ b: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            var h = atan2(b, a) * 180 / .pi
            if h < 0 { h += 360 }
            return h
        }
        let h1p = hue(a1p, b1), h2p = hue(a2p, b2)
        let dLp = l2 - l1
        let dCp = c2p - c1p
        var dhp = h2p - h1p
        if c1p * c2p == 0 { dhp = 0 } else if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        let dHp = 2 * sqrt(c1p * c2p) * sin(dhp * .pi / 360)
        let lBp = (l1 + l2) / 2
        let cBp = (c1p + c2p) / 2
        var hBp = (h1p + h2p) / 2
        if c1p * c2p != 0, abs(h1p - h2p) > 180 { hBp += (h1p + h2p < 360) ? 180 : -180 }
        let t = 1 - 0.17 * cos((hBp - 30) * .pi / 180) + 0.24 * cos(2 * hBp * .pi / 180)
            + 0.32 * cos((3 * hBp + 6) * .pi / 180) - 0.20 * cos((4 * hBp - 63) * .pi / 180)
        let dTheta = 30 * exp(-pow((hBp - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cBp, 7) / (pow(cBp, 7) + pow(25.0, 7)))
        let sl = 1 + 0.015 * pow(lBp - 50, 2) / sqrt(20 + pow(lBp - 50, 2))
        let sc = 1 + 0.045 * cBp
        let sh = 1 + 0.015 * cBp * t
        let rt = -sin(2 * dTheta * .pi / 180) * rc
        return sqrt(pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2)
            + rt * (dCp / sc) * (dHp / sh))
    }

    /// Mean SSIM over 8×8 luma windows (C1/C2 per Wang et al., L = 255).
    private static func ssimLuma(_ a: [Double], _ b: [Double], width: Int, height: Int) -> Double {
        let win = 8
        let c1 = pow(0.01 * 255.0, 2.0), c2 = pow(0.03 * 255.0, 2.0)
        var total = 0.0
        var count = 0
        var by = 0
        while by + win <= height {
            var bx = 0
            while bx + win <= width {
                var sumA = 0.0, sumB = 0.0
                for y in by..<(by + win) {
                    for x in bx..<(bx + win) {
                        sumA += a[y * width + x]; sumB += b[y * width + x]
                    }
                }
                let n = Double(win * win)
                let muA = sumA / n, muB = sumB / n
                var varA = 0.0, varB = 0.0, cov = 0.0
                for y in by..<(by + win) {
                    for x in bx..<(bx + win) {
                        let da = a[y * width + x] - muA, db = b[y * width + x] - muB
                        varA += da * da; varB += db * db; cov += da * db
                    }
                }
                varA /= n - 1; varB /= n - 1; cov /= n - 1
                total += ((2 * muA * muB + c1) * (2 * cov + c2))
                    / ((muA * muA + muB * muB + c1) * (varA + varB + c2))
                count += 1
                bx += win
            }
            by += win
        }
        return count > 0 ? total / Double(count) : 1
    }

    /// Grayscale |a−b| max-channel difference, amplified ×8 for visibility.
    private static func writeDifferencePNG(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, to url: URL) {
        var out = [UInt8](repeating: 255, count: a.count)
        for i in stride(from: 0, to: a.count, by: 4) {
            let d = max(abs(Int(a[i]) - Int(b[i])),
                        max(abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2]))))
            let v = UInt8(min(d * 8, 255))
            out[i] = v; out[i + 1] = v; out[i + 2] = v; out[i + 3] = 255
        }
        out.withUnsafeMutableBytes { ptr in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                    data: ptr.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let img = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    private static func handoffCheck(photoID: UUID, rawURL: URL, recipe: EditRecipe, outDir: URL, failures: inout Int) async -> [String: Any] {
        var out: [String: Any] = [:]
        // Work on a scratch directory so the harness never mutates fixture sidecars.
        let scratch = outDir.appendingPathComponent("handoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let linkedRAW = scratch.appendingPathComponent(rawURL.lastPathComponent)
        try? FileManager.default.removeItem(at: linkedRAW)
        do {
            try FileManager.default.createSymbolicLink(at: linkedRAW, withDestinationURL: rawURL)
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await LightroomHandoffService.performHandoff(
                photoID: photoID,
                rawURL: linkedRAW,
                recipe: recipe,
                tiffDestination: scratch.appendingPathComponent("handoff.tif")
            )
            out["totalMs"] = round1((CFAbsoluteTimeGetCurrent() - start) * 1000)
            out["mergeOutcome"] = result.mergeOutcome.rawValue
            out["tiffSHA256"] = result.tiffSHA256 ?? "nil"
            out["colorSpace"] = result.colorSpaceName

            if ExifToolService.isAvailable, let tiff = result.tiffURL {
                let data = try ExifToolService.runDataPublic(arguments: [
                    "-json", "-BitsPerSample", "-Compression", "-ProfileDescription", "-ImageWidth", "-ImageHeight",
                    tiff.path,
                ])
                if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let item = json.first {
                    out["exiftool"] = [
                        "bitsPerSample": "\(item["BitsPerSample"] ?? "?")",
                        "compression": "\(item["Compression"] ?? "?")",
                        "profile": "\(item["ProfileDescription"] ?? "?")",
                        "size": "\(item["ImageWidth"] ?? "?")x\(item["ImageHeight"] ?? "?")",
                    ]
                    let bits = "\(item["BitsPerSample"] ?? "")"
                    if !bits.contains("16") { failures += 1; out["bitDepthProblem"] = true }
                }
            } else {
                out["exiftool"] = "unavailable"
            }
        } catch {
            failures += 1
            out["error"] = "\(error)"
        }
        return out
    }

    /// Deterministic frame sequence — exposure / warmth / highlights / shadows
    /// sweeps written as PNGs (Metal-path CIImage forced to bitmap).
    private static func writeLiveFrameSequence(
        rawURL: URL,
        outDir: URL,
        failures: inout Int
    ) async -> [String: Any] {
        let framesDir = outDir.appendingPathComponent("live-frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        let photoID = UUID()
        let sweeps: [(String, (Int) -> EditRecipe)] = [
            ("exposure", { i in EditRecipe().updating { $0.exposure = -1.0 + Double(i) * 0.2 } }),
            ("warmth", { i in EditRecipe().updating { $0.temperature = 4000 + Double(i) * 400 } }),
            ("highlights", { i in EditRecipe().updating { $0.highlights = -80 + Double(i) * 16 } }),
            ("shadows", { i in EditRecipe().updating { $0.shadows = -80 + Double(i) * 16 } }),
        ]
        var written: [String: Any] = [:]
        for (name, make) in sweeps {
            var paths: [String] = []
            var distinct = 0
            var prevBytes: [UInt8]?
            for i in 0..<11 {
                let recipe = make(i)
                let result = await DevelopRenderGraph.render(RawRenderRequest(
                    generation: UInt64(i + 1),
                    photoID: photoID,
                    rawURL: rawURL,
                    recipe: recipe,
                    quality: .interactive,
                    forDisplay: false
                ))
                guard let cg = result.cgImage else {
                    failures += 1
                    continue
                }
                let file = framesDir.appendingPathComponent(String(format: "%@_%02d.png", name, i))
                writePNG(cg, to: file, longEdge: 640)
                paths.append(file.lastPathComponent)
                if let pixels = resampleSRGB(cg, longEdge: 128) {
                    if let prev = prevBytes {
                        var diff = 0.0
                        for k in 0..<pixels.count { diff += abs(Double(pixels[k]) - Double(prev[k])) }
                        // Adjacent-frame threshold is intentionally low — highlights/shadows
                        // change locally; min/max MAE is gated separately in controlPixelDiffs.
                        if diff / Double(pixels.count) > 0.15 { distinct += 1 }
                    } else {
                        distinct += 1
                    }
                    prevBytes = pixels
                }
            }
            written[name] = ["frames": paths.count, "distinctFromPrev": distinct, "files": paths]
            if distinct < 5 { failures += 1 }
        }
        // Before/after pair from neutral vs treated.
        let before = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 0, photoID: photoID, rawURL: rawURL, recipe: .neutral,
            quality: .settled, forDisplay: false
        ))
        let after = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 1, photoID: photoID, rawURL: rawURL,
            recipe: EditRecipe().updating { $0.exposure = 0.6; $0.temperature = 5200; $0.shadows = 30 },
            quality: .settled, forDisplay: false
        ))
        if let b = before.cgImage {
            writePNG(b, to: framesDir.appendingPathComponent("before.png"), longEdge: 960)
        }
        if let a = after.cgImage {
            writePNG(a, to: framesDir.appendingPathComponent("after.png"), longEdge: 960)
        }
        written["beforeAfter"] = ["before": "before.png", "after": "after.png"]
        written["directory"] = framesDir.path
        return written
    }

    /// Min/max render for each trusted control — mean absolute channel delta
    /// must be meaningfully nonzero.
    private static func controlPixelDiffs(
        photoID: UUID,
        rawURL: URL,
        failures: inout Int
    ) async -> [String: Any] {
        struct ControlSpec {
            let name: String
            let lo: (inout EditRecipe) -> Void
            let hi: (inout EditRecipe) -> Void
            let minMAE: Double
        }
        let controls: [ControlSpec] = [
            .init(name: "exposure", lo: { $0.exposure = -1.5 }, hi: { $0.exposure = 1.5 }, minMAE: 2),
            .init(name: "temperature", lo: { $0.temperature = 4000 }, hi: { $0.temperature = 8000 }, minMAE: 1),
            .init(name: "tint", lo: { $0.tint = -30 }, hi: { $0.tint = 30 }, minMAE: 0.5),
            .init(name: "highlights", lo: { $0.highlights = -80 }, hi: { $0.highlights = 80 }, minMAE: 0.5),
            .init(name: "shadows", lo: { $0.shadows = -80 }, hi: { $0.shadows = 80 }, minMAE: 0.5),
            .init(name: "contrast", lo: { $0.contrast = -60 }, hi: { $0.contrast = 60 }, minMAE: 0.5),
            .init(name: "saturation", lo: { $0.saturation = -60 }, hi: { $0.saturation = 60 }, minMAE: 0.5),
        ]

        var out: [String: Any] = [:]
        for control in controls {
            let loRecipe = EditRecipe().updating(control.lo)
            let hiRecipe = EditRecipe().updating(control.hi)
            let lo = await DevelopRenderGraph.render(RawRenderRequest(
                generation: 0, photoID: photoID, rawURL: rawURL, recipe: loRecipe,
                quality: .interactive, forDisplay: false
            ))
            let hi = await DevelopRenderGraph.render(RawRenderRequest(
                generation: 0, photoID: photoID, rawURL: rawURL, recipe: hiRecipe,
                quality: .interactive, forDisplay: false
            ))
            guard let loCG = lo.cgImage, let hiCG = hi.cgImage,
                  let a = resampleSRGB(loCG, longEdge: 256),
                  let b = resampleSRGB(hiCG, longEdge: 256),
                  a.count == b.count, !a.isEmpty else {
                out[control.name] = ["status": "blocked"]
                failures += 1
                continue
            }
            var sum = 0.0
            for i in 0..<a.count { sum += abs(Double(a[i]) - Double(b[i])) }
            let mae = sum / Double(a.count)
            let ok = mae >= control.minMAE
            out[control.name] = ["mae_8bit": round2(mae), "pass": ok, "minMAE": control.minMAE]
            if !ok { failures += 1 }
        }
        return out
    }

    /// Rapid interactive scrub through the real scheduler — must publish ≥20
    /// distinct recipe revisions without requiring a pause (mouse-up).
    private static func scrubDrainCheck(
        photoID: UUID,
        rawURL: URL,
        failures: inout Int
    ) async -> [String: Any] {
        let scheduler = DevelopRenderScheduler()
        scheduler.activeEditorIdentity = nil
        let steps = 40
        for step in 0..<steps {
            let recipe = EditRecipe().updating { $0.exposure = Double(step) * 0.05 }
            let t0 = CFAbsoluteTimeGetCurrent()
            scheduler.scrub(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: nil,
                recipe: recipe,
                recipeRevision: UInt64(step + 1),
                inputEventAt: t0,
                controlName: "exposure",
                controlValue: recipe.exposure
            )
            // Yield so the drain loop can start evaluates between ticks.
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        // Allow the drain loop to converge on the final revision.
        for _ in 0..<200 {
            if let rev = scheduler.displayedRevision[photoID], rev == UInt64(steps) {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        // Count how many distinct revisions appeared during/after the sweep.
        // We sample presented revision history via metrics.completed.
        let completed = scheduler.metrics.completed
        let stale = scheduler.metrics.staleRejected
        let finalRev = scheduler.displayedRevision[photoID] ?? 0
        let i2vP50 = scheduler.metrics.inputToVisiblePercentile(0.50)
        let i2vP95 = scheduler.metrics.inputToVisiblePercentile(0.95)
        let distinctEnough = completed >= 20
        let converged = finalRev == UInt64(steps)
        if !distinctEnough || !converged { failures += 1 }
        return [
            "steps": steps,
            "completedPublishes": completed,
            "staleRejected": stale,
            "finalDisplayedRevision": finalRev,
            "convergedOnLatest": converged,
            "atLeast20Frames": distinctEnough,
            "inputToVisibleP50Ms": i2vP50.map { round1($0) } as Any,
            "inputToVisibleP95Ms": i2vP95.map { round1($0) } as Any,
            "lifecycleSessionPrepares": PreparedRawSession.prepareCount,
            "note": "Interactive lane drains latest-wins; cancel no longer discards finished frames.",
        ]
    }

    /// Evaluate a lazy CIImage graph to pixels (like the Metal destination does).
    private static func forceEvaluate(_ image: CIImage) {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return }
        let width = Int(extent.width), height = Int(extent.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 8)
        buffer.withUnsafeMutableBytes { ptr in
            DevelopRenderGraph.sharedContext.render(
                image,
                toBitmap: ptr.baseAddress!,
                rowBytes: width * 8,
                bounds: extent,
                format: .RGBAh,
                colorSpace: DevelopColorPolicy.displayColorSpace
            )
        }
    }

    // MARK: - Bitmap helpers

    private static func resampleSRGB(_ image: CGImage, longEdge: Int) -> [UInt8]? {
        let w = image.width, h = image.height
        let scale = Double(longEdge) / Double(max(w, h))
        let nw = Int(Double(w) * scale), nh = Int(Double(h) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: nw * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let data = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: nw * nh * 4))
    }

    private static func writePNG(_ image: CGImage, to url: URL, longEdge: Int) {
        let w = image.width, h = image.height
        let scale = Double(longEdge) / Double(max(w, h))
        let nw = Int(Double(w) * scale), nh = Int(Double(h) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: nw * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let scaled = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, scaled, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func buildConfiguration() -> String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
