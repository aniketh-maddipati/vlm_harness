import XCTest
@testable import Lumina

/// The look string is the Edit step's only state: parse ⇄ format must round-trip, unknown keys
/// must fail loudly, and out-of-range values clamp to the roadmap's slider ranges.
final class LookStringTests: XCTestCase {
    func testRoadmapExampleRoundTrips() throws {
        let s = "ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0"
        let l = try Look.parse(s)
        XCTAssertEqual(l.ev, 0.7, accuracy: 1e-9)
        XCTAssertEqual(l.wb, Look.WhiteBalance(kelvin: 5200, tint: 3))
        XCTAssertEqual(l.contrast, 12); XCTAssertEqual(l.highlights, -40); XCTAssertEqual(l.shadows, 25)
        XCTAssertEqual(l.whites, 0); XCTAssertEqual(l.blacks, -8); XCTAssertEqual(l.vibrance, 10)
        XCTAssertEqual(l.saturation, 0); XCTAssertEqual(l.clarity, 15); XCTAssertEqual(l.sharpen, 30); XCTAssertEqual(l.vignette, 0)
        XCTAssertNil(l.crop)
        XCTAssertEqual(l.format(), s)
        XCTAssertEqual(try Look.parse(l.format()), l)
    }

    func testNeutralAndOrderIndependence() throws {
        XCTAssertTrue(try Look.parse("").isNeutral)
        XCTAssertTrue(try Look.parse("none").isNeutral)
        XCTAssertTrue(try Look.parse("ev:0 con:0").isNeutral)
        XCTAssertEqual(try Look.parse("sat:+5 ev:-1"), try Look.parse("ev:-1.00 sat:5"))
        XCTAssertEqual(Look().format(), "ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:0")
    }

    func testUnknownKeysAndBadNumbersThrow() {
        XCTAssertThrowsError(try Look.parse("exposure:1"))
        XCTAssertThrowsError(try Look.parse("ev:one"))
        XCTAssertThrowsError(try Look.parse("ev:1 ev:2"))
        XCTAssertThrowsError(try Look.parse("wb:5200"))
        XCTAssertThrowsError(try Look.parse("crop:0.5,0.5,0.6,0.6"))      // leaves the frame
        XCTAssertThrowsError(try Look.parse("ev"))
    }

    func testValuesClampToTheSliderRanges() throws {
        let l = try Look.parse("ev:+9 con:-500 shp:999 wb:100/+900 vig:1e9")
        XCTAssertEqual(l.ev, 5); XCTAssertEqual(l.contrast, -100); XCTAssertEqual(l.sharpen, 150)
        XCTAssertEqual(l.wb, Look.WhiteBalance(kelvin: 2000, tint: 150)); XCTAssertEqual(l.vignette, 100)
        XCTAssertThrowsError(try Look.parse("ev:nan"), "nan is not a number")
    }

    func testCropAndBW() throws {
        let l = try Look.parse("crop:0.1,0.2,0.5,0.6/-1.5 bw:1")
        XCTAssertEqual(l.crop, Look.Crop(x: 0.1, y: 0.2, w: 0.5, h: 0.6, rotate: -1.5))
        XCTAssertTrue(l.bw)
        XCTAssertTrue(l.format().hasSuffix("bw:1 crop:0.1000,0.2000,0.5000,0.6000/-1.50"))
        XCTAssertEqual(try Look.parse(l.format()), l)
    }

