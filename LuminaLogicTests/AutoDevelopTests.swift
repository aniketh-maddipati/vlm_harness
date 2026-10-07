import Foundation
import XCTest
@testable import Lumina

/// AutoDevelop behind `lumina.auto` (BRIDGE-v0.02 §1): the recipe's units and clamping (the Edit
/// page's slider units), the measurement on scene-linear pixels, and SetsAuto's argument guard and
/// per file + version cache. Foundation only: also runs in the Linux sandbox (Tests/linux-swift).
/// The acceptance gate (LOOPS.md: median |Δexposure| < 0.25 EV against the photographer's own
/// edited XMPs) needs real RAWs and runs on the Mac.
final class AutoDevelopTests: XCTestCase {
    /// Mid-tone frame, nothing clipping at either end, as-shot 5200 K / +3.
    private func even(mean: Double = AutoDevelop.meanAnchor, low: Double = 0, high: Double = 0,
                      kelvin: Double? = 5200, tint: Double? = 3) -> ImageStats {
        ImageStats(luminanceBins: Array(repeating: 32, count: ImageStats.binCount), shadowClipFraction: low, highlightClipFraction: high,
                   mean: mean, linearMean: 0.18, nativeTemperature: kelvin, nativeTint: tint)
    }

    private func onStep(_ ev: Double) -> Bool { abs(ev * 20 - (ev * 20).rounded()) < 1e-9 }

    // MARK: The recipe, in slider units

    func testSameStatsSameRecipe() {
        let s = even(mean: 0.31, low: 0.02, high: 0.011)
        XCTAssertEqual(AutoDevelop.recipe(for: s), AutoDevelop.recipe(for: s))
    }

    func testIdentityStatsAreNearIdentity() {
        let r = AutoDevelop.recipe(for: even())
        XCTAssertEqual(r.ev, 0)
        XCTAssertEqual(r.hl, 0)
        XCTAssertEqual(r.sh, 0)
        XCTAssertEqual(r.wh, 0)
        XCTAssertEqual(r.bl, 0)
        XCTAssertEqual(r.wb, 5200)
        XCTAssertEqual(r.tint, 3)
    }

