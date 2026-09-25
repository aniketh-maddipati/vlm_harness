import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Lumina

/// W0 — does one `EditRecipe.temperature` mean the same thing on both render tiers?
///
/// `EditRecipe.temperature` is stored as a single Kelvin number. The authoritative
/// tier bakes it onto `CIRAWFilter.neutralTemperature`, i.e. absolute Kelvin in the
/// RAW domain. The interactive tier once pinned the decode at camera as-shot and then
/// applied `CITemperatureAndTint` as a post-op with `inputNeutral = (6500, 0)` — a
/// move *from an assumed 6500 K source*. Relative in one tier, absolute in the other,
/// with the error growing as the true capture illuminant departs from 6500 K.
///
/// Three arms per frame, all rendered at one decode size so only white-balance
/// semantics can move the pixels:
///
///   authoritative  `tier: .authoritative`                    — the reference
///   interactive    `tier: .interactive`                      — what ships today
///   legacy         pinned as-shot decode + the 6500 post-op  — the defect, reconstructed
///
/// `legacy` is not dead-code exercise for its own sake: without it the parity assertion
/// cannot distinguish "the tiers agree because the bug is fixed" from "the tiers agree
/// because this test never had the resolution to see it". It is the positive control.
///
/// Fixture-gated like the other RAW tests — with no card it skips loudly rather than
/// passing vacuously. `LUMINA_TIER_PARITY_RAW_DIR` overrides the default card path;
/// `LUMINA_TIER_PARITY_OUT` overrides where the evidence JSON lands.
@MainActor
final class DevelopTierWhiteBalanceParityTests: XCTestCase {

    // MARK: - Configuration

    /// Both tiers decode to this long edge. Equal for every arm: a size difference
    /// would show up as resampling error and be indistinguishable from a WB gap.
    private static let decodeLongEdge = 640
    /// Comparison raster. Matches `DevelopEvalHarnessTests.compareLongEdge`.
    private static let compareSize = (384, 256)

    /// Tolerance. The repo already holds preview/export agreement to mean ΔE ≤ 1.5
    /// (`testSonyPreviewExportContract`), so the tier gap is held to the same bar
    /// rather than a new one invented here. Mean ΔE ≈ 1 is the conventional
    /// just-noticeable difference for a trained observer on a flat patch; 1.5
    /// averaged over a whole frame is tighter than it sounds, because a real WB
    /// error biases every pixel in the same direction instead of cancelling.
    private static let toleranceDeltaE = 1.5

    /// One frame per capture illuminant, chosen from the 500-frame card by as-shot
    /// neutral temperature. `expectedK` is asserted before the frame is used, so a
    /// re-shot or re-ordered card fails loudly instead of quietly narrowing the span.
    private struct Frame {
        let name: String
        let band: String
        let expectedK: Double
    }

    private static let frames: [Frame] = [
        Frame(name: "LUM00004.ARW", band: "tungsten", expectedK: 3216),
        Frame(name: "LUM00104.ARW", band: "warm", expectedK: 3988),
        Frame(name: "LUM00130.ARW", band: "daylight", expectedK: 5002),
        Frame(name: "LUM00420.ARW", band: "neutral", expectedK: 6001),
        Frame(name: "LUM00387.ARW", band: "cloudy", expectedK: 7000),
        Frame(name: "LUM00112.ARW", band: "shade", expectedK: 8634),
    ]

    /// Explicit photographer-set white balances. Every one is an *override* — none is
    /// within the as-shot sentinel window — so all three arms must do real work.
    /// Spread either side of 6500 K because the legacy error changes sign there.
    private static let recipes: [(label: String, temperature: Double, tint: Double)] = [
        ("k3200", 3200, 0),
        ("k5200", 5200, 0),
        ("k7800", 7800, 0),
        ("k5200tint12", 5200, 12),
    ]

    // MARK: - Infrastructure

