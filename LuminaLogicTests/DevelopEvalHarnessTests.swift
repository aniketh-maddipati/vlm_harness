import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import Lumina

/// Stream D — Lumina's auto arms measured against the photographer's own hand edits.
///
/// Every arm is rendered through Lumina's own graph (authoritative tier: exposure and
/// white balance baked onto `CIRAWFilter`, then `applyLook` and `applyGeometry`) and
/// compared in pixel space with the photographer's export of the same frame. The
/// oracle arm searches the rendered slider subset for the closest match, so its
/// residual is the floor no slider-only proposal can beat.
///
/// Fixture-gated like `AutoDevelopRawFixtureTests`: with no eval set it skips loudly,
/// never passes vacuously. It writes numbers only (`metrics.json`) — no preview,
/// thumbnail or embedding — and expects the output folder to live outside the repo,
/// because the numbers describe one photographer's taste.
///
/// Environment (each prefixed `TEST_RUNNER_` on the xcodebuild command line):
///   LUMINA_EVAL_RAW_DIR   folder of RAW files
///   LUMINA_EVAL_EDIT_DIR  folder of the exports named in truth.json
///   LUMINA_EVAL_TRUTH     truth.json from Scripts/harness/eval/lr_truth.py
///   LUMINA_EVAL_OUT       folder that receives metrics.json
///   LUMINA_EVAL_LIMIT     optional: only the first N frames (smoke runs)
///   LUMINA_LIVE_MODEL=1   optional: add the model arm (LM Studio on loopback, D67)
///   LUMINA_EVAL_CONTACT_DIR  optional: one JPEG per frame, panels left to right
///                            neutral · auto · model (when on) · oracle · the hand edit
@MainActor
final class DevelopEvalHarnessTests: XCTestCase {

    // MARK: - Configuration

    /// Decode size for every arm: small enough that the oracle search stays affordable,
    /// large enough that highlight and shadow behaviour still reads.
    private static let decodeLongEdge = 640
    /// Both images are resampled to this long edge before comparison.
    private static let compareLongEdge = 384
    /// Coordinate-descent passes; each pass halves every step.
    private static let oraclePasses = 4
    /// Preview size handed to the vision model, same as the product path.
    private static let modelPreviewLongEdge = ModelImage.longEdge

    private struct Config {
        let rawDir: URL
        let editDir: URL
        let truthURL: URL
        let outDir: URL
        let limit: Int?
        let liveModel: Bool
        /// Optional: write one side-by-side JPEG per frame (pixels — local, never committed).
        let contactDir: URL?

