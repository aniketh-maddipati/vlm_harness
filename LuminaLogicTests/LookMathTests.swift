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
        // Shadows + lifts the darks more than the lights; highlights − lowers the lights, not the darks.
        let sh = Look.single("Shadows", 80, asShot: asShot)!
        XCTAssertGreaterThan(luma(run(sh, dark)) / dark, luma(run(sh, light)) / light)
        XCTAssertGreaterThan(luma(run(sh, dark)), dark)
        let hl = Look.single("Highlights", -80, asShot: asShot)!
        XCTAssertLessThan(luma(run(hl, light)), light)
        XCTAssertEqual(luma(run(hl, dark)), dark, accuracy: 1e-9)
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
}
