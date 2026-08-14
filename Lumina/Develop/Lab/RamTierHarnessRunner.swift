#if !LUMINA_SHIPPING_APP
import AppKit
import CoreImage
import Darwin
import Foundation

/// HEAVY RAM tier gate — `--ram-harness [ledger.json]`.
///
/// Measures peak resident footprint while exercising decode tiers named in
/// `design/fixture-manifest.md` (mixed-200, card-clean-500, mixed-tier bodies).
@MainActor
enum RamTierHarnessRunner {

    struct TierSpec: Sendable {
        let id: String
        let frameCount: Int
        let maxPixelSize: Int?
        let allowRAW: Bool
        let ceilingBytes: Int
    }

    static let tierSpecs: [TierSpec] = [
        TierSpec(
            id: "mixed-200",
            frameCount: 200,
            maxPixelSize: PhotoImageTier.gridMaxPixelSize,
            allowRAW: false,
            ceilingBytes: PhotoImageCacheBudget.gridTierCeilingBytes
        ),
        TierSpec(
            id: "card-clean-500",
            frameCount: 500,
            maxPixelSize: PhotoImageTier.gridMaxPixelSize,
            allowRAW: false,
            ceilingBytes: PhotoImageCacheBudget.gridTierCeilingBytes
        ),
        TierSpec(
            id: "mixed-tier-preview",
            frameCount: 60,
            maxPixelSize: 1600,
            allowRAW: false,
            ceilingBytes: PhotoImageCacheBudget.previewTierCeilingBytes
        ),
    ]

    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ram-harness") else { return false }

        let outURL: URL
        if let idx = args.firstIndex(of: "--ram-harness"),
           args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            outURL = URL(fileURLWithPath: args[idx + 1], isDirectory: false)
        } else {
            outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/harness/ledgers/ram-tiers.json")
        }

        var finished = false
        var exitCode: Int32 = 1
        Task { @MainActor in
            exitCode = await run(outURL: outURL)
            finished = true
        }
        while !finished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    private static func run(outURL: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var ledger: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": "measured",
            "gates_active": true,
            "proposal": "W6 byte ceilings await contract ruling — see PhotoImageCacheBudget",
            "totalCeilingBytes": PhotoImageCacheBudget.totalCeilingBytes,
            "prefetchConcurrencyWidth": PhotoImageCacheBudget.prefetchConcurrencyWidth,
        ]

        var tierResults: [[String: Any]] = []
        var failures = 0
        let baselineRSS = MemoryFootprint.residentBytes()

        for spec in tierSpecs {
            let result = await measureTier(spec, baselineRSS: baselineRSS)
            tierResults.append(result.report)
            if result.pass == false { failures += 1 }
        }

        ledger["tiers"] = tierResults
        ledger["failures"] = failures

        if let data = try? JSONSerialization.data(withJSONObject: ledger, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outURL)
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return failures == 0 ? 0 : 1
    }

    private struct TierMeasurement {
        let report: [String: Any]
        let pass: Bool
    }

    private static func measureTier(_ spec: TierSpec, baselineRSS: UInt64) async -> TierMeasurement {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-ram-\(spec.id)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var paths: [String] = []
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            for index in 0..<spec.frameCount {
                let url = tempDir.appendingPathComponent(String(format: "IMG_%04d.jpg", index))
                guard let jpeg = synthesizeJPEG(index: index) else { continue }
                try jpeg.write(to: url)
                paths.append(url.path)
            }
        } catch {
            return TierMeasurement(
                report: [
                    "id": spec.id,
                    "status": "blocked",
                    "reason": "fixture synthesis failed: \(error.localizedDescription)",
                ],
                pass: false
            )
        }

        await PhotoImageCache.shared.beginSession(projectName: "ram-harness-\(spec.id)")
        let rssBefore = MemoryFootprint.residentBytes()
        var peakDuring = rssBefore

        await PhotoImageCache.shared.prefetch(paths, maxPixelSize: spec.maxPixelSize, allowRAW: spec.allowRAW)

        // Wait for prefetch queue to drain (bounded — poll with timeout).
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let pending = await PhotoImageCache.shared.prefetchDiagnostics().pending
            let active = await PhotoImageCache.shared.prefetchDiagnostics().active
            peakDuring = max(peakDuring, MemoryFootprint.residentBytes())
            if pending == 0, active == 0 { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // Force-load any stragglers sequentially to capture worst-case retention.
        for path in paths.prefix(min(paths.count, spec.frameCount)) {
            _ = await PhotoImageCache.shared.load(path: path, maxPixelSize: spec.maxPixelSize, allowRAW: spec.allowRAW)
            peakDuring = max(peakDuring, MemoryFootprint.residentBytes())
        }

        let cacheBytes = await PhotoImageCache.shared.trackedMemoryBytes()
        await PhotoImageCache.shared.endSession()
        let rssAfter = MemoryFootprint.residentBytes()
        let deltaPeak = peakDuring > rssBefore ? peakDuring - rssBefore : 0

        let pass = peakDuring <= baselineRSS + UInt64(spec.ceilingBytes) * 2
            && cacheBytes <= PhotoImageCacheBudget.totalCeilingBytes

        return TierMeasurement(
            report: [
                "id": spec.id,
                "frameCount": spec.frameCount,
                "maxPixelSize": spec.maxPixelSize as Any,
                "ceilingBytes": spec.ceilingBytes,
                "rssBeforeBytes": baselineRSS,
                "peakRssBytes": peakDuring,
                "deltaPeakBytes": deltaPeak,
                "cacheTrackedBytes": cacheBytes,
                "rssAfterBytes": rssAfter,
                "pass": pass,
            ],
            pass: pass
        )
    }

    private static func synthesizeJPEG(index: Int) -> Data? {
        let w = 640 + (index % 5) * 32
        let h = 480 + (index % 7) * 24
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let r = CGFloat((index * 37) % 255) / 255
        ctx.setFillColor(CGColor(red: r, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

enum MemoryFootprint {
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}

#endif