    func testExposureIsInStopsOnTheSliderStepAndBounded() {
        XCTAssertEqual(AutoDevelop.exposure(mean: 1.0), -1.0)
        XCTAssertEqual(AutoDevelop.exposure(mean: 0.0), 0.35)
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] { XCTAssertEqual(AutoDevelop.exposure(mean: invalid), 0) }
        // Near-identical frames of a burst land on the same value; every value is on the 0.05 step,
        // with no binary noise (0.35, never 0.35000000000000003) and never −0.
        XCTAssertEqual(AutoDevelop.exposure(mean: 0.400), AutoDevelop.exposure(mean: 0.401))
        for m in stride(from: 0.0, through: 1.0, by: 0.013) {
            let ev = AutoDevelop.exposure(mean: m)
            XCTAssertTrue(onStep(ev), "\(ev) for mean \(m)")
            XCTAssertTrue((-1.0...0.35).contains(ev))
            XCTAssertEqual(ev, (ev * 100).rounded() / 100)
            XCTAssertFalse(ev == 0 && ev.sign == .minus, "−0 for mean \(m)")
        }
        XCTAssertEqual(AutoDevelop.quantized(9), 5)
        XCTAssertEqual(AutoDevelop.quantized(-9), -5)
        XCTAssertEqual(AutoDevelop.quantized(0.123), 0.1)
    }

    func testBrighteningNeedsHeadroom() {
        var s = even(mean: 0.15, high: 0.02)
        s.luminanceBins = Array(repeating: 0, count: ImageStats.binCount)
        s.luminanceBins[3] = 900
        s.luminanceBins[31] = 100
        XCTAssertEqual(AutoDevelop.recipe(for: s).ev, 0, "clipping highlights veto a lift")
        s.highlightClipFraction = 0
        s.luminanceBins[31] = 0
        s.luminanceBins[27] = 100
        XCTAssertEqual(AutoDevelop.recipe(for: s).ev, 0, "bright but not clipped still vetoes")
        s.luminanceBins[27] = 0
        s.luminanceBins[12] = 100
        XCTAssertEqual(AutoDevelop.recipe(for: s).ev, 0.35)
        for bins in [[], Array(repeating: 0, count: ImageStats.binCount), [-1]] {
            var t = even(mean: 0.1)
            t.luminanceBins = bins
            XCTAssertEqual(AutoDevelop.exposure(stats: t), 0, "no histogram, no lift")
        }
    }

    func testHighlightsAndShadowsAreWholeNumbersInsideTheirSliders() {
        XCTAssertEqual(AutoDevelop.highlights(clipFraction: 0.004), 0, "below significance: no move")
        XCTAssertEqual(AutoDevelop.highlights(clipFraction: 0.01), -30)
        XCTAssertEqual(AutoDevelop.highlights(clipFraction: 0.5), -80)
        XCTAssertEqual(AutoDevelop.shadows(clipFraction: 0.01), 10)
        XCTAssertEqual(AutoDevelop.shadows(clipFraction: 0.9), 20)
        for bad in [Double.nan, .infinity, -0.5, 1.5] {
            XCTAssertEqual(AutoDevelop.highlights(clipFraction: bad), 0)
            XCTAssertEqual(AutoDevelop.shadows(clipFraction: bad), 0)
        }
        for f in stride(from: 0.0, through: 1.0, by: 0.0007) {
            let hl = AutoDevelop.highlights(clipFraction: f), sh = AutoDevelop.shadows(clipFraction: f)
            XCTAssertTrue(AutoDevelop.toneRange.contains(hl) && hl == hl.rounded() && hl <= 0, "hl \(hl)")
            XCTAssertTrue(AutoDevelop.toneRange.contains(sh) && sh == sh.rounded() && sh >= 0, "sh \(sh)")
        }
    }

    func testWhiteBalanceIsTheAsShotPairOrNothing() {
        XCTAssertEqual(AutoDevelop.whiteBalance(kelvin: 5234, tint: 3.4)?.kelvin, 5230, "Kelvin on the slider's 10 K step")
        XCTAssertEqual(AutoDevelop.whiteBalance(kelvin: 5234, tint: 3.4)?.tint, 3)
        XCTAssertEqual(AutoDevelop.whiteBalance(kelvin: 5000, tint: 400)?.tint, 150, "tint inside −150 … +150")
        // Outside the slider, missing, or not finite: as shot (no wb, no tint), never a clamped colour.
        for (k, t) in [(2300.0, 0.0), (12000, 0), (.nan, 0), (5000, .nan), (.infinity, 0)] as [(Double, Double)] {
            XCTAssertNil(AutoDevelop.whiteBalance(kelvin: k, tint: t), "\(k) / \(t)")
        }
        XCTAssertNil(AutoDevelop.whiteBalance(kelvin: nil, tint: 0))
        XCTAssertNil(AutoDevelop.whiteBalance(kelvin: 5000, tint: nil))
        let tungsten = AutoDevelop.recipe(for: even(kelvin: 2300, tint: 0))
        XCTAssertNil(tungsten.wb)
        XCTAssertNil(tungsten.look["wb"])
        XCTAssertNil(tungsten.look["tint"])
    }

    func testLookHasThePagesKeysOnly() {
        let r = AutoDevelop.recipe(for: even(mean: 0.2, low: 0.02, high: 0.02))
        XCTAssertEqual(Set(r.look.keys), ["ev", "wb", "tint", "hl", "sh", "wh", "bl"])
        XCTAssertNil(r.look["vib"], "no Vibrance: the Edit page has no slider for it")
        XCTAssertTrue(r.look.values.allSatisfy(\.isFinite))
        XCTAssertFalse(AutoDevelop.version.isEmpty)
    }

    // MARK: Measuring scene-linear pixels

    private func rgba(_ values: [Float]) -> [Float] { values.flatMap { [$0, $0, $0, 1] } }

    func testMeasureEncodesLinearLuminanceForTheTunedThresholds() throws {
        // 18 % grey is about 0.46 encoded: the mean anchor, so no exposure move.
        let grey = try XCTUnwrap(ImageStats.measure(linearRGBA: rgba(Array(repeating: 0.18, count: 100))))
        XCTAssertEqual(grey.mean, ImageStats.encoded(0.18), accuracy: 1e-6)
        XCTAssertEqual(grey.linearMean, 0.18, accuracy: 1e-6)
        XCTAssertEqual(grey.sampleCount, 100)
        XCTAssertEqual(AutoDevelop.exposure(stats: grey), 0)
        // Above 1 (extended linear) is white and clipped; 0 and below are black and clipped.
        let ends = try XCTUnwrap(ImageStats.measure(linearRGBA: rgba([4, 1, 0, -0.5, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18])))
        XCTAssertEqual(ends.highlightClipFraction, 0.2, accuracy: 1e-9)
        XCTAssertEqual(ends.shadowClipFraction, 0.2, accuracy: 1e-9)
        XCTAssertEqual(ends.luminanceBins[ImageStats.binCount - 1], 2)
        XCTAssertEqual(ends.luminanceBins[0], 2)
    }

    func testMeasureSkipsNonFinitePixelsAndRefusesNothing() {
        XCTAssertNil(ImageStats.measure(linearRGBA: []))
        XCTAssertNil(ImageStats.measure(linearRGBA: [.nan, 0, 0, 1, .infinity, 1, 1, 1]))
        let s = ImageStats.measure(linearRGBA: [.nan, 0, 0, 1] + rgba([0.18]))
        XCTAssertEqual(s?.sampleCount, 1)
        // A bad luma vector falls back to Rec.709 instead of producing nonsense.
        XCTAssertEqual(ImageStats.measure(linearRGBA: rgba([0.18]), luma: [.nan, 1])?.mean ?? -1, ImageStats.encoded(0.18), accuracy: 1e-6)
    }

    func testMeasureCarriesTheAsShotPair() {
        let s = ImageStats.measure(linearRGBA: rgba([0.05, 0.05]), nativeTemperature: 6100, nativeTint: -7)
        XCTAssertEqual(s?.nativeTemperature, 6100)
        XCTAssertEqual(s?.nativeTint, -7)
        XCTAssertEqual(s.flatMap { AutoDevelop.recipe(for: $0).wb }, 6100)
    }

    // MARK: SetsAuto: the op's argument and the cache

    func testRelGuard() {
        XCTAssertEqual(SetsAuto.rel("shoot/DSC00001.ARW", maxBytes: 4096), "shoot/DSC00001.ARW")
        let bads: [Any?] = [nil, NSNull(), 42, 1e308, Double.nan, true, "", ["shoot/DSC00001.ARW"], ["rel": "x"], "a\u{0}b", String(repeating: "A", count: 4097)]
        for bad in bads {
            XCTAssertNil(SetsAuto.rel(bad, maxBytes: 4096), "\(String(describing: bad).prefix(40))")
        }
    }

    func testAnswerShapeAndCachePerFileAndVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("auto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("DSC00001.ARW"), b = dir.appendingPathComponent("DSC00002.ARW"), bad = dir.appendingPathComponent("DSC00003.ARW")
        for u in [a, b, bad] { try Data(repeating: 1, count: 64).write(to: u) }
        let stats = even(mean: 0.2, low: 0.02, high: 0.0)
        let auto = SetsAuto(measure: { url in
            if url.lastPathComponent == "DSC00003.ARW" { throw CocoaError(.fileReadCorruptFile) }
            return stats
        })
        let first = try XCTUnwrap(auto.answer(url: a))
        XCTAssertEqual(first["version"] as? String, AutoDevelop.version)
        let look = try XCTUnwrap(first["look"] as? [String: Double])
        XCTAssertEqual(look, AutoDevelop.recipe(for: stats).look)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(first), "the bridge hands it to WebKit as is")
        XCTAssertEqual(auto.measured, 1)
        _ = auto.answer(url: a)
        XCTAssertEqual(auto.measured, 1, "the same file and version: a cache hit")
        _ = auto.answer(url: b)
        XCTAssertEqual(auto.measured, 2, "another file: measured")
        XCTAssertNil(auto.answer(url: bad))
        XCTAssertNil(auto.answer(url: bad))
        XCTAssertEqual(auto.measured, 3, "a file that can't be measured is remembered too")
        XCTAssertNil(auto.answer(url: dir.appendingPathComponent("NOPE.ARW")))
        XCTAssertNil(auto.answer(url: dir))
        XCTAssertEqual(auto.measured, 3, "a missing file or a folder is never measured")
        // The file changes on disk: measured again.
        try Data(repeating: 2, count: 128).write(to: a)
        _ = auto.answer(url: a)
        XCTAssertEqual(auto.measured, 4)
        XCTAssertTrue(SetsAuto.key(a).hasSuffix("|" + AutoDevelop.version), "the version is part of the key")
    }
}