    /// `rot`: a quarter turn, geometry like the crop. Written only when set, last.
    func testQuarterTurn() throws {
        XCTAssertEqual(Look().rot, 0)
        for r in [90, 180, 270] {
            let l = try Look.parse("rot:\(r)")
            XCTAssertEqual(l.rot, r)
            XCTAssertTrue(l.isNeutral, "a turn is geometry, not a look stage")
            XCTAssertTrue(l.format().hasSuffix(" vig:0 rot:\(r)"))
            XCTAssertEqual(try Look.parse(l.format()), l)
        }
        XCTAssertEqual(try Look.parse("rot:0"), Look())
        XCTAssertFalse(try Look.parse("rot:0").format().contains("rot"), "the reset value is not written")
        XCTAssertEqual(try Look.parse("rot:-90").rot, 270); XCTAssertEqual(try Look.parse("rot:360").rot, 0); XCTAssertEqual(try Look.parse("rot:450").rot, 90)
        XCTAssertThrowsError(try Look.parse("rot:45")); XCTAssertThrowsError(try Look.parse("rot:90.5"))
        XCTAssertThrowsError(try Look.parse("rot:right")); XCTAssertThrowsError(try Look.parse("rot:90 rot:180"))
        // Separate from the crop's straighten angle, and written after the crop.
        let both = try Look.parse("rot:270 crop:0.1,0.2,0.5,0.6/-1.5")
        XCTAssertEqual(both.crop?.rotate, -1.5); XCTAssertEqual(both.rot, 270)
        XCTAssertTrue(both.format().hasSuffix("crop:0.1000,0.2000,0.5000,0.6000/-1.50 rot:270"))
        XCTAssertEqual(try Look.parse(both.format()), both)
    }

    /// `vigs:midpoint,roundness,feather,highlights`: the vignette's shape, written only off its reset.
    func testVignetteShape() throws {
        XCTAssertTrue(Look().vignetteShape.isDefault)
        XCTAssertEqual(Look().vignetteShape, Look.VignetteShape(midpoint: 50, roundness: 0, feather: 50, highlights: 0))
        let l = try Look.parse("vig:-30 vigs:40,-20,70,25")
        XCTAssertEqual(l.vignetteShape, Look.VignetteShape(midpoint: 40, roundness: -20, feather: 70, highlights: 25))
        XCTAssertTrue(l.format().hasSuffix("vig:-30 vigs:40,-20,70,25"))
        XCTAssertEqual(try Look.parse(l.format()), l)
        XCTAssertTrue(try Look.parse("vigs:50,+35,50,0").format().hasSuffix("vig:0 vigs:50,+35,50,0"), "roundness is signed like the other ± sliders")
        // The reset is not written, so a look that never touched the shape is the string it was.
        XCTAssertEqual(try Look.parse("vig:-30 vigs:50,0,50,0"), try Look.parse("vig:-30"))
        XCTAssertEqual(try Look.parse("vig:-30 vigs:50,0,50,0").format(), "ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:-30")
        // A shape without an amount draws nothing: the look is neutral.
        XCTAssertTrue(try Look.parse("vigs:10,-100,0,100").isNeutral)
        // Clamped into Lightroom's ranges; the wrong number of values or a word is an error.
        XCTAssertEqual(try Look.parse("vigs:-5,-500,400,101").vignetteShape, Look.VignetteShape(midpoint: 0, roundness: -100, feather: 100, highlights: 100))
        XCTAssertThrowsError(try Look.parse("vigs:50,0,50")); XCTAssertThrowsError(try Look.parse("vigs:50,0,50,0,0"))
        XCTAssertThrowsError(try Look.parse("vigs:50,round,50,0")); XCTAssertThrowsError(try Look.parse("vigs:"))
    }

