import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Lumina

/// Is the decoder gap a fixed offset we could calibrate away, or irreducible difference?
///
/// On frames the photographer left at Lightroom defaults, Lumina's neutral render still sits
/// ~5.12 mean ΔE from their export. The oracle floor on EDITED frames is 5.58 — only 0.46
/// above it. If that 5.12 is a systematic pipeline offset, one global correction removes most
/// of it and the slider domain gets its room back. If it is per-frame, it is a ceiling and no
/// amount of slider modelling matters.
///
/// ΔE alone cannot tell those apart, so this dumps PAIRED PIXELS: Lumina's neutral render and
/// the photographer's export, both resampled to the same small grid. The fit and its
/// cross-validation happen in Python, where a leave-one-frame-out check is cheap.
///
/// Identity frames only — the photographer accepted Lightroom's default rendering, so any
/// difference is pipeline and not taste. Crops are excluded for the usual reason.
///
///   LUMINA_FLOOR_FRAMES  identity-frames.jsonl
///   LUMINA_FLOOR_OUT     output folder
@MainActor
final class DecoderFloorProbeTests: XCTestCase {

    private static let decodeLongEdge = 640
    /// Paired-sample grid. 32x32 = 1024 pixel pairs per frame, plenty to fit 12 parameters
    /// while staying small enough to ship as JSON.
    private static let gridEdge = 32

    private let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private func grid(_ cg: CGImage) -> [UInt8]? {
        let n = Self.gridEdge
        var rgba = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &rgba, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        return rgba
    }

    private func sample(_ image: CIImage) -> [UInt8]? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1,
              let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { return nil }
        return grid(cg)
    }

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 4 * 60 * 60
    }

    func testDumpPairedPixelsOnIdentityFrames() async throws {
        let env = ProcessInfo.processInfo.environment
        let framesURL = URL(fileURLWithPath: env["LUMINA_FLOOR_FRAMES"]
            ?? NSString(string: "~/LuminaEvidence/export-labels-01/identity-frames.jsonl")
                .expandingTildeInPath)
        let outDir = URL(fileURLWithPath: env["LUMINA_FLOOR_OUT"]
            ?? NSString(string: "~/LuminaEvidence/decoder-floor-01").expandingTildeInPath,
            isDirectory: true)

        guard let text = try? String(contentsOf: framesURL, encoding: .utf8) else {
            throw XCTSkip("identity-frames.jsonl required at \(framesURL.path)")
        }
        let frames: [[String: Any]] = text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }

        func uncropped(_ l: [String: Any]) -> Bool {
            let g = ["cropTop": 0.0, "cropLeft": 0.0, "cropBottom": 1.0, "cropRight": 1.0,
                     "cropAngle": 0.0]
            return g.allSatisfy { abs((l[$0.key] as? Double ?? $0.value) - $0.value) < 1e-6 }
        }

        var rows: [[String: Any]] = []
        var skipped = 0
        for frame in frames where uncropped(frame) {
            guard let rawPath = frame["raw"] as? String,
                  let jpegPath = frame["jpeg"] as? String,
                  FileManager.default.fileExists(atPath: rawPath),
                  FileManager.default.fileExists(atPath: jpegPath),
                  let exportImage = CIImage(contentsOf: URL(fileURLWithPath: jpegPath)),
                  let exportGrid = sample(DevelopRenderGraph.normalizeOrigin(exportImage))
            else { skipped += 1; continue }

            let url = URL(fileURLWithPath: rawPath)
            let session = PreparedRawSession(assetID: UUID(), rawURL: url)
            guard let staged = await session.rawStageImage(
                intent: RawIntent.neutral, targetLongEdge: Self.decodeLongEdge, tier: .authoritative
            ) else { skipped += 1; continue }
            let oriented = OrientedDisplayImage.aligning(staged.image, toFile: url)
            guard let renderGrid = sample(DevelopRenderGraph.normalizeOrigin(oriented))
            else { skipped += 1; continue }

            rows.append([
                "raw": rawPath,
                "jpeg": jpegPath,
                "dateTimeOriginal": frame["dateTimeOriginal"] as? String ?? "",
                "cameraProfile": frame["cameraProfile"] as? String ?? "",
                "gridEdge": Self.gridEdge,
                "render": renderGrid.map { Int($0) },
                "export": exportGrid.map { Int($0) },
            ])
        }

        XCTAssertGreaterThan(rows.count, 0, "no identity frame produced a pair")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var blob = ""
        for r in rows {
            blob += String(decoding: try JSONSerialization.data(withJSONObject: r,
                                                                options: [.sortedKeys]),
                           as: UTF8.self) + "\n"
        }
        try blob.write(to: outDir.appendingPathComponent("paired-pixels.jsonl"),
                       atomically: true, encoding: .utf8)
        print("FLOOR-PROBE rows=\(rows.count) skipped=\(skipped)")
    }
}
