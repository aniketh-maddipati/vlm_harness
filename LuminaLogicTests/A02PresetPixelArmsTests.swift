import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Lumina

/// W6 follow-up — settle in PIXEL space what W6 could only claim in slider space.
///
/// W6 found that a constant preset taken from the photographer's own median beats the
/// shipping Auto by ~70% on recipe-space MAE. W4 then showed that recipe-space MAE is a
/// poor proxy for what is visible: A00 looks weak on sliders yet beats as-shot by 27%
/// in pixels, because pixel ΔE is dominated by exposure and white balance while slider
/// MAE over-weights controls that barely move pixels. So the W6 claim is unproven until
/// it is rendered. This renders it.
///
/// Four arms per frame, all through the production graph at the authoritative tier:
///   neutral  as-shot, no look          the bar W4 measured
///   a00      AutoDevelop's proposal    the incumbent
///   preset   the constant from W6      the claim under test
///   hand     the photographer's own six tone values
///
/// DELIBERATE: every arm leaves white balance at as-shot and varies ONLY the six tone
/// controls. The reference is the photographer's export, which carries their WB choice,
/// so all four arms share a common WB error against it. That offset is constant across
/// arms, so it cannot change their ranking — but it does mean the absolute ΔE here is
/// not comparable to W4's numbers, and no cross-run comparison should be made.
///
/// Runs on the UNCROPPED subset only (457 of 482). A cropped export cannot be compared
/// against an uncropped render without the crop dominating the difference.
///
///   LUMINA_ARMS_LABELS  labels.jsonl  (default ~/LuminaEvidence/export-labels-01/labels.jsonl)
///   LUMINA_ARMS_PRESET  preset.json   (default ~/LuminaEvidence/a02-regression/preset.json)
///   LUMINA_ARMS_OUT     output folder (default ~/LuminaEvidence/a02-regression)
@MainActor
final class A02PresetPixelArmsTests: XCTestCase {

    private static let decodeLongEdge = 640
    private static let compareSize = (384, 256)

    private let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private struct Bitmap { let width: Int; let height: Int; let rgba: [UInt8] }

    private static let linearLUT: [Double] = (0..<256).map { v in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func lab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (Double, Double, Double) {
        let rl = linearLUT[Int(r)], gl = linearLUT[Int(g)], bl = linearLUT[Int(b)]
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func meanDeltaEAndL(_ a: Bitmap, _ b: Bitmap) -> (Double, Double)? {
        guard a.width == b.width, a.height == b.height, a.width > 0 else { return nil }
        var de = 0.0, dl = 0.0, n = 0.0
        for i in stride(from: 0, to: a.rgba.count, by: 4) {
            let la = lab(a.rgba[i], a.rgba[i + 1], a.rgba[i + 2])
            let lb = lab(b.rgba[i], b.rgba[i + 1], b.rgba[i + 2])
            de += ((la.0 - lb.0) * (la.0 - lb.0) + (la.1 - lb.1) * (la.1 - lb.1)
                + (la.2 - lb.2) * (la.2 - lb.2)).squareRoot()
            dl += la.0 - lb.0
            n += 1
        }
        guard n > 0 else { return nil }
        return (de / n, dl / n)
    }

    private func draw(_ cg: CGImage) -> Bitmap? {
        let (w, h) = Self.compareSize
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(width: w, height: h, rgba: rgba)
    }

    private func rasterize(_ image: CIImage) -> Bitmap? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1,
              let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { return nil }
        return draw(cg)
    }

    private func reference(at path: String) -> Bitmap? {
        guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return rasterize(DevelopRenderGraph.normalizeOrigin(image))
    }

    private func tone(_ v: [String: Double]) -> EditRecipe {
        EditRecipe.neutral.updating { r in
            r.exposure = v["exposure"] ?? 0
            r.contrast = v["contrast"] ?? 0
            r.highlights = v["highlights"] ?? 0
            r.shadows = v["shadows"] ?? 0
            r.vibrance = v["vibrance"] ?? 0
            r.saturation = v["saturation"] ?? 0
        }
    }

    private func render(_ session: PreparedRawSession, rawURL: URL, recipe: EditRecipe) async -> Bitmap? {
        // `exposure` lives in RawIntent, not LookIntent: it is baked onto CIRAWFilter,
        // not applied as a look post-op. Decoding at RawIntent.neutral and then calling
        // applyLook renders every arm WITHOUT its exposure — which silently removes the
        // incumbent's strongest control and half of the photographer's intent.
        guard let staged = await session.rawStageImage(
            intent: recipe.rawIntent, targetLongEdge: Self.decodeLongEdge, tier: .authoritative
        ) else { return nil }
        let oriented = OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
        let looked = DevelopRenderGraph.applyLook(recipe.lookIntent, to: oriented)
        return rasterize(DevelopRenderGraph.normalizeOrigin(looked))
    }

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 4 * 60 * 60
    }

