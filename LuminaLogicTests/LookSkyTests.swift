import CoreImage
import XCTest
@testable import Lumina

/// The blue-skies prototype (LookSky, behind `Look.skyFeatures`): the clip diagnosis and the
/// capture tip on synthetic planes, the meter, the set target, the sky-blue maths and its kernel,
/// and the flag: with it off, `blu` is an unknown key, so every look parses as before.
final class LookSkyTests: XCTestCase {
    typealias Plane = LookMasks.Plane
    let rules = try! LookTestRules.load()

    override func tearDown() { Look.skyFeatures = false }

    /// The top `rows` rows of a w × h plane set to `v`.
    private func top(_ w: Int, _ h: Int, rows: Int, _ v: Float = 1) -> Plane {
        var p = Plane(width: w, height: h)
        for y in 0..<rows { for x in 0..<w { p.values[y * w + x] = v } }
        return p
    }

    // MARK: F1 / F6

    func testDiagnosisVerdicts() {
        let sky = top(40, 30, rows: 10), none = Plane(width: 40, height: 30)
        XCTAssertEqual(LookSky.diagnose(sky: nil, white: none, clipped: none).verdict, .noSky)
        XCTAssertEqual(LookSky.diagnose(sky: sky, white: none, clipped: none).verdict, .fine)
        // half the sky white in today's render, nothing clipped at the sensor
        let d = LookSky.diagnose(sky: sky, white: top(40, 30, rows: 5), clipped: none)
        XCTAssertEqual(d.verdict, .recoverable)
        XCTAssertEqual(d.white, 0.5, accuracy: 1e-6)
        XCTAssertEqual(d.sky, 1.0 / 3, accuracy: 1e-6)
        // a quarter of the sky clipped at capture wins over white
        let c = LookSky.diagnose(sky: sky, white: top(40, 30, rows: 5), clipped: top(40, 30, rows: 2))
        XCTAssertEqual(c.verdict, .clippedAtCapture)
        XCTAssertEqual(c.clipped!, 0.2, accuracy: 1e-6)
        // clipping outside the sky does not count; maps on another grid are resampled
        let below = LookSky.diagnose(sky: sky, white: none, clipped: { var p = Plane(width: 20, height: 15); for i in 150..<300 { p.values[i] = 1 }; return p }())
        XCTAssertEqual(below.verdict, .fine)
        // without the decoder's recovery switch the clip share is unknown, never guessed
        XCTAssertNil(LookSky.diagnose(sky: sky, white: none, clipped: nil).clipped)
    }

    func testCaptureTip() {
        let sky = top(10, 10, rows: 5)
        let clipped = LookSky.diagnose(sky: sky, white: sky, clipped: top(10, 10, rows: 2))
        XCTAssertEqual(LookSky.captureTip(clipped, stopsOver: 1.2), "Sky was clipped when shot (40 % of it). About 1.5 stops less exposure would have kept it.")
        XCTAssertEqual(LookSky.captureTip(clipped, stopsOver: 0.4), "Sky was clipped when shot (40 % of it). About 0.5 stops less exposure would have kept it.")
        XCTAssertEqual(LookSky.captureTip(clipped, stopsOver: nil), "Sky was clipped when shot (40 % of it). Less exposure would have kept it.")
        XCTAssertNil(LookSky.captureTip(LookSky.diagnose(sky: sky, white: sky, clipped: Plane(width: 10, height: 10)), stopsOver: 2))
    }

    // MARK: F2 / F5

    func testMeterIgnoresSkyAndWhite() throws {
        // land at luma 0.05, a white sky on top: the meter reads the land only
        var luma = Plane(width: 64, height: 64)
        for i in 0..<luma.values.count { luma.values[i] = i < 64 * 20 ? 1 : 0.05 }
        let m = try XCTUnwrap(LookSky.meter(luma: luma, sky: top(64, 64, rows: 20), rules: rules))
        XCTAssertEqual(m.midtone, LookSky.lstar(0.05), accuracy: 0.01)
        XCTAssertGreaterThan(m.ev, 0)
        // the answer is what the exposure stage does: the midtone lands on target within a slider step
        let after = LookSky.lstar(LookMath.exposure(0.05, gain: LookMath.exposureGain(m.ev, rules), white: LookMath.exposureWhite(rules)))
        XCTAssertEqual(after, LookSky.targetL, accuracy: 1.5)
        // a frame that is all sky has nothing to meter
        XCTAssertNil(LookSky.meter(luma: luma, sky: top(64, 64, rows: 64), rules: rules))
        // already on target: no move
        var grey = Plane(width: 32, height: 32)
        let y = pow((LookSky.targetL + 16) / 116, 3)
        for i in 0..<grey.values.count { grey.values[i] = Float(y) }
        XCTAssertEqual(try XCTUnwrap(LookSky.meter(luma: grey, sky: nil, rules: rules)).ev, 0, accuracy: 0.05)
    }

    func testSetTargetIsTheMedian() {
        XCTAssertEqual(LookSky.setTarget([40, 50, 45]), 45)
        XCTAssertEqual(LookSky.setTarget([40, 50]), 45)
        XCTAssertNil(LookSky.setTarget([]))
    }

    // MARK: F4 sky blue

