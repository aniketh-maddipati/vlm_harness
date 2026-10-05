import XCTest
@testable import Lumina

/// Where the tests find the shipped rules: `LUMINA_RULES` when set (the Linux sandbox runs in a
/// container that only mounts Tests/linux-swift), else `rules-v1.json` next to the Look sources,
/// found by walking up from this file.
enum LookTestRules {
    static func url() -> URL {
        if let p = ProcessInfo.processInfo.environment["LUMINA_RULES"], !p.isEmpty { return URL(fileURLWithPath: p) }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("Lumina/Sets/Look/rules-v1.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "Lumina/Sets/Look/rules-v1.json")
    }

    static func load() throws -> LookRules { try LookRules.load(from: url()) }
}

/// Every stage's transfer function, in scalar form, on a synthetic grey ramp: monotonic in
/// luminance, grey in → grey out for every slider except white balance, identity at reset, and the
/// sign each slider must have. The same properties are checked through the real graph in
/// `LookPipelineTests`; here they also run on Linux (Tests/linux-swift).
final class LookMathTests: XCTestCase {
    var rules: LookRules!
    let asShot = Look.WhiteBalance(kelvin: 5500, tint: 0)
    /// Linear grey values, 0 to a little over white (the working space is extended).
    let ramp: [Double] = (0...60).map { Double($0) / 50 }

    override func setUpWithError() throws { rules = try LookTestRules.load() }

    private func luma(_ c: LookMath.RGB) -> Double { LookMath.luma(c, rules) }

    private func run(_ look: Look, _ v: Double) -> LookMath.RGB {
        LookMath.flat(.gray(v), look: look, asShot: asShot, rules: rules)
    }

    /// The twelve sliders at a spread of positions, as `Look.single` names them.
    private var sweep: [(String, Double)] {
        var out: [(String, Double)] = []
        for s in ["Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Vibrance", "Saturation", "Clarity"] {
            for v in [-100.0, -50, -10, 10, 50, 100] { out.append((s, v)) }
        }
        for v in [-5.0, -2, -0.5, 0.5, 2, 5] { out.append(("Exposure", v)) }
        for v in [2000.0, 3200, 4500, 6500, 9000, 50000] { out.append(("Temperature", v)) }
        for v in [-150.0, -40, 40, 150] { out.append(("Tint", v)) }
        for v in [10.0, 50, 150] { out.append(("Sharpness", v)) }
        return out
    }

    func testRulesFileLoadsAndIsCanonical() throws {
        XCTAssertEqual(rules.order, LookRules.canonicalOrder)
        XCTAssertEqual(rules.lookStages.count, 9)
        for s in rules.lookStages { XCTAssertNotNil(rules.stages[s], s) }
        XCTAssertNoThrow(try rules.validate())
        var bad = rules!; bad.order = ["exposure", "rawDevelop", "outputTransform"]
        XCTAssertThrowsError(try bad.validate())
        XCTAssertEqual(try LookRules.load(json: try rules.encoded()), rules, "rules survive a re-encode (the loop rewrites the file)")
    }

    func testResetIsIdentity() {
        for v in ramp {
            let out = run(Look(), v)
            XCTAssertEqual(out.r, v, accuracy: 1e-12); XCTAssertEqual(out.g, v, accuracy: 1e-12); XCTAssertEqual(out.b, v, accuracy: 1e-12)
        }
    }

    func testEverySliderIsMonotonicOnAGreyRamp() {
        for (slider, value) in sweep {
            let look = Look.single(slider, value, asShot: asShot)!
            var last = -1.0
            for v in ramp {
                let y = luma(run(look, v))
                XCTAssertGreaterThanOrEqual(y, last - 1e-9, "\(slider) \(value) at grey \(v): \(y) < \(last)")
                XCTAssertTrue(y.isFinite && y >= 0, "\(slider) \(value) at grey \(v): \(y)")
                last = y
            }
        }
    }

    func testGreyStaysGreyUnderEverySliderExceptWhiteBalance() {
        for (slider, value) in sweep where slider != "Temperature" && slider != "Tint" {
            let look = Look.single(slider, value, asShot: asShot)!
            for v in ramp {
                let out = run(look, v)
                XCTAssertTrue(out.isNeutral, "\(slider) \(value) at grey \(v): \(out)")
            }
        }
        for v in [0.05, 0.18, 0.5, 0.9] {
            XCTAssertFalse(run(Look.single("Temperature", 8000, asShot: asShot)!, v).isNeutral)
            XCTAssertFalse(run(Look.single("Tint", 60, asShot: asShot)!, v).isNeutral)
        }
    }