    private let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private struct Bitmap {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private static let linearLUT: [Double] = (0..<256).map { value in
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB → CIE Lab (D65). Mirrors `DevelopEvalHarnessTests.lab`; that one is
    /// `private` to its class, and a cross-file `@testable` reach-in would couple
    /// this test to that file's internals.
    private static func lab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (Double, Double, Double) {
        let rl = linearLUT[Int(r)], gl = linearLUT[Int(g)], bl = linearLUT[Int(b)]
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Mean ΔE*ab over every pixel.
    private static func meanDeltaE(_ a: Bitmap, _ b: Bitmap) -> Double? {
        guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return nil }
        var total = 0.0
        var n = 0.0
        for i in stride(from: 0, to: a.rgba.count, by: 4) {
            let la = lab(a.rgba[i], a.rgba[i + 1], a.rgba[i + 2])
            let lb = lab(b.rgba[i], b.rgba[i + 1], b.rgba[i + 2])
            total += ((la.0 - lb.0) * (la.0 - lb.0)
                + (la.1 - lb.1) * (la.1 - lb.1)
                + (la.2 - lb.2) * (la.2 - lb.2)).squareRoot()
            n += 1
        }
        guard n > 0 else { return nil }
        return total / n
    }

    private func draw(_ cg: CGImage, width: Int, height: Int) -> Bitmap? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(width: width, height: height, rgba: rgba)
    }

    private func rasterize(_ image: CIImage) -> Bitmap? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1,
              let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { return nil }
        return draw(cg, width: Self.compareSize.0, height: Self.compareSize.1)
    }

    private func recipe(temperature: Double, tint: Double) -> EditRecipe {
        EditRecipe(exposure: 0, temperature: temperature, tint: tint)
    }

    // MARK: - Arms

    /// Reference: RAW-domain absolute Kelvin.
    private func authoritativeArm(
        _ session: PreparedRawSession, rawURL: URL, recipe: EditRecipe
    ) async -> Bitmap? {
        guard let staged = await session.rawStageImage(
            intent: recipe.rawIntent, targetLongEdge: Self.decodeLongEdge, tier: .authoritative
        ) else { return nil }
        let oriented = OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
        return rasterize(DevelopRenderGraph.normalizeOrigin(oriented))
    }

    /// What ships today on the interactive tier.
    private func interactiveArm(
        _ session: PreparedRawSession, rawURL: URL, recipe: EditRecipe
    ) async -> Bitmap? {
        guard let staged = await session.rawStageImage(
            intent: recipe.rawIntent, targetLongEdge: Self.decodeLongEdge, tier: .interactive
        ) else { return nil }
        let oriented = OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
        return rasterize(DevelopRenderGraph.normalizeOrigin(oriented))
    }

    /// The defect, reconstructed: pin the decode at camera as-shot, then move white
    /// balance with `CITemperatureAndTint` as though the source were 6500 K.
    private func legacyPostOpArm(
        _ session: PreparedRawSession, rawURL: URL, recipe: EditRecipe
    ) async -> Bitmap? {
        guard let staged = await session.rawStageImage(
            intent: recipe.rawIntent.pinnedInteractiveDecode,
            targetLongEdge: Self.decodeLongEdge,
            tier: .interactive
        ) else { return nil }
        let oriented = OrientedDisplayImage.aligning(staged.image, toFile: rawURL)
        let posted = DevelopRenderGraph.applyExposureAndWhiteBalance(recipe.rawIntent, to: oriented)
        return rasterize(DevelopRenderGraph.normalizeOrigin(posted))
    }

