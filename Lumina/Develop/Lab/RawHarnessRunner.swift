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
        let pixels = a.count / 4
        for i in stride(from: 0, to: a.count, by: 4) {
            let dr = abs(Double(a[i]) - Double(b[i]))
            let dg = abs(Double(a[i + 1]) - Double(b[i + 1]))
            let db = abs(Double(a[i + 2]) - Double(b[i + 2]))
            sumR += dr; sumG += dg; sumB += db
            maxDelta = max(maxDelta, max(dr, max(dg, db)))
        }
        writePNG(preview, to: outDir.appendingPathComponent("fidelity_preview.png"), longEdge: target)
        writePNG(export, to: outDir.appendingPathComponent("fidelity_export.png"), longEdge: target)
        return [
            "status": "measured",
            "size": target,
            "maeR_8bit": round2(sumR / Double(pixels)),
            "maeG_8bit": round2(sumG / Double(pixels)),
            "maeB_8bit": round2(sumB / Double(pixels)),
            "maxChannelDelta_8bit": round2(maxDelta),
            "note": "settled preview (display space) vs full export (ProPhoto) resampled to sRGB \(target)px",
        ]
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
