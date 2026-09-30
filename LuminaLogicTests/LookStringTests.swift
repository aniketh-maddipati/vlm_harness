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

    func testSingleSliderLooksForTheSweep() {
        let asShot = Look.WhiteBalance(kelvin: 5100, tint: 4)
        XCTAssertEqual(Look.single("Exposure", 1.5, asShot: asShot)?.ev, 1.5)
        XCTAssertEqual(Look.single("Temperature", 8000, asShot: asShot)?.wb, Look.WhiteBalance(kelvin: 8000, tint: 4))
        XCTAssertEqual(Look.single("Tint", -20, asShot: asShot)?.wb, Look.WhiteBalance(kelvin: 5100, tint: -20))
        XCTAssertEqual(Look.single("Sharpness", 80, asShot: asShot)?.sharpen, 80)
        XCTAssertNil(Look.single("Texture", 10, asShot: asShot))
    }
}