    // MARK: - The run

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60 * 60
    }

    func testExplicitKelvinAgreesAcrossTiersOverCaptureIlluminants() async throws {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(
            fileURLWithPath: env["LUMINA_TIER_PARITY_RAW_DIR"]
                ?? NSString(string: "~/Pictures/lumina-fixtures/card-clean-500").expandingTildeInPath,
            isDirectory: true
        )
        let present = Self.frames.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.name).path) }
        guard present.count == Self.frames.count else {
            throw XCTSkip("tier parity fixture card required at \(dir.path) — found \(present.count)/\(Self.frames.count) frames")
        }

        var rows: [[String: Any]] = []
        var worstInteractive = 0.0
        var worstLegacy = 0.0
        var worstInteractiveCase = ""
        var worstLegacyCase = ""
        var illuminantsSeen = Set<String>()

        for frame in Self.frames {
            let url = dir.appendingPathComponent(frame.name)

            // Assert the fixture still is the illuminant this test claims it is.
            let asShot = try XCTUnwrap(CIRAWFilter(imageURL: url), "no RAW filter for \(frame.name)")
            let asShotK = Double(asShot.neutralTemperature)
            let asShotTint = Double(asShot.neutralTint)
            XCTAssertEqual(
                asShotK, frame.expectedK, accuracy: 25,
                "\(frame.name) as-shot Kelvin moved — the illuminant span this test claims is no longer true"
            )
            illuminantsSeen.insert(frame.band)

            let session = PreparedRawSession(assetID: UUID(), rawURL: url)

            for spec in Self.recipes {
                let recipe = self.recipe(temperature: spec.temperature, tint: spec.tint)
                XCTAssertFalse(
                    recipe.rawIntent.isAsShotWhiteBalance,
                    "\(spec.label) fell inside the as-shot sentinel window — it would not exercise any WB path"
                )

                let referenceValue = await authoritativeArm(session, rawURL: url, recipe: recipe)
                let shippingValue = await interactiveArm(session, rawURL: url, recipe: recipe)
                let legacyValue = await legacyPostOpArm(session, rawURL: url, recipe: recipe)
                let reference = try XCTUnwrap(referenceValue)
                let shipping = try XCTUnwrap(shippingValue)
                let legacy = try XCTUnwrap(legacyValue)

                let interactiveGap = try XCTUnwrap(Self.meanDeltaE(shipping, reference))
                let legacyGap = try XCTUnwrap(Self.meanDeltaE(legacy, reference))

                if interactiveGap > worstInteractive {
                    worstInteractive = interactiveGap
                    worstInteractiveCase = "\(frame.name)/\(spec.label)"
                }
                if legacyGap > worstLegacy {
                    worstLegacy = legacyGap
                    worstLegacyCase = "\(frame.name)/\(spec.label)"
                }

                rows.append([
                    "frame": frame.name,
                    "band": frame.band,
                    "asShotK": asShotK,
                    "asShotTint": asShotTint,
                    "recipe": spec.label,
                    "targetK": spec.temperature,
                    "targetTint": spec.tint,
                    // The legacy post-op assumed the source was 6500 K. This is by how
                    // much that assumption was wrong for this frame, in Kelvin.
                    "assumedSourceErrorK": asShotK - EditRecipe.neutralTemperature,
                    "interactiveVsAuthoritativeDeltaE": interactiveGap,
                    "legacyVsAuthoritativeDeltaE": legacyGap,
                ])

                XCTAssertLessThanOrEqual(
                    interactiveGap, Self.toleranceDeltaE,
                    "\(frame.name) (\(frame.band), as-shot \(Int(asShotK))K) @ \(spec.label): "
                        + "interactive vs authoritative mean ΔE \(interactiveGap)"
                )
            }
        }

        XCTAssertGreaterThanOrEqual(illuminantsSeen.count, 3, "fewer than 3 capture illuminants exercised")
        XCTAssertTrue(illuminantsSeen.contains("tungsten"), "no tungsten frame")
        XCTAssertTrue(illuminantsSeen.contains("shade"), "no shade frame")

        // Positive control. If the reconstructed defect does not itself exceed the
        // tolerance, this test cannot detect the class of bug it exists to detect,
        // and a pass above means nothing.
        XCTAssertGreaterThan(
            worstLegacy, Self.toleranceDeltaE,
            "positive control failed: the reconstructed 6500 K post-op stayed within tolerance, "
                + "so this test has no power to detect a tier gap"
        )

        let outDir = URL(
            fileURLWithPath: env["LUMINA_TIER_PARITY_OUT"]
                ?? NSString(string: "~/LuminaEvidence/tier-gap-01").expandingTildeInPath,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "toleranceDeltaE": Self.toleranceDeltaE,
            "decodeLongEdge": Self.decodeLongEdge,
            "worstInteractiveVsAuthoritativeDeltaE": worstInteractive,
            "worstInteractiveCase": worstInteractiveCase,
            "worstLegacyVsAuthoritativeDeltaE": worstLegacy,
            "worstLegacyCase": worstLegacyCase,
            "rows": rows,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outDir.appendingPathComponent("before-after-deltas.json"))
        }
        print("TIER-PARITY worst interactive ΔE \(worstInteractive) (\(worstInteractiveCase)); "
            + "worst legacy ΔE \(worstLegacy) (\(worstLegacyCase))")
    }
}
