import CoreImage
import ImageIO
import XCTest
@testable import Lumina

/// The real graph (Core Image, the Metal kernels) on synthetic images: every slider monotonic and
/// grey-preserving on a ramp, flat patches equal to `LookMath`'s scalar chain (so the Metal port
/// of every stage matches the reference maths), crop, the encoders, and the preview renderer's
/// cache and sequence numbers.
final class LookPipelineTests: XCTestCase {
    var rules: LookRules!
    var pipe: LookPipeline!
    let asShot = Look.WhiteBalance(kelvin: 5500, tint: 0)

    override func setUpWithError() throws {
        rules = try LookTestRules.load()
        pipe = try LookPipeline(rules: rules)
    }

    private func luma(_ c: LookMath.RGB) -> Double { LookMath.luma(c, rules) }

    /// The twelve sliders (the sweep's names) at a spread of positions.
    private var sweep: [(String, Double)] {
        var out: [(String, Double)] = []
        for s in ["Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Vibrance", "Saturation", "Clarity"] {
            for v in [-100.0, -40, 40, 100] { out.append((s, v)) }
        }
        for v in [-3.0, -0.5, 0.5, 3] { out.append(("Exposure", v)) }
        for v in [2500.0, 4200, 7500, 20000] { out.append(("Temperature", v)) }
        for v in [-120.0, 60] { out.append(("Tint", v)) }
        for v in [40.0, 150] { out.append(("Sharpness", v)) }
        return out
    }

    func testKernelsCompile() throws {
        let k = try LookKernels.shared()
        XCTAssertEqual(k.byName.count, 8, "\(k.byName.keys.sorted())")
    }

    func testNeutralLookIsTheDevelopedImage() {
        let dev = pipe.ramp(steps: 64, columnWidth: 4, height: 8, lo: 0, hi: 1.2)
        let inRow = pipe.row(dev.image, y: 4, width: 256), outRow = pipe.row(pipe.apply(Look(), to: dev), y: 4, width: 256)
        for (a, b) in zip(inRow, outRow) {
            XCTAssertEqual(a.r, b.r, accuracy: 2e-3); XCTAssertEqual(a.g, b.g, accuracy: 2e-3); XCTAssertEqual(a.b, b.b, accuracy: 2e-3)
        }
        XCTAssertEqual(outRow[0].r, 0, accuracy: 1e-3)
        XCTAssertEqual(outRow[255].r, 1.2, accuracy: 3e-3, "the working space keeps values above white")
    }

    func testEverySliderIsMonotonicAndGreyOnARamp() {
        // A smooth ramp (one step per pixel) so the blur-based stages see a continuous base;
        // the outer 3σ of the widest blur (tone: 0.03 × 512 px) is left out at both ends.
        let width = 512, margin = 48
        let dev = pipe.ramp(steps: width, columnWidth: 1, height: 32, lo: 0, hi: 1.2)
        for (slider, value) in sweep {
            let look = Look.single(slider, value, asShot: asShot)!
            let row = pipe.row(pipe.apply(look, to: dev), y: 16, width: width)
            var last = -1.0
            for x in margin..<(width - margin) {
                let y = luma(row[x])
                XCTAssertTrue(y.isFinite && y >= -1e-4, "\(slider) \(value) x=\(x): \(y)")
                XCTAssertGreaterThanOrEqual(y, last - 2e-3, "\(slider) \(value) not monotonic at x=\(x): \(y) after \(last)")
                last = max(last, y)
                if slider != "Temperature" && slider != "Tint" {
                    XCTAssertTrue(row[x].isNeutral(tolerance: 4e-3), "\(slider) \(value) x=\(x) tinted a grey: \(row[x])")
                }
            }
            XCTAssertGreaterThan(last, 0.05, "\(slider) \(value) flattened the ramp")
        }
    }