    /// Highlights and Shadows read each pixel against the photo (its anchor), as Lightroom does: a
    /// 0.4 pixel is a highlight in a night scene and a midtone in a bright one, and each slider's
    /// strength follows the photo's tonal spread and its share of bright pixels.
    func testToneIsRelativeToThePhoto() {
        typealias A = LookMath.ToneAnchor
        func out(_ slider: String, _ v: Double, _ px: Double, _ anchor: A) -> Double {
            luma(LookMath.flat(.gray(px), look: Look.single(slider, v, asShot: asShot)!, asShot: asShot, rules: rules, anchor: anchor))
        }
        let night = out("Highlights", -100, 0.4, A(mean: 0.005)), bright = out("Highlights", -100, 0.4, A(mean: 0.4))
        XCTAssertLessThan(night, bright, "pulled harder where 0.4 is the brightest thing in the frame")
        XCTAssertLessThan(bright, 0.4)
        // Shadows are read against the photo too: against its mean, or against its bright end (the rules say which).
        let byMean = rules.k("tone", "shadowsAdapt", 0), byHigh = rules.k("tone", "shadowsHighAdapt", 0)
        XCTAssertGreaterThan(byMean + byHigh, 0, "Shadows must be read against the photo one way or the other")
        if byMean > 0 { XCTAssertGreaterThan(out("Shadows", 100, 0.1, A(mean: 0.4)), out("Shadows", 100, 0.1, A(mean: 0.02)), "0.1 is a shadow in a bright photo") }
        if byHigh > 0 { XCTAssertGreaterThan(out("Shadows", 100, 0.1, A(mean: 0.18, high: 1.0)), out("Shadows", 100, 0.1, A(mean: 0.18, high: 0.3)), "0.1 is a shadow where the bright end is far above it") }
        // The reference anchor is what a flat patch gets by default.
        XCTAssertEqual(out("Shadows", 50, 0.1, .reference), luma(run(Look.single("Shadows", 50, asShot: asShot)!, 0.1)), accuracy: 1e-12)
        // Strength follows the photo: Shadows lifts more where much of the frame is bright, Highlights
        // pulls more in a wider photo; a missing statistic sits at the rules' centre (factor 1).
        let centre = LookMath.toneNormalisers(anchor: .reference, rules)
        XCTAssertEqual(centre.shadowsGain, 1, accuracy: 0.02)
        let c = { (n: String, d: Double) in self.rules.k("tone", n, d) }
        let atCentre = LookMath.toneNormalisers(anchor: A(mean: exp2(c("meanCentre", log2(0.18))), spread: c("spreadCentre", 1.5), bright: c("brightCentre", 0.2)), rules)
        XCTAssertEqual(atCentre.shadowsGain, 1, accuracy: 1e-9); XCTAssertEqual(atCentre.highlightsGain, 1, accuracy: 1e-9)
        if c("shadowsBright", 0) > 0 {
            XCTAssertGreaterThan(LookMath.toneNormalisers(anchor: A(mean: 0.18, spread: nil, bright: 0.6), rules).shadowsGain, 1)
            XCTAssertGreaterThan(out("Shadows", 100, 0.02, A(mean: 0.18, spread: nil, bright: 0.6)), out("Shadows", 100, 0.02, A(mean: 0.18, spread: nil, bright: 0.02)))
        }
        if c("highlightsSpread", 0) > 0 { XCTAssertGreaterThan(LookMath.toneNormalisers(anchor: A(mean: 0.18, spread: 3, bright: nil), rules).highlightsGain, 1) }
        // The Shadows mask sits against the photo's bright end (Lightroom, 156 photos: where its
        // Shadows curve sits follows the 95th percentile of luma, not the average): the same pixel
        // in the same average photo is a deeper shadow when the bright end is higher. A missing
        // bright end changes nothing.
        XCTAssertEqual(LookMath.toneNormalisers(anchor: A(mean: 0.18), rules).shadows, LookMath.toneNormalisers(anchor: A(mean: 0.18, high: exp2(c("highCentre", 0))), rules).shadows, accuracy: 1e-9)
        if c("shadowsHighAdapt", 0) > 0 {
            XCTAssertGreaterThan(out("Shadows", 100, 0.1, A(mean: 0.18, high: 1.0)), out("Shadows", 100, 0.1, A(mean: 0.18, high: 0.3)), "0.1 is a deeper shadow under a brighter bright end")
        }
        // However extreme the photo, a strength stays within [0.25, 4].
        let wild = LookMath.toneNormalisers(anchor: A(mean: 0.001, spread: 9, bright: 1), rules)
        XCTAssertLessThanOrEqual(wild.shadowsGain, 4); XCTAssertLessThanOrEqual(wild.highlightsGain, 4); XCTAssertGreaterThanOrEqual(wild.highlightsGain, 0.25)
        // Monotonic on a ramp for extreme anchors too.
        for a in [A(mean: 0.003, spread: 3, bright: 0.0, high: 0.02), A(mean: 0.6, spread: 0.5, bright: 0.9, high: 1.0), A(mean: 0.1, high: 0.001), .reference] {
            for (slider, v) in [("Highlights", -100.0), ("Highlights", 100), ("Shadows", 100), ("Shadows", -100)] {
                var last = -1.0
                for i in 0...240 { let y = out(slider, v, Double(i) / 200, a); XCTAssertGreaterThanOrEqual(y, last - 1e-9, "\(slider) \(v) anchor \(a) at \(i)"); last = y }
            }
        }
        // The anchor itself, from pixels: log-mean, spread in stops, share above L* 80.
        let flat = LookMath.toneAnchor(pixels: [0.18, 0.18, 0.18, 1, 0.18, 0.18, 0.18, 1], luma: rules.luma)
        XCTAssertEqual(flat.mean, 0.18, accuracy: 1e-6); XCTAssertEqual(flat.spread ?? -1, 0, accuracy: 1e-6); XCTAssertEqual(flat.bright ?? -1, 0, accuracy: 1e-12)
        let two = LookMath.toneAnchor(pixels: [0.1, 0.1, 0.1, 1, 0.8, 0.8, 0.8, 1], luma: rules.luma)
        XCTAssertEqual(two.mean, (0.1 * 0.8).squareRoot(), accuracy: 1e-6); XCTAssertEqual(two.spread ?? -1, 1.5, accuracy: 1e-6); XCTAssertEqual(two.bright ?? -1, 0.5, accuracy: 1e-12)
        // the bright end: the 95th percentile of luma, interpolated between the sorted values
        XCTAssertEqual(flat.high ?? -1, 0.18, accuracy: 1e-6); XCTAssertEqual(two.high ?? -1, 0.1 + 0.7 * 0.95, accuracy: 1e-6)
        let ramp = LookMath.toneAnchor(pixels: (0...100).flatMap { i -> [Float] in let v = Float(i) / 100; return [v, v, v, 1] }, luma: rules.luma)
        XCTAssertEqual(ramp.high ?? -1, 0.95, accuracy: 1e-6)
        XCTAssertEqual(LookMath.toneAnchor(pixels: [0, 0, 0, 1], luma: rules.luma).mean, 1e-3, accuracy: 1e-12)
        XCTAssertEqual(LookMath.toneAnchor(pixels: [], luma: rules.luma), .reference)
    }