    func testPresetVersusIncumbentInPixels() async throws {
        let env = ProcessInfo.processInfo.environment
        let labelsURL = URL(fileURLWithPath: env["LUMINA_ARMS_LABELS"]
            ?? NSString(string: "~/LuminaEvidence/export-labels-01/labels.jsonl").expandingTildeInPath)
        let presetURL = URL(fileURLWithPath: env["LUMINA_ARMS_PRESET"]
            ?? NSString(string: "~/LuminaEvidence/a02-regression/preset.json").expandingTildeInPath)
        let outDir = URL(fileURLWithPath: env["LUMINA_ARMS_OUT"]
            ?? NSString(string: "~/LuminaEvidence/a02-regression").expandingTildeInPath, isDirectory: true)

        guard let text = try? String(contentsOf: labelsURL, encoding: .utf8),
              let pdata = try? Data(contentsOf: presetURL),
              let presetValues = (try? JSONSerialization.jsonObject(with: pdata)) as? [String: Double]
        else { throw XCTSkip("labels.jsonl and preset.json required") }

        let labels: [[String: Any]] = text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
        let presetRecipe = tone(presetValues)

        func uncropped(_ l: [String: Any]) -> Bool {
            let g = ["cropTop": 0.0, "cropLeft": 0.0, "cropBottom": 1.0, "cropRight": 1.0, "cropAngle": 0.0]
            return g.allSatisfy { abs((l[$0.key] as? Double ?? $0.value) - $0.value) < 1e-6 }
        }

        var rows: [[String: Any]] = []
        var skipped = 0
        for label in labels where uncropped(label) {
            guard let rawPath = label["raw"] as? String,
                  let jpegPath = label["jpeg"] as? String,
                  FileManager.default.fileExists(atPath: rawPath),
                  FileManager.default.fileExists(atPath: jpegPath),
                  let ref = reference(at: jpegPath)
            else { skipped += 1; continue }

            let url = URL(fileURLWithPath: rawPath)
            let session = PreparedRawSession(assetID: UUID(), rawURL: url)
            guard let stats = await session.imageStats() else { skipped += 1; continue }

            var handValues: [String: Double] = [:]
            for k in ["exposure", "contrast", "highlights", "shadows", "vibrance", "saturation"] {
                handValues[k] = label[k] as? Double ?? 0
            }
            let arms: [(String, EditRecipe)] = [
                ("neutral", .neutral),
                ("a00", AutoDevelop.recipe(for: ModelTestSupport.makeAsset(stats: stats), stats: stats)),
                ("preset", presetRecipe),
                ("hand", tone(handValues)),
            ]

            var row: [String: Any] = [
                "raw": rawPath, "jpeg": jpegPath,
                "dateTimeOriginal": label["dateTimeOriginal"] as? String ?? "",
            ]
            var complete = true
            for (name, recipe) in arms {
                guard let bmp = await render(session, rawURL: url, recipe: recipe),
                      let (de, dl) = Self.meanDeltaEAndL(bmp, ref) else { complete = false; break }
                row[name + "_deltaE"] = de
                row[name + "_deltaL"] = dl
            }
            if complete { rows.append(row) } else { skipped += 1 }
        }

        XCTAssertGreaterThan(rows.count, 0, "no frame rendered")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var blob = ""
        for r in rows {
            blob += String(decoding: try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]),
                           as: UTF8.self) + "\n"
        }
        try blob.write(to: outDir.appendingPathComponent("pixel-arms.jsonl"),
                       atomically: true, encoding: .utf8)
        print("A02-ARMS rows=\(rows.count) skipped=\(skipped)")
    }
}