    func testFlatPatchesMatchLookMath() {
        let colours: [LookMath.RGB] = [.gray(0.02), .gray(0.18), .gray(0.5), .gray(0.9), .gray(1.1),
                                       LookMath.RGB(r: 0.5, g: 0.2, b: 0.2), LookMath.RGB(r: 0.2, g: 0.5, b: 0.2), LookMath.RGB(r: 0.15, g: 0.2, b: 0.6),
                                       LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0.7, g: 0.6, b: 0.1)]
        var looks: [Look] = []
        for (slider, value) in sweep { looks.append(Look.single(slider, value, asShot: asShot)!) }
        for s in ["ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0",
                  "ev:-1.20 con:-30 hl:+50 sh:-40 wh:+30 bl:+20 vib:-40 sat:+25",
                  "ev:+0.30 wb:3200/-20 con:+40 bw:1", "sat:-100", "wh:-60 bl:-60 con:+80"] {
            looks.append(try! Look.parse(s))
        }
        var worst = 0.0
        for c in colours {
            let dev = pipe.flat(c, size: 64)
            for look in looks {
                let got = pipe.pixel(pipe.apply(look, to: dev), x: 32, y: 32)
                let want = LookMath.flat(c, look: look, asShot: asShot, rules: rules)
                for (g, w) in [(got.r, want.r), (got.g, want.g), (got.b, want.b)] {
                    let tol = max(0.006, 0.02 * abs(w))
                    worst = max(worst, abs(g - w) / tol)
                    XCTAssertEqual(g, w, accuracy: tol, "\(look.format()) on \(c): graph \(got) vs maths \(want)")
                }
            }
        }
        print("LookPipelineTests: graph vs LookMath worst error = \(String(format: "%.2f", worst)) × tolerance")
    }

    func testVignetteDarkensTheCornersOnly() {
        let dev = pipe.flat(.gray(0.5), size: 256)
        var dark = Look(); dark.vignette = -100
        var light = Look(); light.vignette = 60
        let d = pipe.apply(dark, to: dev), l = pipe.apply(light, to: dev)
        XCTAssertEqual(pipe.pixel(d, x: 128, y: 128).g, 0.5, accuracy: 3e-3)
        XCTAssertLessThan(pipe.pixel(d, x: 2, y: 2).g, 0.4)
        XCTAssertLessThan(pipe.pixel(d, x: 2, y: 2).g, pipe.pixel(d, x: 40, y: 40).g)
        XCTAssertGreaterThan(pipe.pixel(l, x: 2, y: 253).g, 0.5)
        XCTAssertTrue(pipe.pixel(d, x: 2, y: 2).isNeutral(tolerance: 4e-3))
        let expected = 0.5 * LookMath.vignetteGain(r: hypot(125.5, 125.5) / hypot(128, 128), vignette: -100, rules)
        XCTAssertEqual(pipe.pixel(d, x: 2, y: 2).g, expected, accuracy: 0.01)
    }

    func testCropAndStraighten() throws {
        let dev = pipe.ramp(steps: 256, columnWidth: 1, height: 128)
        var look = Look(); look.crop = Look.Crop(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
        let out = pipe.apply(look, to: dev)
        XCTAssertEqual(out.extent, CGRect(x: 0, y: 0, width: 128, height: 64))
        // The crop starts a quarter of the way in: its first column is the ramp at 25 %.
        XCTAssertEqual(pipe.pixel(out, x: 0, y: 32).r, 64.0 / 255, accuracy: 0.02)
        look.crop?.rotate = 10
        XCTAssertEqual(pipe.apply(look, to: dev).extent.size, CGSize(width: 128, height: 64))
    }

    func testEncodersWriteSixteenBitTIFFAndJPEG() throws {
        let dev = pipe.ramp(steps: 64, columnWidth: 2, height: 16)
        let out = pipe.apply(try Look.parse("ev:+0.5 con:+20"), to: dev)
        let tiff = try pipe.tiff16(out, space: .prophoto)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(tiff as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyDepth] as? Int, 16)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 128)
        XCTAssertNotNil(props[kCGImagePropertyProfileName], "the TIFF carries its ICC profile")
        print("LookPipelineTests: TIFF profile = \(props[kCGImagePropertyProfileName] ?? "none")")
        let jpg = try pipe.jpeg(out, quality: 0.9)
        XCTAssertNotNil(CGImageSourceCreateWithData(jpg as CFData, nil))
        XCTAssertGreaterThan(jpg.count, 500)
    }

    func testRendererCachesDevelopsAndDropsStaleRequests() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-renderer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("ramp.png")
        try pipe.png(pipe.ramp(steps: 128, columnWidth: 2, height: 128).image).write(to: file)

        // Cap: the half-float rasters are 256 KB (256 px), 64 KB (128 px) and 144 KB (192 px); the
        // three don't fit in 400 KB, so the oldest (256 px) goes when the third is developed.
        let r = try LookRenderer(rules: rules, byteCap: 400 << 10)
        r.requested(rel: "shoot/ramp.png", seq: 1)
        r.requested(rel: "shoot/ramp.png", seq: 2)
        XCTAssertThrowsError(try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "ev:+1", px: 256, seq: 1)) { XCTAssertTrue($0 is LookRenderer.Stale) }
        XCTAssertFalse(r.isStale(rel: "shoot/ramp.png", seq: 2))
        let a = try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "ev:+1", px: 256, seq: 2)
        XCTAssertGreaterThan(a.count, 100)
        _ = try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "con:+30", px: 256, seq: 3)
        XCTAssertEqual(r.stats.developed, 1); XCTAssertEqual(r.stats.cacheHits, 1); XCTAssertEqual(r.stats.stale, 1)
        _ = try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "", px: 128, seq: 4)
        _ = try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "", px: 192, seq: 5)
        XCTAssertEqual(r.stats.developed, 3)
        XCTAssertGreaterThanOrEqual(r.stats.evicted, 1, "the byte cap evicts the oldest size: \(r.stats)")
        XCTAssertLessThanOrEqual(r.stats.cacheBytes, 400 << 10)
        r.forget(rel: "shoot/ramp.png")
        XCTAssertEqual(r.stats.cacheBytes, 0)
        XCTAssertThrowsError(try r.renderJPEG(url: file, rel: "shoot/ramp.png", look: "nope:1", px: 128, seq: 6))
        XCTAssertThrowsError(try r.renderJPEG(url: dir.appendingPathComponent("missing.png"), rel: "shoot/missing.png", look: "", px: 128, seq: 1))
    }
}