        static func fromEnvironment() -> Config? {
            let env = ProcessInfo.processInfo.environment
            guard let raw = env["LUMINA_EVAL_RAW_DIR"],
                  let edit = env["LUMINA_EVAL_EDIT_DIR"],
                  let truth = env["LUMINA_EVAL_TRUTH"],
                  let out = env["LUMINA_EVAL_OUT"] else { return nil }
            return Config(
                rawDir: URL(fileURLWithPath: raw, isDirectory: true),
                editDir: URL(fileURLWithPath: edit, isDirectory: true),
                truthURL: URL(fileURLWithPath: truth),
                outDir: URL(fileURLWithPath: out, isDirectory: true),
                limit: env["LUMINA_EVAL_LIMIT"].flatMap(Int.init),
                liveModel: env["LUMINA_LIVE_MODEL"] == "1",
                contactDir: env["LUMINA_EVAL_CONTACT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            )
        }
    }

    // MARK: - Truth (numbers written by lr_truth.py)

    private struct TruthFrame: Decodable {
        let raw: String
        let edit: String
        let virtualCopy: Bool
        let whiteBalance: String
        let untouched: Bool
        let unrenderedMagnitude: Double
        let hasMask: Bool
        let hasRetouch: Bool
        /// FiveK only: which retoucher's rendition this row compares against (a…e).
        let expert: String?
        let exposure, temperature, tint, contrast, highlights, shadows: Double
        let whites, blacks, texture, clarity, dehaze, vibrance, saturation: Double
        let sharpness, luminanceNR, vignette: Double
        let cropTop, cropLeft, cropBottom, cropRight, cropAngle: Double

        var crop: EditCrop? {
            let crop = EditCrop(
                x: cropLeft, y: cropTop, width: cropRight - cropLeft, height: cropBottom - cropTop
            )
            return crop.isFullFrame ? nil : crop.normalized()
        }

        var json: [String: Any] {
            [
                "exposure": exposure, "temperature": temperature, "tint": tint,
                "contrast": contrast, "highlights": highlights, "shadows": shadows,
                "whites": whites, "blacks": blacks, "texture": texture, "clarity": clarity,
                "dehaze": dehaze, "vibrance": vibrance, "saturation": saturation,
                "sharpness": sharpness, "luminanceNR": luminanceNR, "vignette": vignette,
                "whiteBalance": whiteBalance,
            ]
        }
    }

    private struct Truth: Decodable {
        let frames: [TruthFrame]
    }

    // MARK: - Pixels

    private struct Bitmap {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private struct PixelMetrics {
        var psnr = 0.0
        var deltaE = 0.0
        /// Signed mean L* difference, Lumina minus reference: positive = Lumina brighter.
        var deltaL = 0.0
        var centerPsnr = 0.0
        var centerDeltaE = 0.0
        var centerDeltaL = 0.0

        var json: [String: Any] {
            [
                "psnr": round4(psnr), "deltaE": round4(deltaE), "deltaL": round4(deltaL),
                "centerPsnr": round4(centerPsnr), "centerDeltaE": round4(centerDeltaE),
                "centerDeltaL": round4(centerDeltaL),
            ]
        }
    }

    private let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static let linearLUT: [Double] = (0..<256).map { value in
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func lab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (Double, Double, Double) {
        let rl = linearLUT[Int(r)], gl = linearLUT[Int(g)], bl = linearLUT[Int(b)]
        // sRGB → XYZ (D65), normalized to the D65 white point.
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func compare(_ a: Bitmap, _ b: Bitmap) -> PixelMetrics? {
        guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return nil }
        var sq = 0.0, de = 0.0, dl = 0.0
        var csq = 0.0, cde = 0.0, cdl = 0.0
        var n = 0.0, cn = 0.0
        let cx = a.width / 4 ..< a.width * 3 / 4
        let cy = a.height / 4 ..< a.height * 3 / 4
        for y in 0..<a.height {
            for x in 0..<a.width {
                let i = (y * a.width + x) * 4
                let dr = Double(a.rgba[i]) - Double(b.rgba[i])
                let dg = Double(a.rgba[i + 1]) - Double(b.rgba[i + 1])
                let db = Double(a.rgba[i + 2]) - Double(b.rgba[i + 2])
                let s = dr * dr + dg * dg + db * db
                let la = lab(a.rgba[i], a.rgba[i + 1], a.rgba[i + 2])
                let lb = lab(b.rgba[i], b.rgba[i + 1], b.rgba[i + 2])
                let e = ((la.0 - lb.0) * (la.0 - lb.0) + (la.1 - lb.1) * (la.1 - lb.1)
                    + (la.2 - lb.2) * (la.2 - lb.2)).squareRoot()
                sq += s; de += e; dl += la.0 - lb.0; n += 1
                if cx.contains(x), cy.contains(y) {
                    csq += s; cde += e; cdl += la.0 - lb.0; cn += 1
                }
            }
        }
        func psnr(_ sumSq: Double, _ count: Double) -> Double {
            let mse = sumSq / (count * 3)
            return mse <= 0 ? 99 : 10 * log10(255 * 255 / mse)
        }
        guard n > 0, cn > 0 else { return nil }
        return PixelMetrics(
            psnr: psnr(sq, n), deltaE: de / n, deltaL: dl / n,
            centerPsnr: psnr(csq, cn), centerDeltaE: cde / cn, centerDeltaL: cdl / cn
        )
    }

    private static func flippedVertically(_ bitmap: Bitmap) -> Bitmap {
        var rgba = [UInt8](repeating: 0, count: bitmap.rgba.count)
        let row = bitmap.width * 4
        for y in 0..<bitmap.height {
            let src = y * row, dst = (bitmap.height - 1 - y) * row
            rgba.replaceSubrange(dst..<(dst + row), with: bitmap.rgba[src..<(src + row)])
        }
        return Bitmap(width: bitmap.width, height: bitmap.height, rgba: rgba)
    }

    /// Resample a CGImage into an sRGB 8-bit buffer of exactly `width` × `height`.
    private func draw(_ cg: CGImage, width: Int, height: Int, space: CGColorSpace? = nil) -> Bitmap? {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space ?? srgb,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? Bitmap(width: width, height: height, rgba: buffer) : nil
    }

    private func loadReference(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.compareLongEdge * 2,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func compareSize(for cg: CGImage) -> (Int, Int) {
        let long = max(cg.width, cg.height)
        let scale = Double(compareLongEdge) / Double(long)
        return (
            max(1, Int((Double(cg.width) * scale).rounded())),
            max(1, Int((Double(cg.height) * scale).rounded()))
        )
    }

    // MARK: - Lumina's graph

    /// Authoritative RAW stage for one RAW-domain intent, oriented like the file.
    private func stage(_ session: PreparedRawSession, rawURL: URL, intent: RawIntent) async -> CIImage? {
        guard let staged = await session.rawStageImage(
            intent: intent, targetLongEdge: Self.decodeLongEdge, tier: .authoritative
        ) else { return nil }
        return OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
    }

    /// Evaluate a lazy stage once so the look stage can be re-applied cheaply.
    private func materialize(_ image: CIImage) -> CIImage? {
        let extent = image.extent.integral
        guard let cg = context.createCGImage(
            image, from: extent, format: .RGBAh, colorSpace: DevelopColorPolicy.workingColorSpace
        ) else { return nil }
        return CIImage(cgImage: cg)
    }

    private func finish(_ stage: CIImage, recipe: EditRecipe) -> CIImage {
        var image = DevelopRenderGraph.applyLook(recipe.lookIntent, to: stage)
        image = DevelopRenderGraph.applyGeometry(recipe, to: image)
        return DevelopRenderGraph.normalizeOrigin(image)
    }

    private func rasterize(_ image: CIImage, size: (Int, Int)) -> Bitmap? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1,
              let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { return nil }
        return draw(cg, width: size.0, height: size.1)
    }

    private func renderArm(
        _ session: PreparedRawSession, rawURL: URL, recipe: EditRecipe, size: (Int, Int)
    ) async -> Bitmap? {
        guard let stage = await stage(session, rawURL: rawURL, intent: recipe.rawIntent) else { return nil }
        return rasterize(finish(stage, recipe: recipe), size: size)
    }

    // MARK: - Oracle

    private struct OracleField {
        let name: String
        let keyPath: WritableKeyPath<EditRecipe, Double>
        let range: ClosedRange<Double>
        let step: Double
    }

    private struct OracleResult {
        var recipe: EditRecipe
        var deltaE: Double
        var evaluations: Int
        var decodes: Int
    }

    /// Coordinate descent over the rendered slider subset, minimizing mean ΔE against the
    /// reference. RAW-domain moves (exposure, temperature, tint) re-decode; look moves reuse
    /// the materialized stage. A local search from the mapped hand edit — it can stop in a
    /// local minimum, so treat the result as an upper bound on the true floor.
    private func oracle(
        _ session: PreparedRawSession, rawURL: URL, start: EditRecipe,
        nativeTemperature: Double, reference: Bitmap
    ) async -> OracleResult? {
        let size = (reference.width, reference.height)
        let fields: [OracleField] = [
            OracleField(name: "exposure", keyPath: \.exposure, range: -3...3, step: 0.5),
            OracleField(
                name: "temperature", keyPath: \.temperature,
                range: (nativeTemperature - 2500)...(nativeTemperature + 2500), step: 500
            ),
            OracleField(name: "tint", keyPath: \.tint, range: -150...150, step: 30),
            OracleField(name: "contrast", keyPath: \.contrast, range: -100...100, step: 25),
            OracleField(name: "highlights", keyPath: \.highlights, range: -100...100, step: 25),
            OracleField(name: "shadows", keyPath: \.shadows, range: -100...100, step: 25),
            OracleField(name: "vibrance", keyPath: \.vibrance, range: -100...100, step: 25),
            OracleField(name: "saturation", keyPath: \.saturation, range: -100...100, step: 25),
        ]

        var stages: [String: CIImage] = [:]
        var evaluations = 0
        var decodes = 0

        func score(_ recipe: EditRecipe) async -> Double? {
            let key = recipe.rawIntent.fingerprint
            if stages[key] == nil {
                guard let lazy = await stage(session, rawURL: rawURL, intent: recipe.rawIntent),
                      let solid = materialize(lazy) else { return nil }
                decodes += 1
                if stages.count >= 6 { stages.removeAll() }
                stages[key] = solid
            }
            guard let solid = stages[key],
                  let bitmap = rasterize(finish(solid, recipe: recipe), size: size),
                  let metrics = Self.compare(bitmap, reference) else { return nil }
            evaluations += 1
            return metrics.deltaE
        }

        var best = start
        guard var bestScore = await score(best) else { return nil }
        var steps = fields.map(\.step)

        for _ in 0..<Self.oraclePasses {
            for (index, field) in fields.enumerated() {
                var improved = true
                while improved {
                    improved = false
                    for direction in [1.0, -1.0] {
                        let value = best[keyPath: field.keyPath] + direction * steps[index]
                        guard field.range.contains(value) else { continue }
                        var candidate = best
                        candidate[keyPath: field.keyPath] = value
                        candidate = Self.avoidingAsShotSentinel(candidate)
                        guard let candidateScore = await score(candidate) else { continue }
                        if candidateScore < bestScore - 1e-4 {
                            best = candidate
                            bestScore = candidateScore
                            improved = true
                            break
                        }
                    }
                }
                steps[index] /= 2
            }
        }
        return OracleResult(recipe: best, deltaE: bestScore, evaluations: evaluations, decodes: decodes)
    }

    /// `RawIntent.isAsShotWhiteBalance` treats 6500 K ± 1 as "as shot"; a searched Kelvin
    /// value landing there would silently mean something else.
    private static func avoidingAsShotSentinel(_ recipe: EditRecipe) -> EditRecipe {
        guard abs(recipe.temperature - EditRecipe.neutralTemperature) <= 1 else { return recipe }
        return recipe.updating { $0.temperature = EditRecipe.neutralTemperature + 2 }
    }

    // MARK: - Subject-weighted measurement (eval-only spike of Stream B)

    private struct SubjectStats {
        let stats: ImageStats
        let method: String
        /// Share of total weight that sits on the subject (faces or salient region).
        let subjectMass: Double
        /// Unweighted mean from the same pixels, to show the weighting effect alone.
        let globalMean: Double
    }

    private func subjectStats(
        _ session: PreparedRawSession, rawURL: URL, base: ImageStats
    ) async -> SubjectStats? {
        guard let staged = await session.rawStageImage(
            intent: .neutral, targetLongEdge: ImageStatsRenderer.sampleLongEdge, tier: .interactive
        ) else { return nil }
        let image = OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
        let extent = image.extent.integral
        guard let cg = context.createCGImage(
            image, from: extent, format: .RGBA8, colorSpace: DevelopColorPolicy.displayColorSpace
        ), let bitmap = draw(cg, width: cg.width, height: cg.height, space: DevelopColorPolicy.displayColorSpace)
        else { return nil }

        let width = bitmap.width, height = bitmap.height
        var weights = [Double](repeating: 1, count: width * height)
        var method = "global"
        var subjectMass = 1.0
        let floorWeight = 0.15

        let faces = (try? Self.faceBoxes(in: cg)) ?? []
        if !faces.isEmpty {
            method = "faces"
            weights = [Double](repeating: floorWeight, count: width * height)
            for box in faces {
                // Vision boxes are normalized, origin bottom-left; grow them to take in
                // hair and neck, which is what a portrait exposure is judged on.
                let grow = 0.6
                let w = box.width * (1 + grow), h = box.height * (1 + grow)
                let cx = box.midX, cy = 1 - box.midY
                let x0 = max(0, Int((cx - w / 2) * Double(width)))
                let x1 = min(width, Int((cx + w / 2) * Double(width)))
                let y0 = max(0, Int((cy - h / 2) * Double(height)))
                let y1 = min(height, Int((cy + h / 2) * Double(height)))
                guard x1 > x0, y1 > y0 else { continue }
                for y in y0..<y1 { for x in x0..<x1 { weights[y * width + x] = 1 } }
            }
        } else if let saliency = Self.saliencyMap(in: cg) {
            method = "saliency"
            for y in 0..<height {
                let sy = min(saliency.height - 1, y * saliency.height / height)
                for x in 0..<width {
                    let sx = min(saliency.width - 1, x * saliency.width / width)
                    let s = Double(saliency.values[sy * saliency.width + sx])
                    weights[y * width + x] = floorWeight + (1 - floorWeight) * min(max(s, 0), 1)
                }
            }
        }

        var bins = [Double](repeating: 0, count: ImageStats.binCount)
        var weightSum = 0.0, lumSum = 0.0, low = 0.0, high = 0.0, subject = 0.0, plainSum = 0.0
        for index in 0..<(width * height) {
            let i = index * 4
            let r = Double(bitmap.rgba[i]) / 255, g = Double(bitmap.rgba[i + 1]) / 255, b = Double(bitmap.rgba[i + 2]) / 255
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let w = weights[index]
            let bin = min(ImageStats.binCount - 1, max(0, Int(lum * Double(ImageStats.binCount))))
            bins[bin] += w
            weightSum += w
            lumSum += lum * w
            plainSum += lum
            if lum < ImageStats.shadowClipThreshold { low += w }
            if lum > ImageStats.highlightClipThreshold { high += w }
            subject += w - floorWeight
        }
        guard weightSum > 0 else { return nil }
        // Share of the weight that the subject adds above the floor every pixel gets.
        if method != "global" { subjectMass = max(0, subject) / weightSum }
        let stats = ImageStats(
            luminanceBins: bins.map { Int(($0 * 1000).rounded()) },
            shadowClipFraction: low / weightSum,
            highlightClipFraction: high / weightSum,
            mean: lumSum / weightSum,
            nativeTemperature: base.nativeTemperature,
            horizonAngle: base.horizonAngle
        )
        return SubjectStats(
            stats: stats, method: method, subjectMass: subjectMass,
            globalMean: plainSum / Double(width * height)
        )
    }

    private static func faceBoxes(in cg: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }

    private struct SaliencyMap {
        let width: Int
        let height: Int
        let values: [Float]
    }

    private static func saliencyMap(in cg: CGImage) -> SaliencyMap? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])) != nil,
              let observation = request.results?.first else { return nil }
        let buffer = observation.pixelBuffer
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.size
        let pointer = base.assumingMemoryBound(to: Float.self)
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { values[y * width + x] = pointer[y * stride + x] } }
        return SaliencyMap(width: width, height: height, values: values)
    }

    // MARK: - Model arm (gated)

    private func writePreviewJPEG(_ image: CIImage, to url: URL) -> Bool {
        let extent = image.extent.integral
        let long = max(extent.width, extent.height)
        let scale = min(1, CGFloat(Self.modelPreviewLongEdge) / max(long, 1))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent.integral, format: .RGBA8, colorSpace: srgb),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: - Contact sheet (opt-in, pixels for the photographer's own eyes)

    private func writeContactSheet(_ panels: [Bitmap], to url: URL) {
        guard !panels.isEmpty else { return }
        let gap = 8
        let width = panels.reduce(0) { $0 + $1.width } + gap * (panels.count - 1)
        let height = panels.map(\.height).max() ?? 0
        guard width > 0, height > 0 else { return }
        var buffer = [UInt8](repeating: 255, count: width * height * 4)
        var x0 = 0
        for panel in panels {
            for y in 0..<panel.height {
                let src = y * panel.width * 4
                let dst = (y * width + x0) * 4
                buffer.replaceSubrange(dst..<(dst + panel.width * 4), with: panel.rgba[src..<(src + panel.width * 4)])
            }
            x0 += panel.width + gap
        }
        let image: CGImage? = buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Journal

    private static func readJournal(_ url: URL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    private static func appendJournal(_ row: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
        } else {
            try? (data + Data("\n".utf8)).write(to: url, options: .atomic)
        }
    }

    // MARK: - Recipes

    private static func recipeJSON(_ recipe: EditRecipe) -> [String: Any] {
        [
            "exposure": round4(recipe.exposure), "temperature": round4(recipe.temperature),
            "tint": round4(recipe.tint), "contrast": round4(recipe.contrast),
            "highlights": round4(recipe.highlights), "shadows": round4(recipe.shadows),
            "vibrance": round4(recipe.vibrance), "saturation": round4(recipe.saturation),
            "whites": round4(recipe.whites), "blacks": round4(recipe.blacks),
        ]
    }

    /// The hand edit mapped 1:1 onto the fields Lumina renders. "As Shot" becomes the
    /// engine's as-shot sentinel; a custom white balance is carried as absolute Kelvin
    /// and Lightroom's tint units, so any scale mismatch shows up as oracle movement.
    private static func mappedRecipe(_ truth: TruthFrame, base: EditRecipe) -> EditRecipe {
        base.updating { recipe in
            recipe.exposure = truth.exposure
            if truth.whiteBalance == "As Shot" {
                recipe.temperature = EditRecipe.neutralTemperature
                recipe.tint = 0
            } else {
                recipe.temperature = truth.temperature
                recipe.tint = truth.tint
            }
            recipe.contrast = truth.contrast
            recipe.highlights = truth.highlights
            recipe.shadows = truth.shadows
            recipe.vibrance = truth.vibrance
            recipe.saturation = truth.saturation
            // Recorded for the residual attribution; the engine does not render them.
            recipe.whites = truth.whites
            recipe.blacks = truth.blacks
            recipe.texture = truth.texture
            recipe.clarity = truth.clarity
            recipe.dehaze = truth.dehaze
        }
    }

    private static func round4(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 10_000).rounded() / 10_000
    }

    // MARK: - The run

    /// The Fast plan caps a test at three minutes; a full set takes about fifteen. The
    /// plan is not loosened — the run passes `-test-timeouts-enabled NO` on the command
    /// line, and this asks for the room in case a plan with a higher cap is used.
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 4 * 60 * 60
    }

    func testAutoArmsAgainstHandEdits() async throws {
        guard let config = Config.fromEnvironment() else {
            throw XCTSkip(
                "No eval set. Set LUMINA_EVAL_RAW_DIR, LUMINA_EVAL_EDIT_DIR, LUMINA_EVAL_TRUTH and LUMINA_EVAL_OUT."
            )
        }
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: config.truthURL))
        var frames = truth.frames
        if let limit = config.limit { frames = Array(frames.prefix(limit)) }
        XCTAssertFalse(frames.isEmpty, "truth.json names no frames")

        try FileManager.default.createDirectory(at: config.outDir, withIntermediateDirectories: true)
        let previewDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-eval-\(UUID().uuidString)", isDirectory: true)
        if config.liveModel {
            try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: previewDir) }
        if let contactDir = config.contactDir {
            try FileManager.default.createDirectory(at: contactDir, withIntermediateDirectories: true)
        }

        let modelClient = ChatCompletionsClient(endpoint: .localVision)
        var modelFallbacks = 0
        var lastFallback: String?
        let runStart = CFAbsoluteTimeGetCurrent()

        // Resumable: every finished frame is appended to frames.jsonl as it completes, and
        // a relaunch skips frames already there. The test host can be quit from outside
        // (a sibling session's `pkill Lumina` ends it with code 0 mid-run); fourteen
        // minutes of decodes should not be lost to that.
        let journalURL = config.outDir.appendingPathComponent("frames.jsonl")
        var results = Self.readJournal(journalURL)
        let done = Set(results.compactMap { row -> String? in
            guard let raw = row["raw"] as? String, let edit = row["edit"] as? String else { return nil }
            return raw + "|" + edit
        })
        if !done.isEmpty { print("[eval] resuming: \(done.count) frames already in \(journalURL.lastPathComponent)") }

        for (index, frame) in frames.enumerated() {
            if done.contains(frame.raw + "|" + frame.edit) { continue }
            let frameStart = CFAbsoluteTimeGetCurrent()
            let rawURL = config.rawDir.appendingPathComponent(frame.raw)
            let editURL = config.editDir.appendingPathComponent(frame.edit)
            var row: [String: Any] = [
                "raw": frame.raw, "edit": frame.edit, "virtualCopy": frame.virtualCopy,
                "untouched": frame.untouched, "whiteBalance": frame.whiteBalance,
                "unrenderedMagnitude": frame.unrenderedMagnitude,
                "hasMask": frame.hasMask, "hasRetouch": frame.hasRetouch,
                "hasCrop": frame.crop != nil, "lr": frame.json,
                "expert": frame.expert as Any,
            ]

            guard let referenceImage = loadReference(editURL) else {
                XCTFail("\(frame.edit): reference export could not be read")
                continue
            }
            let size = Self.compareSize(for: referenceImage)
            guard let reference = draw(referenceImage, width: size.0, height: size.1) else {
                XCTFail("\(frame.edit): reference could not be resampled")
                continue
            }

            let assetID = UUID()
            let session = PreparedRawSession(assetID: assetID, rawURL: rawURL)
            let (capabilities, metadata) = await session.capabilityReport()
            guard let metadata else {
                XCTFail("\(frame.raw): RAW could not be prepared")
                continue
            }
            row["capabilities"] = capabilities.summary
            row["native"] = [
                "temperature": Self.round4(metadata.nativeNeutralTemperature),
                "tint": Self.round4(metadata.nativeNeutralTint),
            ]

            // Geometry and the RAW-domain detail controls come from the hand edit for every
            // arm: they are not what an auto pass proposes, and the pixels must line up.
            let base = EditRecipe(
                sharpness: frame.sharpness, luminanceNR: frame.luminanceNR, crop: frame.crop
            )
            var arms: [String: [String: Any]] = [:]
            var armBitmaps: [String: Bitmap] = [:]

            func record(_ name: String, _ recipe: EditRecipe, extra: [String: Any] = [:]) async {
                var entry: [String: Any] = ["recipe": Self.recipeJSON(recipe)]
                for (key, value) in extra { entry[key] = value }
                if let bitmap = await renderArm(session, rawURL: rawURL, recipe: recipe, size: size) {
                    armBitmaps[name] = bitmap
                    if let metrics = Self.compare(bitmap, reference) {
                        entry["pixel"] = metrics.json
                    } else {
                        entry["error"] = "size mismatch \(bitmap.width)x\(bitmap.height) vs \(reference.width)x\(reference.height)"
                    }
                } else {
                    entry["error"] = "render failed"
                }
                arms[name] = entry
            }

            // Aspect sanity: a portrait frame that did not orient would compare garbage.
            if let stage = await stage(session, rawURL: rawURL, intent: .neutral) {
                let ext = stage.extent
                let cropped = frame.crop.map { $0.pixelRect(in: ext) } ?? ext
                let luminaAspect = cropped.width / max(cropped.height, 1)
                let referenceAspect = Double(reference.width) / Double(reference.height)
                let mismatch = abs(luminaAspect - referenceAspect) / referenceAspect
                row["aspectMismatch"] = Self.round4(mismatch)
                if mismatch > 0.05 {
                    XCTFail("\(frame.raw): aspect \(luminaAspect) vs reference \(referenceAspect)")
                }
            }

            await record("neutral", base)
            let mapped = Self.mappedRecipe(frame, base: base)
            await record("lrMapped", mapped)

            // Oracle starts from the mapped edit with white balance made explicit, so the
            // search can move Kelvin without crossing the as-shot sentinel.
            let oracleStart = mapped.updating {
                if $0.rawIntent.isAsShotWhiteBalance {
                    $0.temperature = metadata.nativeNeutralTemperature
                    $0.tint = metadata.nativeNeutralTint
                }
            }
            if let fit = await oracle(
                session, rawURL: rawURL, start: Self.avoidingAsShotSentinel(oracleStart),
                nativeTemperature: metadata.nativeNeutralTemperature, reference: reference
            ) {
                await record("oracle", fit.recipe, extra: [
                    "evaluations": fit.evaluations, "decodes": fit.decodes,
                ])
            } else {
                arms["oracle"] = ["error": "search failed"]
            }

            // Deterministic auto, measured the way the product measures.
            guard let stats = await session.imageStats() else {
                XCTFail("\(frame.raw): no image stats")
                continue
            }
            let asset = AssetRecord(
                id: assetID,
                sourceKey: "eval-\(assetID.uuidString)",
                source: SourceReference(
                    originalPath: rawURL.path, relativePath: rawURL.lastPathComponent,
                    volumeID: "LOCAL", availability: .available
                ),
                filename: frame.raw,
                recipe: base,
                imageStats: stats
            )
            let autoFull = AutoDevelop.recipe(for: asset, stats: stats)
            let auto = autoFull.updating { $0.straightenDegrees = 0 }
            row["stats"] = [
                "mean": Self.round4(stats.mean),
                "shadowClip": Self.round4(stats.shadowClipFraction),
                "highlightClip": Self.round4(stats.highlightClipFraction),
                "horizonAngle": stats.horizonAngle.map(Self.round4) as Any,
            ]
            row["autoStraighten"] = Self.round4(autoFull.straightenDegrees)
            await record("auto", auto)

            // White balance the auto pass writes, on its own: shows whether "native
            // temperature, tint 0" is really as-shot on the authoritative tier.
            await record("autoWB", base.updating {
                $0.temperature = auto.temperature
                $0.tint = auto.tint
            })

            // Subject-weighted metering feeding the same deterministic rules.
            if let subject = await subjectStats(session, rawURL: rawURL, base: stats) {
                let weighted = AutoDevelop.recipe(for: asset, stats: subject.stats)
                    .updating { $0.straightenDegrees = 0 }
                await record("autoSubject", weighted, extra: [
                    "method": subject.method,
                    "subjectMass": Self.round4(subject.subjectMass),
                    "weightedMean": Self.round4(subject.stats.mean),
                    "globalMean": Self.round4(subject.globalMean),
                ])
            }

            // Preview ≡ export: the same recipe on the interactive tier (pinned as-shot
            // decode plus Core Image post-ops) versus the authoritative render above.
            var tierGaps: [String: Any] = [:]
            for (name, recipe) in [("neutral", base), ("lrMapped", mapped), ("auto", auto)] {
                guard let authoritative = armBitmaps[name],
                      let pinned = await session.interactivePinnedSource(
                          intent: recipe.rawIntent, targetLongEdge: Self.decodeLongEdge
                      ) else { continue }
                let aligned = OrientedDisplayImage.aligning(pinned.image, toFile: rawURL)
                let variant = DevelopRenderGraph.branchInteractiveVariant(from: aligned, recipe: recipe)
                // The texture-backed interactive image rasterizes upside down relative to
                // the lazy authoritative graph (Metal top-left vs Core Image bottom-left);
                // the flipped comparison is the real gap. The unflipped number is kept so a
                // change in that convention shows up rather than hiding in the gap.
                if let interactive = rasterize(variant, size: size),
                   let gap = Self.compare(Self.flippedVertically(interactive), authoritative),
                   let unflipped = Self.compare(interactive, authoritative) {
                    var entry = gap.json
                    entry["unflippedDeltaE"] = Self.round4(unflipped.deltaE)
                    tierGaps[name] = entry
                }
            }
            row["tierGap"] = tierGaps

            // How far the auto pass's white balance alone moves the render from as-shot.
            if let wb = armBitmaps["autoWB"], let neutral = armBitmaps["neutral"],
               let drift = Self.compare(wb, neutral) {
                row["wbDrift"] = drift.json
            }

            if config.liveModel, let neutralStage = await stage(session, rawURL: rawURL, intent: .neutral) {
                let previewURL = previewDir.appendingPathComponent("\(assetID.uuidString).jpg")
                if writePreviewJPEG(finish(neutralStage, recipe: base), to: previewURL) {
                    let modelAsset = asset.withThumbPath(previewURL.path)
                    let result = await ModelAutoDevelop.proposal(for: modelAsset, stats: stats, client: modelClient)
                    if result.source != .model {
                        modelFallbacks += 1
                        lastFallback = result.fallbackReason
                    }
                    await record("model", result.recipe.updating { $0.straightenDegrees = 0 }, extra: [
                        "source": result.source.rawValue,
                        "fallback": result.fallbackReason as Any,
                    ])
                    try? FileManager.default.removeItem(at: previewURL)
                }
            }

            if let contactDir = config.contactDir {
                let order = ["neutral", "auto", "model", "oracle"]
                let panels = order.compactMap { armBitmaps[$0] } + [reference]
                let stem = (frame.edit as NSString).deletingPathExtension
                writeContactSheet(panels, to: contactDir.appendingPathComponent("\(stem)-neutral-auto\(config.liveModel ? "-model" : "")-oracle-edit.jpg"))
            }

            row["arms"] = arms
            row["seconds"] = Self.round4(CFAbsoluteTimeGetCurrent() - frameStart)
            results.append(row)
            Self.appendJournal(row, to: journalURL)

            func summary(_ name: String) -> String {
                guard let pixel = arms[name]?["pixel"] as? [String: Any],
                      let de = pixel["deltaE"] as? Double else { return "\(name) —" }
                return "\(name) ΔE \(String(format: "%.2f", de))"
            }
            print(
                "[eval] \(index + 1)/\(frames.count) \(frame.raw)"
                    + (frame.untouched ? " (untouched)" : "")
                    + " · \(summary("neutral")) · \(summary("lrMapped")) · \(summary("oracle"))"
                    + " · \(summary("auto")) · \(summary("autoSubject"))"
                    + (config.liveModel ? " · \(summary("model"))" : "")
                    + String(format: " · %.1fs", CFAbsoluteTimeGetCurrent() - frameStart)
            )
        }

        // Rows restored from the journal carry their own fallback field.
        modelFallbacks = results.filter {
            (($0["arms"] as? [String: Any])?["model"] as? [String: Any])?["source"] as? String == "auto"
        }.count
        if config.liveModel, modelFallbacks == results.count {
            XCTFail("model arm requested but every frame fell back: \(lastFallback ?? "unknown")")
        }

        let document: [String: Any] = [
            "schema": 1,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "evalSet": config.rawDir.lastPathComponent,
            "decodeLongEdge": Self.decodeLongEdge,
            "compareLongEdge": Self.compareLongEdge,
            "oraclePasses": Self.oraclePasses,
            "decoder": RawDecodeBackendRegistry.mappingVersion,
            "liveModel": config.liveModel,
            "modelFallbacks": modelFallbacks,
            "frames": results,
            "seconds": Self.round4(CFAbsoluteTimeGetCurrent() - runStart),
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        let outURL = config.outDir.appendingPathComponent("metrics.json")
        try data.write(to: outURL, options: .atomic)
        print("[eval] wrote \(outURL.path) (\(results.count) frames)")
        XCTAssertEqual(results.count, frames.count, "some frames produced no row")
    }
}

private extension AssetRecord {
    func withThumbPath(_ path: String) -> AssetRecord {
        var copy = self
        copy.thumbPath = path
        return copy
    }
}