    /// The tone curve: `tc:dark,mid,light` and the point curves `crv`, `crvr`, `crvg`, `crvb`.
    func testToneCurve() throws {
        typealias P = Look.ToneCurve.Point
        XCTAssertTrue(Look().curve.isNeutral)
        let l = try Look.parse("tc:+10,0,-8 crv:0,0/0.25,0.2/0.6,0.7125/1,1 crvr:0,0.05/1,1 crvb:0,0/0.5,0.4/1,0.9")
        XCTAssertEqual(l.curve.dark, 10); XCTAssertEqual(l.curve.mid, 0); XCTAssertEqual(l.curve.light, -8)
        XCTAssertEqual(l.curve.rgb, [P(0, 0), P(0.25, 0.2), P(0.6, 0.7125), P(1, 1)])
        XCTAssertEqual(l.curve.red, [P(0, 0.05), P(1, 1)]); XCTAssertNil(l.curve.green); XCTAssertEqual(l.curve.blue?.count, 3)
        XCTAssertFalse(l.isNeutral)
        XCTAssertTrue(l.format().hasSuffix("vig:0 tc:+10,0,-8 crv:0,0/0.25,0.2/0.6,0.7125/1,1 crvr:0,0.05/1,1 crvb:0,0/0.5,0.4/1,0.9"), l.format())
        XCTAssertEqual(try Look.parse(l.format()), l)
        // Reset values are not written: the region sliders at 0, a curve that is the diagonal.
        XCTAssertEqual(try Look.parse("tc:0,0,0 crv:0,0/1,1 crvg:0,0/0.5,0.5/1,1"), Look())
        XCTAssertEqual(try Look.parse("tc:0,0,0 crv:0,0/1,1").format(), Look().format())
        XCTAssertFalse(try Look.parse("tc:0,+5,0").isNeutral)
        // Numbers clamp (regions to ±50, points into 0…1 at four decimals); the list's shape is checked.
        XCTAssertEqual(try Look.parse("tc:-80,+51,+3").curve.dark, -50); XCTAssertEqual(try Look.parse("tc:-80,+51,+3").curve.mid, 50)
        XCTAssertEqual(try Look.parse("crv:-0.2,-1/0.33333333,0.5/1.5,2").curve.rgb, [P(0, 0), P(0.3333, 0.5), P(1, 1)])
        XCTAssertEqual(try Look.parse("crv:0,0/0.33333333,0.5/1,1").format(), try Look.parse("crv:0,0/0.3333,0.5/1,1").format())
        XCTAssertThrowsError(try Look.parse("tc:1,2")); XCTAssertThrowsError(try Look.parse("tc:a,b,c"))
        XCTAssertThrowsError(try Look.parse("crv:0,0"), "one point is not a curve")
        XCTAssertThrowsError(try Look.parse("crv:0,0/0.5/1,1")); XCTAssertThrowsError(try Look.parse("crv:0,0/0.5,x/1,1"))
        XCTAssertThrowsError(try Look.parse("crv:0,0/0.6,0.5/0.4,0.7/1,1"), "x must increase")
        XCTAssertThrowsError(try Look.parse("crv:0,0/0.5,0.5/0.5,0.7/1,1"), "x must increase strictly")
        XCTAssertThrowsError(try Look.parse("crvr:" + (0...Look.ToneCurve.maxPoints).map { "\(Double($0) / 100),0.5" }.joined(separator: "/")), "too many points")
        XCTAssertThrowsError(try Look.parse("crvx:0,0/1,1"), "unknown key")
        // A falling curve is kept as written (it is the page's state); the stage repairs it when it renders.
        XCTAssertEqual(try Look.parse("crv:0,0/0.3,0.8/0.6,0.2/1,1").curve.rgb?[2], P(0.6, 0.2))
        XCTAssertEqual(Look.keys.filter { $0.hasPrefix("crv") || $0 == "tc" }, ["tc", "crv", "crvr", "crvg", "crvb"])
    }