    private func hue(_ c: LookMath.RGB) -> Double { let l = LookMath.toOklab(c); return (atan2(l.b, l.a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
    private func chroma(_ c: LookMath.RGB) -> Double { let l = LookMath.toOklab(c); return hypot(l.a, l.b) }

    func testSkyBlueHoldsLightnessAndTurnsCyanAndGreyTowardBlue() {
        let cyan = LookMath.RGB(r: 0.3, g: 0.62, b: 0.78), grey = LookMath.RGB.gray(0.5)
        for c in [cyan, grey] {
            let out = LookMath.skyBlue(c, amount: 100)
            XCTAssertEqual(LookMath.toOklab(out).L, LookMath.toOklab(c).L, accuracy: 1e-6, "L held")
            XCTAssertEqual(hue(out), LookMath.SkyBlue.hue, accuracy: 1, "on the target hue at 100")
        }
        XCTAssertGreaterThan(chroma(LookMath.skyBlue(grey, amount: 100)), 0.03)
        // half the amount: half way round
        XCTAssertEqual(hue(LookMath.skyBlue(cyan, amount: 50)), (hue(cyan) + LookMath.SkyBlue.hue) / 2, accuracy: 1)
    }

    func testSkyBlueLeavesFarHuesAndBlueSkiesAndWhiteAlone() {
        for c in [LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0.2, g: 0.5, b: 0.2), LookMath.RGB(r: 0.7, g: 0.6, b: 0.1)] {
            let out = LookMath.skyBlue(c, amount: 100)      // the Oklab round trip is exact to ~1e-6
            XCTAssertEqual(out.r, c.r, accuracy: 1e-5, "far from blue: untouched"); XCTAssertEqual(out.g, c.g, accuracy: 1e-5); XCTAssertEqual(out.b, c.b, accuracy: 1e-5)
        }
        // a deep blue already at the target hue with chroma above the cap does not move
        let L = 0.55, C = LookMath.SkyBlue.cap(L) + 0.02, h = LookMath.SkyBlue.hue * .pi / 180
        let blue = LookMath.fromOklab(L, C * cos(h), C * sin(h))
        let out = LookMath.skyBlue(blue, amount: 100)
        XCTAssertEqual(out.r, blue.r, accuracy: 1e-5); XCTAssertEqual(out.g, blue.g, accuracy: 1e-5); XCTAssertEqual(out.b, blue.b, accuracy: 1e-5)
        // white stays white (no chroma room at L 1); amount 0 is the identity
        XCTAssertTrue(LookMath.skyBlue(.gray(1), amount: 100).isNeutral)
        XCTAssertEqual(LookMath.skyBlue(LookMath.RGB(r: 0.3, g: 0.62, b: 0.78), amount: 0), LookMath.RGB(r: 0.3, g: 0.62, b: 0.78))
    }

    func testSkyBlueStaysInGamutOnAGreyRamp() {
        for i in 0...40 {
            let out = LookMath.skyBlue(.gray(Double(i) / 40), amount: 100)
            XCTAssertGreaterThanOrEqual(min(out.r, out.g, out.b), 0)
            XCTAssertLessThanOrEqual(max(out.r, out.g, out.b), 1.0001)
        }
    }

    func testTheKernelIsTheMaths() throws {
        let pipe = try LookPipeline(rules: rules)
        var look = Look(); look.skyBlue = 70
        for c in [LookMath.RGB(r: 0.3, g: 0.62, b: 0.78), .gray(0.4), .gray(0.9), LookMath.RGB(r: 0.4, g: 0.3, b: 0.6), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25)] {
            let got = pipe.pixel(pipe.apply(look, to: pipe.flat(c, size: 16)), x: 8, y: 8), want = LookMath.skyBlue(c, amount: 70)
            XCTAssertEqual(got.r, want.r, accuracy: 0.004); XCTAssertEqual(got.g, want.g, accuracy: 0.004); XCTAssertEqual(got.b, want.b, accuracy: 0.004)
        }
    }

    // MARK: the flag

    func testBluIsAnUnknownKeyWithTheFlagOff() throws {
        Look.skyFeatures = false
        XCTAssertThrowsError(try Look.parse("ev:0 mask:sky/blu=40"))
        XCTAssertThrowsError(try Look.parse("ev:0 blu:40"), "never a global key")
        Look.skyFeatures = true
        let l = try Look.parse("ev:0 mask:sky/ev=-1.00,blu=40")
        XCTAssertEqual(l.locals.first?.skyBlue, 40)
        XCTAssertEqual(l.locals.first?.look.skyBlue, 40)
        XCTAssertEqual(try Look.parse(l.format()), l, "round trip")
        XCTAssertEqual(try Look.parse("ev:0 mask:sky/blu=400").locals.first?.skyBlue, 100, "clamped to 0 … 100")
        XCTAssertThrowsError(try Look.parse("ev:0 blu:40"), "still never a global key")
    }

    func testALookWithoutBluRendersTheSameWithTheFlagOn() throws {
        let pipe = try LookPipeline(rules: rules)
        let look = try Look.parse("ev:+0.30 con:+10 hl:-20 vib:+15")
        let c = LookMath.RGB(r: 0.3, g: 0.5, b: 0.7)
        Look.skyFeatures = false
        let off = pipe.pixel(pipe.apply(look, to: pipe.flat(c, size: 8)), x: 4, y: 4)
        Look.skyFeatures = true
        let on = pipe.pixel(pipe.apply(look, to: pipe.flat(c, size: 8)), x: 4, y: 4)
        XCTAssertEqual(off, on)
    }
}