    /// rawDevelop's base match: nothing at all with zero coefficients; otherwise a grey stays the
    /// same grey the curve gives it (rows of the mix sum to 1), the curve is the identity at 0 and
    /// from 1 up, and it never folds back.
    func testBaseMatchKeepsGreysNeutralAndIsMonotonic() {
        let c = LookMath.RGB(r: 0.6, g: 0.35, b: 0.25)
        XCTAssertTrue(LookMath.BaseMatch().isIdentity)
        XCTAssertEqual(LookMath.baseMatch(c, LookMath.BaseMatch(), rules), c)
        for m in [{ var m = LookMath.BaseMatch(); m.lift = 0.033; m.s = 0.30; m.rg = 0.135; m.rb = -0.003; m.gb = 0.135; m.br = 0.0025; m.bg = 0.012; return m }(),
                  LookMath.BaseMatch(rules)] {
            for row in m.rows { XCTAssertEqual(row.reduce(0, +), 1, accuracy: 1e-12) }
            XCTAssertEqual(LookMath.baseCurve(0, m, rules), 0, accuracy: 1e-12)
            for y in [1.0, 1.3, 4.0] { XCTAssertEqual(LookMath.baseCurve(y, m, rules), y, accuracy: 1e-9, "identity in the headroom") }
            var last = -1.0
            for i in 0...240 {
                let v = Double(i) / 200
                let out = LookMath.baseMatch(.gray(v), m, rules)
                XCTAssertTrue(out.isNeutral, "grey \(v) → \(out)")
                XCTAssertEqual(out.g, LookMath.baseCurve(v, m, rules), accuracy: 1e-9)
                XCTAssertGreaterThan(out.g, last, "monotonic at \(v)")
                last = out.g
            }
            guard !m.isIdentity else { continue }
            XCTAssertNotEqual(LookMath.baseMatch(c, m, rules), c)
        }
        // The fade toward luma near white and in the deepest shadows: the colour shrinks, the luma
        // does not move, the midtones keep all of their colour.
        var fade = LookMath.BaseMatch(); fade.hiDesat = 0.6; fade.hiFrom = 0.9; fade.loDesat = 0.5; fade.loBelow = 0.2
        XCTAssertFalse(fade.isIdentity)
        XCTAssertEqual(fade.chromaKept(0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(fade.chromaKept(1.0), 0.4, accuracy: 1e-12); XCTAssertEqual(fade.chromaKept(0.0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(fade.chromaKept(0.95), 1 - 0.6 * 0.25, accuracy: 1e-12)
        for colour in [LookMath.RGB(r: 0.95, g: 0.85, b: 0.8), LookMath.RGB(r: 0.004, g: 0.002, b: 0.006), LookMath.RGB(r: 0.3, g: 0.2, b: 0.1)] {
            let out = LookMath.baseMatch(colour, fade, rules)
            XCTAssertEqual(luma(out), luma(colour), accuracy: 1e-12, "luma kept")
            let spreadIn = max(colour.r, colour.g, colour.b) - min(colour.r, colour.g, colour.b), spreadOut = max(out.r, out.g, out.b) - min(out.r, out.g, out.b)
            XCTAssertLessThanOrEqual(spreadOut, spreadIn + 1e-12)
        }
        let mid = LookMath.baseMatch(LookMath.RGB(r: 0.3, g: 0.2, b: 0.1), fade, rules)
        XCTAssertEqual(mid.r, 0.3, accuracy: 1e-12, "midtones untouched"); XCTAssertEqual(mid.g, 0.2, accuracy: 1e-12); XCTAssertEqual(mid.b, 0.1, accuracy: 1e-12)
        XCTAssertTrue(LookMath.baseMatch(.gray(0.97), fade, rules).isNeutral)
    }

    /// Exposure is a scene gain seen through a sigmoid tone curve (the form Lightroom's sweep
    /// shows): deep shadows move by the full gain, highlights roll off toward `white`, the stage
    /// composes (+1 then −1 is nothing) and stays monotonic above `white` and below 0.
    func testExposureIsASceneGainThroughTheToneCurve() {
        let w = LookMath.exposureWhite(rules)
        let up = LookMath.exposureGain(1, rules), down = LookMath.exposureGain(-1, rules)
        XCTAssertEqual(up, exp2(rules.k("exposure", "stopsPerUnit", 1)), accuracy: 1e-12)
        XCTAssertEqual(up * down, 1, accuracy: 1e-12)
        // Deep shadows: the full gain. Highlights: less, never past white from below it.
        XCTAssertEqual(LookMath.exposure(1e-5, gain: up, white: w) / 1e-5, up, accuracy: 1e-3)
        let mid = LookMath.exposure(0.18, gain: up, white: w), high = LookMath.exposure(0.8, gain: up, white: w)
        XCTAssertGreaterThan(mid / 0.18, high / 0.8, "highlights move less than midtones")
        XCTAssertLessThan(high, w)
        XCTAssertEqual(LookMath.exposure(w, gain: up, white: w), w, accuracy: 1e-12)
        // It composes, so +1 then −1 gives the pixel back, in range and in the headroom.
        for x in [-0.02, 0.0, 0.01, 0.18, 0.6, 0.99, w, 1.4, 3.0] {
            XCTAssertEqual(LookMath.exposure(LookMath.exposure(x, gain: up, white: w), gain: down, white: w), x, accuracy: 1e-9, "\(x)")
            XCTAssertEqual(LookMath.exposure(x, gain: 1, white: w), x, accuracy: 1e-12, "identity at 0 EV")
        }
        // Monotonic through 0 and white for brightening and darkening.
        for g in [down * down, down, up, up * up] {
            var last = -Double.infinity
            for i in -20...400 { let y = LookMath.exposure(Double(i) / 100, gain: g, white: w); XCTAssertGreaterThan(y, last, "gain \(g) at \(i)"); last = y }
        }
        // Through the chain: brighter, grey stays grey.
        let c = run(Look.single("Exposure", 1, asShot: asShot)!, 0.18)
        XCTAssertGreaterThan(luma(c), 0.18); XCTAssertTrue(c.isNeutral)
        XCTAssertLessThan(luma(run(Look.single("Exposure", -2, asShot: asShot)!, 0.4)), 0.4)
    }

    func testWhiteBalanceSigns() {
        // Higher Kelvin = warmer render (more red than blue); positive tint = magenta (less green).
        let warm = run(Look.single("Temperature", 8000, asShot: asShot)!, 0.5)
        let cool = run(Look.single("Temperature", 3500, asShot: asShot)!, 0.5)
        XCTAssertGreaterThan(warm.r / warm.b, 1); XCTAssertLessThan(cool.r / cool.b, 1)
        let magenta = run(Look.single("Tint", 50, asShot: asShot)!, 0.5), green = run(Look.single("Tint", -50, asShot: asShot)!, 0.5)
        XCTAssertLessThan(magenta.g, magenta.r); XCTAssertGreaterThan(green.g, green.r)
        // As shot is identity.
        let same = run(Look.single("Temperature", asShot.kelvin, asShot: asShot)!, 0.5)
        XCTAssertEqual(same.r, 0.5, accuracy: 1e-9); XCTAssertEqual(same.b, 0.5, accuracy: 1e-9)
        // Temperature holds green where it is (Lightroom's sweep: green moves ~0.05 stops while
        // red and blue move ~1.3), unless the rules ask for the luma to be kept instead.
        if rules.k("whiteBalance", "preserveLuma", 1) < 0.5 {
            XCTAssertEqual(warm.g, 0.5, accuracy: 1e-9); XCTAssertEqual(cool.g, 0.5, accuracy: 1e-9)
        } else {
            XCTAssertEqual(luma(warm), 0.5, accuracy: 1e-9)
        }
        // The gains go through the tone curve: a cast is strongest in the shadows and fades toward
        // white (the sweep: ±1.3 stops at dark greys, ±0.3–0.6 near white).
        func redShift(_ v: Double) -> Double { let c = run(Look.single("Temperature", 8000, asShot: asShot)!, v); return log2(c.r / v) }
        XCTAssertGreaterThan(redShift(0.02), redShift(0.5)); XCTAssertGreaterThan(redShift(0.5), redShift(0.95))
        XCTAssertGreaterThan(redShift(0.95), 0)
        let w = LookMath.whiteBalanceWhite(rules)
        let white = run(Look.single("Temperature", 8000, asShot: asShot)!, w)
        XCTAssertEqual(white.r, w, accuracy: 1e-9, "white stays white"); XCTAssertEqual(white.b, w, accuracy: 1e-9)
    }

    func testToneShapedSlidersPushTheRightWay() {
        let dark = 0.02, light = 0.7
        // Contrast +: darks darker, lights lighter; −: the reverse. The midpoint holds.
        let m = LookMath.linear(rules.k("contrast", "midpoint", 0.46), rules)
        XCTAssertLessThan(luma(run(Look.single("Contrast", 60, asShot: asShot)!, dark)), dark)
        XCTAssertGreaterThan(luma(run(Look.single("Contrast", 60, asShot: asShot)!, light)), light)
        XCTAssertGreaterThan(luma(run(Look.single("Contrast", -60, asShot: asShot)!, dark)), dark)
        XCTAssertEqual(luma(run(Look.single("Contrast", 80, asShot: asShot)!, m)), m, accuracy: 1e-6)
        // Shadows + lifts the darks more than the lights; highlights − lowers the lights far more than
        // the darks (Lightroom's own −100 moves a dark grey by half a stop: it does reach them).
        let sh = Look.single("Shadows", 80, asShot: asShot)!
        XCTAssertGreaterThan(luma(run(sh, dark)) / dark, luma(run(sh, light)) / light)
        XCTAssertGreaterThan(luma(run(sh, dark)), dark)
        let hl = Look.single("Highlights", -80, asShot: asShot)!
        XCTAssertLessThan(luma(run(hl, light)), light)
        XCTAssertLessThan(luma(run(hl, light)) / light, luma(run(hl, dark)) / dark)
        XCTAssertLessThanOrEqual(luma(run(hl, dark)), dark)
        // Whites + raises the lights, blacks − lowers the darks; each leaves the other end alone.
        XCTAssertGreaterThan(luma(run(Look.single("Whites", 80, asShot: asShot)!, light)), light)
        XCTAssertEqual(luma(run(Look.single("Whites", 80, asShot: asShot)!, 0)), 0, accuracy: 1e-9)
        XCTAssertLessThan(luma(run(Look.single("Blacks", -80, asShot: asShot)!, dark)), dark)
        XCTAssertEqual(luma(run(Look.single("Blacks", -80, asShot: asShot)!, 1)), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(luma(run(Look.single("Blacks", 80, asShot: asShot)!, dark)), dark)
    }

    func testColourStage() {
        let red = LookMath.RGB(r: 0.5, g: 0.2, b: 0.2), skin = LookMath.RGB(r: 0.6, g: 0.35, b: 0.25)
        func chroma(_ c: LookMath.RGB) -> Double { let l = LookMath.toOklab(c); return hypot(l.a, l.b) }
        let desat = LookMath.flat(red, look: Look.single("Saturation", -100, asShot: asShot)!, asShot: asShot, rules: rules)
        XCTAssertTrue(desat.isNeutral, "saturation −100 is grey: \(desat)")
        let more = LookMath.flat(red, look: Look.single("Saturation", 30, asShot: asShot)!, asShot: asShot, rules: rules)
        XCTAssertGreaterThan(chroma(more), chroma(red))
        // Vibrance protects skin and already-saturated colours: red gains less than skin, relative to saturation.
        let vibRed = LookMath.flat(red, look: Look.single("Vibrance", 80, asShot: asShot)!, asShot: asShot, rules: rules)
        let vibSkin = LookMath.flat(skin, look: Look.single("Vibrance", 80, asShot: asShot)!, asShot: asShot, rules: rules)
        let satSkin = LookMath.flat(skin, look: Look.single("Saturation", 80, asShot: asShot)!, asShot: asShot, rules: rules)
        XCTAssertGreaterThan(chroma(vibRed), chroma(red) * 0.99)
        XCTAssertLessThan(chroma(vibSkin) / chroma(skin), chroma(satSkin) / chroma(skin), "vibrance is gentler on skin than saturation")
        // Vivid colours: without a floor Vibrance leaves a colour at vibranceChromaMax alone; with one it still
        // moves, by that share of the full strength. Below 0 the strength is vibranceDownPerUnit, skin or not.
        var r = rules!
        r.stages["colour"]?.coefficients.merge(["vibrancePerUnit": 0.008, "vibranceDownPerUnit": 0.012, "vibranceChromaMax": 0.3, "vibranceFloor": 0, "skinProtect": 0.8, "skinHue": 30, "skinWidth": 40]) { $1 }
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.3, hueDegrees: 200, vibrance: 50, saturation: 0, bw: false, r), 1, accuracy: 1e-12)
        r.stages["colour"]?.coefficients["vibranceFloor"] = 0.25
        let farFromSkin: Double = 1 - 0.8 * exp(-pow(170.0 / 40.0, 2))
        let vivid: Double = 1 + 50 * 0.008 * 0.25 * farFromSkin
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.3, hueDegrees: 200, vibrance: 50, saturation: 0, bw: false, r), vivid, accuracy: 1e-12)
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.5, hueDegrees: 200, vibrance: 50, saturation: 0, bw: false, r), LookMath.chromaFactor(chroma: 0.3, hueDegrees: 200, vibrance: 50, saturation: 0, bw: false, r), accuracy: 1e-12)
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.0, hueDegrees: 30, vibrance: -50, saturation: 0, bw: false, r), 1 - 50 * 0.012, accuracy: 1e-12)
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.15, hueDegrees: 30, vibrance: -50, saturation: 0, bw: false, r), LookMath.chromaFactor(chroma: 0.15, hueDegrees: 200, vibrance: -50, saturation: 0, bw: false, r), accuracy: 1e-12)
        // More colour in never comes out as less: C · factor rises with C at every strength the slider reaches.
        for v in [-100.0, -50, 50, 100] {
            var last = -1.0
            for i in 0...60 {
                let c = Double(i) * 0.01, out = c * LookMath.chromaFactor(chroma: c, hueDegrees: 200, vibrance: v, saturation: 0, bw: false, r)
                XCTAssertGreaterThanOrEqual(out, last - 1e-12, "vibrance \(v) at chroma \(c)"); last = out
            }
        }
        r.stages["colour"]?.coefficients["vibranceDownPerUnit"] = nil
        XCTAssertEqual(LookMath.chromaFactor(chroma: 0.0, hueDegrees: 30, vibrance: -50, saturation: 0, bw: false, r), 1 - 50 * 0.008, accuracy: 1e-12, "without its own number, down is as strong as up")
        // Lightness survives a chroma change (Oklab L is untouched).
        XCTAssertEqual(LookMath.toOklab(more).L, LookMath.toOklab(red).L, accuracy: 1e-6)
        // Round trip of the Oklab matrices.
        let back = LookMath.fromOklab(LookMath.toOklab(skin).L, LookMath.toOklab(skin).a, LookMath.toOklab(skin).b)
        XCTAssertEqual(back.r, skin.r, accuracy: 1e-6); XCTAssertEqual(back.g, skin.g, accuracy: 1e-6); XCTAssertEqual(back.b, skin.b, accuracy: 1e-6)
        var bw = Look(); bw.bw = true
        XCTAssertTrue(LookMath.flat(skin, look: bw, asShot: asShot, rules: rules).isNeutral)
    }

    func testVignetteGain() {
        var dark = Look(); dark.vignette = -100
        XCTAssertEqual(LookMath.vignetteGain(r: 0, vignette: -100, rules), 1, accuracy: 1e-12)
        XCTAssertLessThan(LookMath.vignetteGain(r: 1, vignette: -100, rules), 1)
        XCTAssertGreaterThan(LookMath.vignetteGain(r: 1, vignette: 60, rules), 1)
        XCTAssertLessThan(LookMath.vignetteGain(r: 1, vignette: -100, rules), LookMath.vignetteGain(r: 0.6, vignette: -100, rules))
        let corner = LookMath.flat(.gray(0.5), look: dark, asShot: asShot, rules: rules, vignetteR: 1)
        XCTAssertTrue(corner.isNeutral); XCTAssertLessThan(corner.r, 0.5)
    }

    func testLocalStagesAreIdentityOnAFlatPatch() {
        // Clarity and sharpen act on (pixel − base); on a flat patch that is zero.
        for q in [0.0, 0.2, 0.5, 0.9] {
            XCTAssertEqual(LookMath.clarity(q, base: q, clarity: 100, rules), q, accuracy: 1e-12)
            XCTAssertEqual(LookMath.sharpen(q, blur: q, amount: 150, rules), q, accuracy: 1e-12)
        }
        // And they push the right way on an edge: a pixel above its base goes up.
        XCTAssertGreaterThan(LookMath.clarity(0.55, base: 0.45, clarity: 60, rules), 0.55)
        XCTAssertLessThan(LookMath.clarity(0.55, base: 0.45, clarity: -60, rules), 0.55)
        XCTAssertGreaterThan(LookMath.sharpen(0.55, blur: 0.50, amount: 100, rules), 0.55)
        XCTAssertEqual(LookMath.sharpen(0.5001, blur: 0.5, amount: 100, rules), 0.5001, accuracy: 1e-9, "below the threshold nothing sharpens")
    }

    // MARK: outputTransform (the display mapper)

    private var sigmoidRules: LookRules {
        var r = rules!
        r.stages["outputTransform", default: LookRules.Stage()].mapper = "sigmoid"
        return r
    }

    /// Oklab hue (degrees) and chroma.
    private func hue(_ c: LookMath.RGB) -> (h: Double, C: Double) {
        let lab = LookMath.toOklab(c)
        return (atan2(lab.b, lab.a) * 180 / .pi, hypot(lab.a, lab.b))
    }

    private func hueShift(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    func testTheShippedMapperIsTheClamp() throws {
        XCTAssertEqual(rules.mapper, .clamp, "the sigmoid mapper is a prototype: the owner rules before it ships")
        let out = LookMath.output(LookMath.RGB(r: 1.5, g: 0.5, b: -0.1), rules)
        XCTAssertEqual(out, LookMath.RGB(r: 1, g: 0.5, b: 0))
        let s = sigmoidRules
        XCTAssertEqual(s.mapper, .sigmoid)
        XCTAssertEqual(try LookRules.load(json: try s.encoded()).mapper, .sigmoid, "the mapper survives a re-encode")
        var none = rules!
        none.stages["outputTransform"]?.mapper = nil
        XCTAssertEqual(try LookRules.load(json: try none.encoded()).mapper, .clamp, "a rules file without the key is the clamp")
        var bad = rules!
        bad.stages["outputTransform"]?.mapper = "filmic"
        XCTAssertThrowsError(try bad.validate())
    }

    func testMapperMatricesAreInversesAndKeepGrey() {
        for (inset, rotate) in [(0.2, 0.0), (0.2, 7.0), (0.35, -4.0), (0.0, 0.0)] {
            var m = LookMath.DisplayMapper(); m.inset = inset; m.rotate = rotate
            let a = m.insetRows, b = m.outsetRows
            for i in 0..<3 {
                XCTAssertEqual(a[i].reduce(0, +), 1, accuracy: 1e-12); XCTAssertEqual(b[i].reduce(0, +), 1, accuracy: 1e-12)
                for j in 0..<3 {
                    let v = (0..<3).reduce(0.0) { $0 + b[i][$1] * a[$1][j] }
                    XCTAssertEqual(v, i == j ? 1 : 0, accuracy: 1e-12, "inset \(inset) rotate \(rotate)")
                }
            }
        }
    }

    func testMapperIsTheIdentityBelowTheKnee() {
        let r = sigmoidRules
        for c in [LookMath.RGB.gray(0), .gray(0.02), .gray(0.18), .gray(0.6), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0.5, g: 0.2, b: 0.2),
                  LookMath.RGB(r: 0.15, g: 0.2, b: 0.6), LookMath.RGB(r: 0.004, g: 0.002, b: 0.006)] {
            let out = LookMath.output(c, r)
            XCTAssertEqual(out.r, c.r, accuracy: 1e-12); XCTAssertEqual(out.g, c.g, accuracy: 1e-12); XCTAssertEqual(out.b, c.b, accuracy: 1e-12)
        }
    }

    func testMapperRollsOffSmoothlyOnAGreyRamp() {
        let r = sigmoidRules, m = LookMath.DisplayMapper(r)
        var last = -1.0
        for i in 0...4000 {
            let v = Double(i) / 200                                   // 0 … 20, past the top (0.18 · 2^6.5 ≈ 16.3)
            let out = LookMath.output(.gray(v), r)
            XCTAssertTrue(out.isNeutral(tolerance: 1e-9), "grey \(v) → \(out)")
            XCTAssertGreaterThanOrEqual(out.g, last, "not monotonic at \(v)")
            XCTAssertLessThanOrEqual(out.g, 1)
            last = out.g
        }
        // Slope 1 on both sides of the knee, white only at the top, and 1.0 itself a little under white.
        let knee = LookMath.DisplayMapper.grey * exp2(m.kneeEV), h = 1e-5
        XCTAssertEqual((m.shoulder(knee) - m.shoulder(knee - h)) / h, 1, accuracy: 1e-6)
        XCTAssertEqual((m.shoulder(knee + h) - m.shoulder(knee)) / h, 1, accuracy: 1e-3)
        XCTAssertEqual(m.shoulder(m.top), 1, accuracy: 1e-12)
        XCTAssertEqual(m.shoulder(m.top * 8), 1, accuracy: 1e-12)
        XCTAssertLessThan(m.shoulder(4), 1)
        XCTAssertGreaterThan(m.shoulder(1), 0.85); XCTAssertLessThan(m.shoulder(1), 0.95)
        // No kink: the slope only falls from the knee up.
        var slope = 1.0 + 1e-6, x = knee
        while x < m.top {
            let s = (m.shoulder(x * 1.01) - m.shoulder(x)) / (x * 0.01)
            XCTAssertLessThanOrEqual(s, slope + 1e-9, "the slope rose at \(x)")
            slope = s; x *= 1.01
        }
    }

    /// A saturated colour pushed above white keeps its hue and fades toward white; the clamp
    /// cuts one channel and turns the same orange yellow.
    func testMapperKeepsHueAndFadesToWhiteAboveWhite() {
        let r = sigmoidRules
        for base in [LookMath.RGB(r: 1, g: 0.5, b: 0.05), LookMath.RGB(r: 1, g: 0.08, b: 0.03), LookMath.RGB(r: 0.2, g: 0.4, b: 1), LookMath.RGB(r: 0.2, g: 1, b: 0.1)] {
            let scaled = { (g: Double) in LookMath.RGB(r: base.r * g, g: base.g * g, b: base.b * g) }
            let h0 = hue(scaled(0.5)).h
            var chroma = Double.infinity
            for g in [1.0, 2, 4, 8, 16] {
                let out = LookMath.output(scaled(g), r), (h, C) = hue(out)
                if g <= 4 { XCTAssertLessThan(hueShift(h, h0), 10, "\(base) × \(g): hue \(h) from \(h0) (\(out))") }
                XCTAssertLessThanOrEqual(C, chroma + 1e-9, "\(base) × \(g) gained colour")
                chroma = C
            }
            XCTAssertLessThan(chroma, 0.02, "\(base) × 16 is nearly white")
            let far = LookMath.output(scaled(64), r)
            XCTAssertGreaterThan(min(far.r, far.g, far.b), 0.98, "\(base) × 64 → \(far): white")
        }
        let orange = LookMath.RGB(r: 4, g: 2, b: 0.2), h0 = hue(LookMath.RGB(r: 0.5, g: 0.25, b: 0.025)).h
        XCTAssertGreaterThan(hueShift(hue(LookMath.output(orange, rules)).h, h0), 20, "the clamp turns it yellow")
        XCTAssertLessThan(hueShift(hue(LookMath.output(orange, r)).h, h0), 8)
        // A pure primary reaches white too (the inset gives its other channels something to rise from).
        let red = LookMath.output(LookMath.RGB(r: 30, g: 0, b: 0), r)
        XCTAssertGreaterThan(red.g, 0.95); XCTAssertEqual(LookMath.output(LookMath.RGB(r: 30, g: 0, b: 0), rules), LookMath.RGB(r: 1, g: 0, b: 0))
    }

    func testMapperIsFiniteForZeroNegativeAndHugeInputs() {
        let r = sigmoidRules
        for v in [0.0, -0.5, 1e-30, 1e6, 1e30, Double.greatestFiniteMagnitude, .infinity] {
            for c in [LookMath.RGB.gray(v), LookMath.RGB(r: v, g: 1, b: 0), LookMath.RGB(r: 0, g: 0.3, b: v)] {
                let out = LookMath.output(c, r)
                for x in [out.r, out.g, out.b] { XCTAssertTrue(x.isFinite && x >= 0 && x <= 1, "\(c) → \(out)") }
            }
        }
        XCTAssertEqual(LookMath.output(.gray(0), r), .gray(0))
        XCTAssertEqual(LookMath.output(.gray(.infinity), r).g, 1, accuracy: 1e-12)
    }
}