    /// The colour mixer: `mixh`, `mixs`, `mixl`, eight values each (red … magenta).
    func testColourMixer() throws {
        XCTAssertEqual(Look.Mixer.colours, ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"])
        XCTAssertTrue(Look().mixer.isNeutral)
        let l = try Look.parse("mixh:0,+10,0,0,0,-25,0,0 mixs:+40,0,0,-100,0,0,0,+5 mixl:0,0,0,0,0,-30,0,0")
        XCTAssertEqual(l.mixer.hue, [0, 10, 0, 0, 0, -25, 0, 0]); XCTAssertEqual(l.mixer.saturation, [40, 0, 0, -100, 0, 0, 0, 5]); XCTAssertEqual(l.mixer.luminance[5], -30)
        XCTAssertFalse(l.isNeutral)
        XCTAssertTrue(l.format().hasSuffix("vig:0 mixh:0,+10,0,0,0,-25,0,0 mixs:+40,0,0,-100,0,0,0,+5 mixl:0,0,0,0,0,-30,0,0"), l.format())
        XCTAssertEqual(try Look.parse(l.format()), l)
        // Only the rows in use are written; all zeros is no key at all.
        XCTAssertTrue(try Look.parse("mixs:0,0,+7,0,0,0,0,0").format().hasSuffix("vig:0 mixs:0,0,+7,0,0,0,0,0"))
        XCTAssertEqual(try Look.parse("mixh:0,0,0,0,0,0,0,0 mixl:0,0,0,0,0,0,0,0"), Look())
        XCTAssertEqual(try Look.parse("mixh:0,0,0,0,0,0,0,0").format(), Look().format())
        // Clamped to ±100; eight values exactly.
        XCTAssertEqual(try Look.parse("mixl:-500,0,0,0,0,0,0,+101").mixer.luminance, [-100, 0, 0, 0, 0, 0, 0, 100])
        XCTAssertThrowsError(try Look.parse("mixh:0,0,0,0,0,0,0")); XCTAssertThrowsError(try Look.parse("mixh:0,0,0,0,0,0,0,0,0"))
        XCTAssertThrowsError(try Look.parse("mixs:0,0,red,0,0,0,0,0")); XCTAssertThrowsError(try Look.parse("mix:0,0,0,0,0,0,0,0"), "unknown key")
    }

    /// All four additions in one string, in canonical order, and a string without them unchanged.
    func testEveryAddedKeyTogether() throws {
        let s = "ev:+0.30 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:-30 vigs:40,-20,70,25 tc:+10,0,-8 crv:0,0/0.25,0.2/1,1 crvr:0,0.05/1,1 mixh:0,+10,0,0,0,0,0,0 mixs:0,0,0,0,0,+20,0,0 mixl:0,0,0,0,0,-15,0,0 nr:20 crop:0.1000,0.1000,0.8000,0.8000/1.50 rot:90"
        let l = try Look.parse(s)
        XCTAssertEqual(l.format(), s)
        XCTAssertEqual(try Look.parse(s.split(separator: " ").reversed().joined(separator: " ")), l, "any order")
        XCTAssertEqual(Look.keys, ["ev", "wb", "con", "hl", "sh", "wh", "bl", "vib", "sat", "clr", "shp", "vig", "vigs", "tc", "crv", "crvr", "crvg", "crvb", "mixh", "mixs", "mixl", "nr", "bw", "crop", "rot"])
        let old = "ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:-20 nr:40 bw:1 crop:0.1000,0.2000,0.5000,0.6000/-1.50"
        XCTAssertEqual(try Look.parse(old).format(), old)
    }

    func testSingleSliderLooksForTheSweep() {
        let asShot = Look.WhiteBalance(kelvin: 5100, tint: 4)
        XCTAssertEqual(Look.single("Exposure", 1.5, asShot: asShot)?.ev, 1.5)
        XCTAssertEqual(Look.single("Temperature", 8000, asShot: asShot)?.wb, Look.WhiteBalance(kelvin: 8000, tint: 4))
        XCTAssertEqual(Look.single("Tint", -20, asShot: asShot)?.wb, Look.WhiteBalance(kelvin: 5100, tint: -20))
        XCTAssertEqual(Look.single("Sharpness", 80, asShot: asShot)?.sharpen, 80)
        XCTAssertNil(Look.single("Texture", 10, asShot: asShot))
    }
}
