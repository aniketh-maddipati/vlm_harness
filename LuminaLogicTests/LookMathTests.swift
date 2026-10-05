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
        XCTAssertEqual(rules.lookStages, ["exposure", "whiteBalance", "whitesBlacks", "tone", "contrast", "curve", "colour", "mixer", "clarity", "sharpen", "vignette"])
        for s in rules.lookStages { XCTAssertNotNil(rules.stages[s], s) }
        XCTAssertNoThrow(try rules.validate())
        var bad = rules!; bad.order = ["exposure", "rawDevelop", "outputTransform"]
        XCTAssertThrowsError(try bad.validate())
        XCTAssertEqual(try LookRules.load(json: try rules.encoded()), rules, "rules survive a re-encode (the loop rewrites the file)")
    }

    /// A rules file written before a stage existed still loads: the stage takes its canonical
    /// place with the code's own numbers, and every other stage keeps the file's.
    func testRulesFilesFromBeforeAStageExistedStillLoad() throws {
        var old = rules!
        for (name, _) in LookRules.addedStages { old.order.removeAll { $0 == name }; old.stages[name] = nil }
        XCTAssertThrowsError(try old.validate(), "as decoded, it names too few stages")
        let loaded = try LookRules.load(json: try old.encoded())
        XCTAssertEqual(loaded.order, LookRules.canonicalOrder)
        for (name, _) in LookRules.addedStages { XCTAssertEqual(loaded.stages[name], LookRules.Stage()) }
        XCTAssertEqual(loaded.stages["tone"], rules.stages["tone"]); XCTAssertEqual(loaded.stages["vignette"], rules.stages["vignette"])
        // The code's fallbacks are the shipped numbers: the same render with or without the entries.
        for text in ["tc:+30,-10,+20", "crv:0,0.05/0.4,0.5/1,0.95 crvb:0,0/0.5,0.4/1,1", "ev:+0.50 con:+20 tc:-40,+25,0 sat:+10"] {
            let look = try Look.parse(text)
            for c in [LookMath.RGB.gray(0.18), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25)] {
                XCTAssertEqual(LookMath.flat(c, look: look, asShot: asShot, rules: loaded), LookMath.flat(c, look: look, asShot: asShot, rules: rules), text)
            }
        }
    }

    /// A look that uses none of the added keys goes through none of the added stages: the chain
    /// gives what the stages that existed before give, bit for bit, with the added stages named
    /// in the order or not.
    func testLooksWithoutTheAddedKeysRenderAsBefore() throws {
        var before = rules!
        for (name, _) in LookRules.addedStages { before.order.removeAll { $0 == name } }          // the order as it was
        let colours: [LookMath.RGB] = [.gray(0.02), .gray(0.18), .gray(0.9), .gray(1.1), LookMath.RGB(r: 0.5, g: 0.2, b: 0.2), LookMath.RGB(r: 0.15, g: 0.2, b: 0.6), LookMath.RGB(r: 0.7, g: 0.6, b: 0.1)]
        var looks = sweep.map { Look.single($0.0, $0.1, asShot: asShot)! }
        for s in ["ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0", "ev:-1.20 con:-30 hl:+50 sh:-40 wh:+30 bl:+20 vib:-40 sat:+25 vig:-40",
                  "ev:+0.30 wb:3200/-20 con:+40 bw:1 nr:30 crop:0.1,0.1,0.8,0.8/2", "", "vig:+35 rot:90"] { looks.append(try Look.parse(s)) }
        for look in looks {
            XCTAssertFalse(look.runs("curve")); XCTAssertFalse(look.runs("mixer"))
            for c in colours {
                let a = LookMath.flat(c, look: look, asShot: asShot, rules: rules, vignetteR: 0.8), b = LookMath.flat(c, look: look, asShot: asShot, rules: before, vignetteR: 0.8)
                XCTAssertTrue(a.r == b.r && a.g == b.g && a.b == b.b, "\(look.format()) on \(c): \(a) vs \(b)")
            }
        }
    }

    // MARK: curve (the tone curve)

    private func curved(_ text: String, _ c: LookMath.RGB) throws -> LookMath.RGB { LookMath.flat(c, look: try Look.parse(text), asShot: asShot, rules: rules) }
    private func perc(_ v: Double) -> Double { LookMath.perceptual(v, rules) }

    func testToneCurveSplineIsThePagesAndNeverFalls() throws {
        typealias P = Look.ToneCurve.Point
        // The page's cSpline on three points, worked by hand: slopes 1.2 and 0.8, tangents 1.2, 1.0, 0.8.
        let f = LookMath.CurveSpline([P(0, 0), P(0.5, 0.6), P(1, 1)])
        XCTAssertEqual(f(0.25), 0.3125, accuracy: 1e-12); XCTAssertEqual(f(0.5), 0.6, accuracy: 1e-12); XCTAssertEqual(f(0), 0); XCTAssertEqual(f(1), 1)
        XCTAssertEqual(f(0.75), 0.5 * 0.6 + 0.125 * 0.5 * 1.0 + 0.5 * 1.0 - 0.125 * 0.5 * 0.8, accuracy: 1e-12)
        // Two points are a straight line; beyond the first and last point the curve is flat.
        let line = LookMath.CurveSpline([P(0.2, 0.1), P(0.8, 0.9)])
        XCTAssertEqual(line(0.5), 0.5, accuracy: 1e-12); XCTAssertEqual(line(0.1), 0.1); XCTAssertEqual(line(0.95), 0.9)
        XCTAssertEqual(LookMath.CurveSpline([])(0.37), 0.37); XCTAssertEqual(LookMath.CurveSpline([P(0.5, 0.2)])(0.37), 0.37)
        // A point dragged below its left neighbour: raised to it. The dip becomes a flat span.
        let fallen = [P(0, 0), P(0.3, 0.8), P(0.6, 0.2), P(1, 1)]
        XCTAssertEqual(LookMath.curveRepaired(fallen), [P(0, 0), P(0.3, 0.8), P(0.6, 0.8), P(1, 1)])
        XCTAssertEqual(LookMath.curveRepaired([P(0, 1.4), P(0.5, -3), P(1, 0.5)]), [P(0, 1), P(0.5, 1), P(1, 1)], "y is kept in 0…1 first")
        let rising = [P(0, 0.1), P(0.4, 0.3), P(1, 0.9)]
        XCTAssertEqual(LookMath.curveRepaired(rising), rising, "a rising curve is untouched")
        let g = LookMath.CurveSpline(fallen)
        XCTAssertEqual(g(0.3), 0.8, accuracy: 1e-12); XCTAssertEqual(g(0.45), 0.8, accuracy: 1e-12); XCTAssertEqual(g(0.6), 0.8, accuracy: 1e-12)
        // Whatever the points (seeded, most of them falling somewhere), the spline and the tables never fall.
        var seed: UInt64 = 0x1234_5678_9abc_def1
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for _ in 0..<300 {
            let n = 2 + Int(next() * 9)
            var xs = (0..<n).map { _ in (next() * 10000).rounded() / 10000 }.sorted()
            for i in 1..<n where xs[i] <= xs[i - 1] { xs[i] = xs[i - 1] + 0.0001 }
            func points() -> [P] { xs.map { P(min(1, $0), next() < 0.15 ? 2 * next() - 0.5 : next()) } }
            let s = LookMath.CurveSpline(points())
            var last = -1.0
            for i in 0...2000 { let y = s(Double(i) / 2000); XCTAssertGreaterThanOrEqual(y, last - 1e-12, "spline fell at \(Double(i) / 2000): \(s.xs) \(s.ys)"); XCTAssertTrue(y >= 0 && y <= 1); last = y }
            var curve = Look.ToneCurve(); curve.rgb = points(); curve.red = points(); curve.blue = points()
            let t = LookMath.curveTables(curve, rules)
            for table in [t.r, t.g, t.b] {
                XCTAssertEqual(table.count, LookMath.curveNodes)
                for (a, b) in zip(table, table.dropFirst()) { XCTAssertGreaterThanOrEqual(b, a); XCTAssertTrue(a >= 0 && b <= 1) }
            }
        }
    }

    func testToneCurveStage() throws {
        // No curve: no stage, the colour itself.
        XCTAssertEqual(try curved("tc:0,0,0 crv:0,0/1,1", .gray(0.3)), .gray(0.3))
        let identity = LookMath.curveTables(Look.ToneCurve(), rules)
        for (i, v) in identity.g.enumerated() { XCTAssertEqual(v, Double(i) / 255, accuracy: 1e-15) }
        // The region sliders move the curve at a quarter, a half, three quarters (display-referred): ±50 is ±0.25.
        let per = rules.k("curve", "regionPerUnit", 0.005)
        XCTAssertEqual(perc(try curved("tc:0,+20,0", .gray(LookMath.linear(0.5, rules))).g), 0.5 + 20 * per, accuracy: 2e-3)
        XCTAssertEqual(perc(try curved("tc:-30,0,0", .gray(LookMath.linear(0.25, rules))).g), 0.25 - 30 * per, accuracy: 2e-3)
        XCTAssertEqual(perc(try curved("tc:0,0,+50", .gray(LookMath.linear(0.75, rules))).g), 1.0, accuracy: 2e-3)
        XCTAssertEqual(try curved("tc:+50,+50,+50", .gray(0)).g, 0, accuracy: 1e-12); XCTAssertEqual(try curved("tc:-50,-50,-50", .gray(1)).g, 1, accuracy: 1e-12)
        // A point curve: through its points, flat beyond its ends (a lifted black, a lowered white).
        XCTAssertEqual(perc(try curved("crv:0,0/0.5,0.6/1,1", .gray(LookMath.linear(0.25, rules))).g), 0.3125, accuracy: 2e-3)
        XCTAssertEqual(perc(try curved("crv:0,0.1/1,0.9", .gray(0)).g), 0.1, accuracy: 1e-9); XCTAssertEqual(perc(try curved("crv:0,0.1/1,0.9", .gray(1)).g), 0.9, accuracy: 1e-9)
        // Above white the curve goes on at slope 1 from where it ended.
        XCTAssertEqual(perc(try curved("crv:0,0.1/1,0.9", .gray(LookMath.linear(1.1, rules))).g), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try curved("tc:0,+20,0", .gray(1.3)).g, 1.3, accuracy: 1e-9)
        // With points set for all channels the region sliders are a read-out, not a second curve (as on the page).
        XCTAssertEqual(try curved("tc:+40,-30,+10 crv:0,0/0.5,0.6/1,1", .gray(0.2)), try curved("crv:0,0/0.5,0.6/1,1", .gray(0.2)))
        XCTAssertNotEqual(try curved("tc:+40,-30,+10 crvr:0,0/0.5,0.6/1,1", .gray(0.2)), try curved("crvr:0,0/0.5,0.6/1,1", .gray(0.2)), "a channel curve does not replace them")
        // Composite, then channel: red through both curves, green and blue through the first only.
        let both = try curved("crv:0,0/0.5,0.6/1,1 crvr:0,0/0.5,0.4/1,1", .gray(0.2)), first = try curved("crv:0,0/0.5,0.6/1,1", .gray(0.2))
        XCTAssertEqual(both.g, first.g); XCTAssertEqual(both.b, first.b)
        XCTAssertEqual(perc(both.r), LookMath.CurveSpline([.init(0, 0), .init(0.5, 0.4), .init(1, 1)])(perc(first.r)), accuracy: 2e-3)
        XCTAssertLessThan(both.r, first.r)
    }

    /// Monotonic on a grey ramp whatever the curve; grey in → grey out for the all-channels
    /// curve and the region sliders (the channel curves tint by design, as white balance does).
    func testToneCurveIsMonotonicAndKeepsGreyGrey() throws {
        let curves = ["tc:+50,+50,+50", "tc:-50,-50,-50", "tc:+50,-50,+50", "tc:-50,+50,-50", "tc:+10,0,-8", "tc:0,0,+1",
                      "crv:0,0/0.25,0.2/0.6,0.7125/1,1", "crv:0,0.2/1,0.8", "crv:0,1/1,0", "crv:0,0/0.3,0.8/0.6,0.2/1,1", "crv:0.3,0/0.7,1", "crv:0,0/0.02,1/0.04,0/0.06,1/1,1",
                      "crv:0,0.5/1,0.5", "tc:+20,0,0 crv:0,0/0.5,0.3/1,1"]
        let channels = ["crvr:0,0.05/1,1", "crvg:0,0/0.5,0.2/1,0.6 crvb:0,1/1,0", "crv:0,0/0.5,0.6/1,1 crvr:0,0/0.3,0.9/0.6,0.1/1,1 crvb:0,0.3/1,0.7", "tc:-20,+30,0 crvg:0,0/0.5,0.7/1,1"]
        for text in curves + channels {
            var last = -1.0
            for v in ramp {
                let out = try curved(text, .gray(v)), y = luma(out)
                XCTAssertGreaterThanOrEqual(y, last - 1e-12, "\(text) at grey \(v): \(y) < \(last)")
                XCTAssertTrue(y.isFinite && out.r >= 0 && out.g >= 0 && out.b >= 0)
                if !channels.contains(text) { XCTAssertTrue(out.r == out.g && out.g == out.b, "\(text) tinted grey \(v): \(out)") }
                last = y
            }
        }
        XCTAssertFalse(try curved("crvr:0,0.05/1,1", .gray(0.18)).isNeutral, "a channel curve is a colour control")
        // And in the whole chain, after the other tone stages.
        var last = -1.0
        for v in ramp {
            let out = try curved("ev:+0.50 con:+30 hl:-40 sh:+30 wh:+20 bl:-10 tc:+30,-20,+25 crv:0,0/0.3,0.5/0.6,0.4/1,1 sat:+20 vib:-10", .gray(v))
            XCTAssertGreaterThanOrEqual(luma(out), last - 1e-9); XCTAssertTrue(out.isNeutral, "\(out)"); last = luma(out)
        }
    }

    // MARK: mixer (the colour mixer)

    private func hueChroma(_ c: LookMath.RGB) -> (h: Double, C: Double, L: Double) {
        let lab = LookMath.toOklab(c)
        var h = atan2(lab.b, lab.a) * 180 / .pi
        if h < 0 { h += 360 }
        return (h, hypot(lab.a, lab.b), lab.L)
    }
    private func hueGap(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return d > 180 ? 360 - d : d }
    /// A colour of the given Oklab hue, lightness and chroma (inside sRGB for the values used here).
    private func colour(hue: Double, L: Double = 0.7, C: Double = 0.08) -> LookMath.RGB {
        LookMath.fromOklab(L, C * cos(hue * .pi / 180), C * sin(hue * .pi / 180))
    }
    /// A deterministic spread of the 24 values, some of them at the ends of the range.
    private func mixers() -> [Look.Mixer] {
        var seed: UInt64 = 0x9e37_79b9_7f4a_7c15
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        func eight() -> [Double] { (0..<8).map { _ in let v = next(); return v < 0.15 ? -100 : v > 0.85 ? 100 : (200 * next() - 100).rounded() } }
        var out: [Look.Mixer] = []
        for _ in 0..<40 { out.append(Look.Mixer(hue: eight(), saturation: eight(), luminance: eight())) }
        out.append(Look.Mixer(hue: Array(repeating: 100, count: 8), saturation: Array(repeating: 100, count: 8), luminance: Array(repeating: 100, count: 8)))
        out.append(Look.Mixer(hue: Array(repeating: -100, count: 8), saturation: Array(repeating: -100, count: 8), luminance: Array(repeating: -100, count: 8)))
        return out
    }

    func testMixerBandWeightsAreSmoothAndSumToOne() {
        let centres = LookMath.mixerCentres(rules)
        XCTAssertEqual(centres.count, Look.Mixer.colours.count)
        XCTAssertEqual(centres, centres.sorted(), "the centres ascend, red first"); XCTAssertEqual(Set(centres).count, 8)
        XCTAssertTrue(centres.allSatisfy { $0 >= 0 && $0 < 360 })
        XCTAssertEqual(LookMath.mixerCentres(LookRules()), LookMath.mixerHueDefaults, "the code's fallbacks")
        XCTAssertEqual(centres, LookMath.mixerHueDefaults, "…are the shipped numbers")
        var last = LookMath.mixerWeights(hueDegrees: 359.99, centres: centres)
        for step in 0...3600 {
            let h = Double(step) / 10
            let w = LookMath.mixerWeights(hueDegrees: h, centres: centres)
            XCTAssertEqual(w.reduce(0, +), 1, accuracy: 1e-12, "at \(h)")
            XCTAssertTrue(w.allSatisfy { $0 >= 0 && $0 <= 1 }); XCTAssertLessThanOrEqual(w.filter { $0 > 0 }.count, 2)
            for (a, b) in zip(w, last) { XCTAssertLessThan(abs(a - b), 0.02, "a weight jumped at \(h)") }          // smooth, across 0° too
            last = w
        }
        // Each band is alone at its own centre, and shares evenly half way to its neighbour.
        for (i, c) in centres.enumerated() {
            XCTAssertEqual(LookMath.mixerWeights(hueDegrees: c, centres: centres)[i], 1, accuracy: 1e-12, Look.Mixer.colours[i])
            let next = i == 7 ? centres[0] + 360 : centres[i + 1], mid = (c + next) / 2
            let w = LookMath.mixerWeights(hueDegrees: mid.truncatingRemainder(dividingBy: 360), centres: centres)
            XCTAssertEqual(w[i], 0.5, accuracy: 1e-9); XCTAssertEqual(w[(i + 1) % 8], 0.5, accuracy: 1e-9)
        }
        // The band names mean what they say: sRGB's primaries fall in their bands.
        func band(_ c: LookMath.RGB) -> String { Look.Mixer.colours[LookMath.mixerWeights(hueDegrees: hueChroma(c).h, centres: centres).enumerated().max { $0.element < $1.element }!.offset] }
        XCTAssertEqual(band(LookMath.RGB(r: 1, g: 0, b: 0)), "red"); XCTAssertEqual(band(LookMath.RGB(r: 1, g: 1, b: 0)), "yellow")
        XCTAssertEqual(band(LookMath.RGB(r: 0, g: 1, b: 0)), "green"); XCTAssertEqual(band(LookMath.RGB(r: 0, g: 1, b: 1)), "aqua")
        XCTAssertEqual(band(LookMath.RGB(r: 0, g: 0, b: 1)), "blue"); XCTAssertEqual(band(LookMath.RGB(r: 1, g: 0, b: 1)), "magenta")
        XCTAssertEqual(band(LookMath.RGB(r: 1, g: 0.214, b: 0)), "orange"); XCTAssertEqual(band(LookMath.RGB(r: 0.214, g: 0, b: 1)), "purple")          // sRGB 255,128,0 and 128,0,255, linear
    }

    /// A grey is exactly the same grey for any of the 24 values, so a grey ramp goes through untouched.
    func testMixerLeavesEveryGreyExactlyAsItCame() throws {
        let greys = ramp + [1e-6, 0.003, 0.18, 2.5, 40]
        for m in mixers() {
            var look = Look(); look.mixer = m
            XCTAssertTrue(look.runs("mixer"))
            for v in greys {
                let out = LookMath.mixer(.gray(v), mixer: m, rules)
                XCTAssertTrue(out.r == v && out.g == v && out.b == v, "grey \(v) → \(out) under \(look.format())")
                XCTAssertEqual(LookMath.flat(.gray(v), look: look, asShot: asShot, rules: rules), .gray(v))
            }
            // In a whole look the ramp is as monotonic and as grey as it is without the mixer.
            var whole = try Look.parse("ev:+0.50 con:+30 hl:-40 sh:+30 tc:+20,-10,+15 sat:+30 vib:+20"); let plain = whole
            whole.mixer = m
            var last = -1.0
            for v in ramp {
                let out = LookMath.flat(.gray(v), look: whole, asShot: asShot, rules: rules), y = luma(out)
                XCTAssertGreaterThanOrEqual(y, last - 1e-9); XCTAssertTrue(out.isNeutral, "\(out)"); last = y
                XCTAssertEqual(y, luma(LookMath.flat(.gray(v), look: plain, asShot: asShot, rules: rules)), accuracy: 1e-6 * max(1, y), "the mixer moved a grey")
            }
        }
        // The changes fade in with the chroma: a nearly grey pixel barely moves, whatever its (noisy) hue.
        let all = Look.Mixer(hue: Array(repeating: 100, count: 8), saturation: Array(repeating: 100, count: 8), luminance: Array(repeating: 100, count: 8))
        for hue in stride(from: 0.0, to: 360, by: 15) {
            let near = colour(hue: hue, L: 0.6, C: 1e-4), out = LookMath.mixer(near, mixer: all, rules)
            XCTAssertLessThan(max(abs(out.r - near.r), abs(out.g - near.g), abs(out.b - near.b)), 2e-3, "hue \(hue)")
        }
        // Black and white first: no chroma is left, so the mixer has nothing to act on.
        var bw = Look(); bw.bw = true; let grey = LookMath.flat(LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), look: bw, asShot: asShot, rules: rules)
        bw.mixer = all
        let mixed = LookMath.flat(LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), look: bw, asShot: asShot, rules: rules)
        XCTAssertEqual(mixed.g, grey.g, accuracy: 1e-4); XCTAssertTrue(mixed.isNeutral)
    }

    func testMixerActsOnItsOwnBand() throws {
        let centres = LookMath.mixerCentres(rules)
        // Through Oklab and back a colour returns to about 1e-6 (the matrices' precision).
        func same(_ a: LookMath.RGB, _ b: LookMath.RGB, _ what: String) { XCTAssertEqual(a.r, b.r, accuracy: 1e-5, what); XCTAssertEqual(a.g, b.g, accuracy: 1e-5, what); XCTAssertEqual(a.b, b.b, accuracy: 1e-5, what) }
        let hueStep = rules.k("mixer", "hueDegreesPerUnit", 0.3), satStep = rules.k("mixer", "saturationPerUnit", 0.01)
        for (i, name) in Look.Mixer.colours.enumerated() {
            let own = colour(hue: centres[i]), other = colour(hue: centres[(i + 4) % 8]), before = hueChroma(own)
            var m = Look.Mixer(); m.hue[i] = 50
            var out = hueChroma(LookMath.mixer(own, mixer: m, rules))
            XCTAssertEqual(hueGap(out.h, before.h + 50 * hueStep), 0, accuracy: 0.05, "\(name) hue"); XCTAssertEqual(out.C, before.C, accuracy: 1e-5); XCTAssertEqual(out.L, before.L, accuracy: 1e-5)
            same(LookMath.mixer(other, mixer: m, rules), other, "\(name) hue moved the opposite band")
            m = Look.Mixer(); m.saturation[i] = 40
            out = hueChroma(LookMath.mixer(own, mixer: m, rules))
            XCTAssertEqual(out.C, before.C * (1 + 40 * satStep), accuracy: 1e-5, "\(name) saturation"); XCTAssertEqual(hueGap(out.h, before.h), 0, accuracy: 1e-3); XCTAssertEqual(out.L, before.L, accuracy: 1e-5)
            m.saturation[i] = -100
            XCTAssertTrue(LookMath.mixer(own, mixer: m, rules).isNeutral(tolerance: 1e-5), "\(name) saturation −100 is grey")
            same(LookMath.mixer(other, mixer: m, rules), other, name)
            m = Look.Mixer(); m.luminance[i] = 60
            let up = hueChroma(LookMath.mixer(own, mixer: m, rules)); m.luminance[i] = -60
            let down = hueChroma(LookMath.mixer(own, mixer: m, rules))
            XCTAssertGreaterThan(up.L, before.L, "\(name) luminance"); XCTAssertLessThan(down.L, before.L)
            XCTAssertEqual(up.L / before.L - 1, 60 * rules.k("mixer", "luminancePerUnit", 0.003) * before.C / (before.C + rules.k("mixer", "luminanceChromaKnee", 0.05)), accuracy: 1e-5)
            XCTAssertEqual(hueGap(up.h, before.h), 0, accuracy: 1e-3); XCTAssertEqual(up.C, before.C, accuracy: 1e-5)
            same(LookMath.mixer(other, mixer: m, rules), other, name)
        }
        // Between two bands a colour takes each band's value by its weight, smoothly.
        var m = Look.Mixer(); m.saturation[0] = 100; m.saturation[1] = -100          // red up, orange down
        var last = 10.0
        for h in stride(from: centres[0], through: centres[1], by: 0.5) {
            let c = colour(hue: h), ratio = hueChroma(LookMath.mixer(c, mixer: m, rules)).C / hueChroma(c).C
            XCTAssertLessThanOrEqual(ratio, last + 1e-9); XCTAssertLessThan(last == 10 ? 0 : last - ratio, 0.08, "a jump at hue \(h)"); last = ratio
        }
        XCTAssertEqual(last, 0, accuracy: 1e-5)
        // Nothing negative, nothing NaN, for any values on colours from black to above white.
        for m in mixers() {
            for c in [LookMath.RGB(r: 1, g: 0, b: 0), LookMath.RGB(r: 0, g: 0, b: 1), LookMath.RGB(r: 0.004, g: 0.002, b: 0.006), LookMath.RGB(r: 1.3, g: 0.9, b: 0.2), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0, g: 0, b: 0)] {
                let out = LookMath.mixer(c, mixer: m, rules)
                XCTAssertTrue(out.r.isFinite && out.g.isFinite && out.b.isFinite && out.r >= 0 && out.g >= 0 && out.b >= 0, "\(c) → \(out)")
            }
        }
        XCTAssertEqual(LookMath.mixer(LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), mixer: Look.Mixer(), rules), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), "reset: the colour itself")
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

    /// The four shape sliders at reset: the stage is, bit for bit, the one it was before they
    /// existed. The expected values are written out here from the form the stage had then.
    func testVignetteAtTheShapeResetIsBitForBitTheStageItWas() throws {
        let stops = rules.k("vignette", "stopsPerUnit", 0.02), m = rules.k("vignette", "midpoint", 0.5), f = rules.k("vignette", "feather", 0.5)
        func before(_ v: Double, vignette: Double, r: Double) -> Double {
            let e0 = m - f / 2, e1 = m + f / 2, t = min(1, max(0, (r - e0) / (e1 - e0)))
            return v * exp2(vignette * stops * (t * t * (3 - 2 * t)))
        }
        for text in ["vig:-100", "vig:-37", "vig:+60", "vig:-37 vigs:50,0,50,0"] {
            let look = try Look.parse(text)
            XCTAssertTrue(look.vignetteShape.isDefault)
            for r in stride(from: 0.0, through: 1.2, by: 0.05) {
                for v in ramp {
                    let out = LookMath.flat(.gray(v), look: look, asShot: asShot, rules: rules, vignetteR: r)
                    let want = before(v, vignette: look.vignette, r: r)
                    XCTAssertTrue(out.r == want && out.g == want && out.b == want, "\(text) r=\(r) grey \(v): \(out) vs \(want)")
                }
            }
        }
        // And the shaped form meets it there: the same edges exactly, the same distance (the circle
        // through the corners) to rounding, nothing spared.
        for aspect in [1.5, 1.0, 0.6667, 2.4] {
            let form = LookMath.VignetteForm(shape: Look.VignetteShape(), vignette: -50, aspect: aspect, rules)
            XCTAssertTrue(form.edge0 == m - f / 2 && form.edge1 == m + f / 2)
            XCTAssertEqual(form.keep, 0); XCTAssertEqual(form.power, 2); XCTAssertEqual(form.stopsPerUnit, stops)
            for (u, v) in [(0.0, 0.0), (1.0, 1.0), (1.0, 0.0), (0.0, 1.0), (0.3, -0.8), (-0.6, 0.2)] {
                let circle = hypot(u * aspect, v) / hypot(aspect, 1)          // pixels from the centre over the half diagonal
                XCTAssertEqual(form.distance(u: u, v: v), circle, accuracy: 1e-12, "aspect \(aspect) at \(u), \(v)")
                let shaped = LookMath.vignetteShaped(.gray(0.4), d: form.distance(u: u, v: v), vignette: -50, form: form, rules)
                XCTAssertEqual(shaped.g, 0.4 * LookMath.vignetteGain(r: circle, vignette: -50, rules), accuracy: 1e-12)
            }
        }
    }

    func testVignetteShape() throws {
        typealias Shape = Look.VignetteShape
        func form(_ s: Shape, vignette: Double = -60, aspect: Double = 1.5) -> LookMath.VignetteForm { LookMath.VignetteForm(shape: s, vignette: vignette, aspect: aspect, rules) }
        func corner(_ s: Shape, d: Double, vignette: Double = -60, grey: Double = 0.4) -> Double {
            LookMath.vignetteShaped(.gray(grey), d: d, vignette: vignette, form: form(s, vignette: vignette), rules).g
        }
        // Midpoint: a higher one starts the falloff farther out. Feather: 0 is a hard edge at the midpoint.
        XCTAssertGreaterThan(corner(Shape(midpoint: 80), d: 0.6), corner(Shape(midpoint: 20), d: 0.6))
        XCTAssertEqual(corner(Shape(midpoint: 100), d: 0.45), 0.4, accuracy: 1e-12, "nothing yet, well inside the midpoint")
        let hard = form(Shape(feather: 0)); XCTAssertEqual(hard.edge0, hard.edge1)
        XCTAssertEqual(corner(Shape(feather: 0), d: 0.49), 0.4, accuracy: 1e-12)
        XCTAssertEqual(corner(Shape(feather: 0), d: 0.51), 0.4 * exp2(-60 * rules.k("vignette", "stopsPerUnit", 0.02)), accuracy: 1e-12)
        XCTAssertEqual(form(Shape(feather: 100)).edge1 - form(Shape(feather: 100)).edge0, 2 * rules.k("vignette", "feather", 0.5), accuracy: 1e-12)
        // Roundness: every shape is 0 at the centre and 1 at the corners; in between, the circle
        // (reset), the frame's ellipse, the frame's rectangle. The numbers below read the shipped
        // `roundAtReset` (100: Roundness 0 is the circle the stage has always drawn).
        let at = rules.k("vignette", "roundAtReset", 100)
        for r in [-100.0, -75, -50, -25, 0, 40, 100] {
            for aspect in [1.5, 0.6667, 1.0] {
                let f = form(Shape(roundness: r), aspect: aspect)
                XCTAssertEqual(f.distance(u: 0, v: 0), 0, accuracy: 1e-12)
                for (u, v) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0)] { XCTAssertEqual(f.distance(u: u, v: v), 1, accuracy: 1e-12, "roundness \(r) aspect \(aspect)") }
                var last = 0.0          // grows along any ray from the centre
                for t in stride(from: 0.1, through: 1.0, by: 0.1) { let d = f.distance(u: 0.7 * t, v: -t); XCTAssertGreaterThan(d, last); last = d }
            }
        }
        if at == 100 {
            let ellipse = form(Shape(roundness: -50)), rect = form(Shape(roundness: -100)), circle = form(Shape(roundness: 0)), above = form(Shape(roundness: 100))
            XCTAssertEqual(ellipse.distance(u: 1, v: 0), ellipse.distance(u: 0, v: 1), accuracy: 1e-12, "the frame's ellipse reaches all four edges alike")
            XCTAssertEqual(ellipse.distance(u: 1, v: 0), 0.5.squareRoot(), accuracy: 1e-12)
            XCTAssertGreaterThan(circle.distance(u: 1, v: 0), circle.distance(u: 0, v: 1), "a circle in pixels reaches the long edge's ends first")
            XCTAssertGreaterThan(rect.distance(u: 1, v: 0), 0.9, "the rectangle hugs the edges"); XCTAssertEqual(rect.distance(u: 1, v: 0), rect.distance(u: 0, v: 1), accuracy: 1e-12)
            XCTAssertEqual(rect.power, rules.k("vignette", "rectPower", 8))
            XCTAssertEqual(above, circle, "above the reset there is nothing left to round")
        }
        // Highlights: a darkening vignette spares bright pixels, white in full at 100; a lightening one ignores it.
        let plain = corner(Shape(midpoint: 49), d: 1, grey: 0.9), kept = corner(Shape(highlights: 60), d: 1, grey: 0.9), all = corner(Shape(highlights: 100), d: 1, grey: 1)
        XCTAssertLessThan(plain, kept); XCTAssertLessThan(kept, 0.9); XCTAssertEqual(all, 1, accuracy: 1e-12)
        XCTAssertEqual(corner(Shape(highlights: 100), d: 1, grey: 0.0001) / 0.0001, corner(Shape(midpoint: 49), d: 1, grey: 0.0001) / 0.0001, accuracy: 1e-3, "the shadows get the whole vignette")
        XCTAssertEqual(form(Shape(highlights: 100), vignette: 60).keep, 0)
        XCTAssertEqual(corner(Shape(highlights: 100), d: 1, vignette: 60), corner(Shape(midpoint: 50.0001), d: 1, vignette: 60), accuracy: 1e-9)
        // Monotonic on a grey ramp and grey-preserving at every distance, for any shape and amount.
        for text in ["vig:-100 vigs:50,0,50,100", "vig:-100 vigs:0,-100,100,60", "vig:-45 vigs:80,-50,0,30", "vig:+100 vigs:20,-30,80,100", "vig:-100 vigs:100,+100,100,100"] {
            let look = try Look.parse(text)
            for d in [0.0, 0.4, 0.7, 1.0, 1.3] {
                var last = -1.0
                for v in ramp {
                    let out = LookMath.flat(.gray(v), look: look, asShot: asShot, rules: rules, vignetteR: d)
                    XCTAssertTrue(out.isNeutral(tolerance: 1e-12), "\(text) d=\(d) grey \(v): \(out)")
                    XCTAssertGreaterThanOrEqual(out.g, last, "\(text) d=\(d) not monotonic at grey \(v)")
                    XCTAssertTrue(out.g.isFinite && out.g >= 0)
                    last = out.g
                }
            }
        }
        // The shape alone, without an amount, is no stage at all.
        XCTAssertEqual(LookMath.flat(.gray(0.4), look: try Look.parse("vigs:0,-100,0,100"), asShot: asShot, rules: rules, vignetteR: 1), .gray(0.4))
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
