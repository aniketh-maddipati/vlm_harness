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
        XCTAssertEqual(Set(k.byName.keys).intersection(LookKernels.stageNames).count, LookKernels.stageNames.count, "\(k.byName.keys.sorted())")
        XCTAssertEqual(try k.kernel("lookEcho44").name, "lookEcho44", "test kernels compile on demand")
        XCTAssertThrowsError(try k.kernel("lookNope"))
    }

    /// Every argument slot receives what `apply` passed, in each layout the stages use. Values are
    /// small integers with distinct magnitudes per slot so a mix-up is readable in the output.
    func testKernelArgumentsArriveInOrder() throws {
        let dev = pipe.flat(.gray(0.5), size: 8)
        let extent = dev.image.extent
        func echo(_ name: String, _ args: [Any]) -> [Double] {
            let out = pipe.kernels.apply(name, extent: extent, [dev.image] + args)!
            var px = [Float](repeating: 0, count: 4)
            pipe.context.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 4, y: 4, width: 1, height: 1), format: .RGBAf, colorSpace: pipe.workingSpace)
            return px.map { Double($0) }
        }
        let a = CIVector(x: 1, y: 2, z: 3, w: 4), b = CIVector(x: 5, y: 6, z: 7, w: 8), c2 = CIVector(x: 9, y: 10)
        let e442 = echo("lookEcho442", [a, b, c2])
        print("LookPipelineTests: echo442 (s, f4, f4, f2) = \(e442)")
        XCTAssertEqual(e442[0], 0.5 + 1000 * 1 + 1000000 * 5, accuracy: 1)
        XCTAssertEqual(e442[1], 2 + 1000 * 6 + 1000000 * 9, accuracy: 1)
        XCTAssertEqual(e442[2], 3 + 1000 * 7 + 1000000 * 10, accuracy: 1)
        XCTAssertEqual(e442[3], 4 + 1000 * 8, accuracy: 1)
        let e44 = echo("lookEcho44", [a, b])
        print("LookPipelineTests: echo44 (s, f4, f4) = \(e44)")
        XCTAssertEqual(e44[0], 0.5 + 1000 * 1 + 1000000 * 5, accuracy: 1)
        XCTAssertEqual(e44[1], 2 + 1000 * 6, accuracy: 1)
        XCTAssertEqual(e44[2], 3 + 1000 * 7, accuracy: 1)
        XCTAssertEqual(e44[3], 4 + 1000 * 8, accuracy: 1)
        let e424 = echo("lookEcho424", [a, c2, b])
        print("LookPipelineTests: echo424 (s, f4, f2, f4) = \(e424)")
        XCTAssertEqual(e424[0], 0.5 + 1000 * 1 + 1000000 * 5, accuracy: 1)
        XCTAssertEqual(e424[1], 2 + 1000 * 9 + 1000000 * 6, accuracy: 1)
        XCTAssertEqual(e424[2], 3 + 1000 * 10 + 1000000 * 7, accuracy: 1)
        XCTAssertEqual(e424[3], 4 + 1000 * 8, accuracy: 1)
        // The pre kernel on a flat grey with unit gains and no whites/blacks must be the identity.
        let same = pipe.kernels.apply("lookPre", extent: extent, [dev.image, CIVector(x: 1, y: 1, z: 1, w: 1), CIVector(x: 0, y: 0, z: 0, w: 0), CIVector(x: 1 / 2.2, y: 2.2)])!
        let p = pipe.pixel(same, x: 4, y: 4)
        print("LookPipelineTests: lookPre identity on 0.5 = \(p)")
        XCTAssertEqual(p.g, 0.5, accuracy: 0.003)
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

    /// The graph holds a stage exactly when `Look.runs` says so: the warm-up plan (`LookWarmPlan`)
    /// names the programs Core Image will compile by it.
    func testTheGraphHoldsAStageExactlyWhenTheLookRunsIt() throws {
        let dev = pipe.ramp(steps: 16, columnWidth: 4, height: 8)
        XCTAssertTrue(pipe.apply(Look(), to: dev) === dev.image, "no stage: the developed image itself")
        for stage in rules.lookStages {
            let on = Look().toggling(stage)
            XCTAssertEqual(rules.lookStages.filter(on.runs), [stage])
            XCTAssertFalse(pipe.apply(on, to: dev) === dev.image, "\(stage) switched on left the graph empty")
            XCTAssertTrue(pipe.apply(on.toggling(stage), to: dev) === dev.image, "\(stage) switched off again")
        }
        // Sliders written at their reset value add nothing.
        XCTAssertTrue(pipe.apply(try Look.parse("ev:0 con:0 sh:0 hl:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:0 nr:20"), to: dev) === dev.image)
        // A switched-on stage changes the picture (the warm-up's value is not a no-op).
        // (A tinted shadow tone: vibrance leaves a grey alone, shadows leave the highlights alone;
        // clarity and sharpen need an edge and the vignette a corner.)
        let tinted = pipe.ramp(steps: 16, columnWidth: 4, height: 8, tint: LookMath.RGB(r: 1, g: 0.8, b: 0.6))
        let before = pipe.pixel(tinted.image, x: 10, y: 4)
        for stage in rules.lookStages where stage != "clarity" && stage != "sharpen" && stage != "vignette" {
            let out = pipe.pixel(pipe.apply(Look().toggling(stage), to: tinted), x: 10, y: 4)
            XCTAssertGreaterThan(abs(out.r - before.r) + abs(out.g - before.g) + abs(out.b - before.b), 1e-4, stage)
        }
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

    /// rawDevelop's base match on the GPU equals `LookMath.baseMatch` (and is skipped at zero).
    func testBaseMatchKernelEqualsLookMath() throws {
        var r = rules!
        XCTAssertNotNil(r.stages["rawDevelop"])
        for (k, v) in ["baseLift": 0.033, "baseS": 0.30, "baseRG": 0.135, "baseRB": -0.003, "baseGR": -0.001, "baseGB": 0.135, "baseBR": 0.0025, "baseBG": 0.012,
                       "baseHiDesat": 0.6, "baseHiFrom": 0.9, "baseLoDesat": 0.5, "baseLoBelow": 0.2] {
            r.stages["rawDevelop"]?.coefficients[k] = v
        }
        let m = LookMath.BaseMatch(r)
        for c in [LookMath.RGB.gray(0.02), .gray(0.18), .gray(0.9), .gray(1.2), LookMath.RGB(r: 0.5, g: 0.2, b: 0.2),
                  LookMath.RGB(r: 0.15, g: 0.2, b: 0.6), LookMath.RGB(r: 0.7, g: 0.6, b: 0.1),
                  LookMath.RGB(r: 0.95, g: 0.85, b: 0.8), LookMath.RGB(r: 0.004, g: 0.002, b: 0.006)] {
            let got = pipe.pixel(try LookPipeline.baseMatched(pipe.flat(c, size: 16).image, rules: r), x: 8, y: 8)
            let want = LookMath.baseMatch(c, m, r)
            for (g, w) in [(got.r, want.r), (got.g, want.g), (got.b, want.b)] { XCTAssertEqual(g, w, accuracy: max(0.003, 0.01 * abs(w)), "\(c): \(got) vs \(want)") }
        }
        var off = r
        for k in ["baseLift", "baseS", "baseRG", "baseRB", "baseGR", "baseGB", "baseBR", "baseBG", "baseHiDesat", "baseLoDesat"] { off.stages["rawDevelop"]?.coefficients[k] = 0 }
        let img = pipe.flat(.gray(0.4), size: 16).image
        XCTAssertTrue(try LookPipeline.baseMatched(img, rules: off) === img, "zero coefficients: the image itself, no pass")
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

    /// Float pixels of a whole (small) image, for exact comparisons.
    private func floats(_ img: CIImage) -> [Float] {
        let w = Int(img.extent.width), h = Int(img.extent.height)
        var px = [Float](repeating: 0, count: 4 * w * h)
        pipe.context.render(img, toBitmap: &px, rowBytes: 16 * w, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: pipe.workingSpace)
        return px
    }

    /// With the four shape sliders at reset the graph holds the kernel it always held, with the
    /// arguments it always got: the render is bit for bit the one written out here by hand.
    func testVignetteAtTheShapeResetIsBitForBitTheKernelItWas() throws {
        let dev = pipe.ramp(steps: 48, columnWidth: 2, height: 64, lo: 0.02, hi: 1.1, tint: LookMath.RGB(r: 1, g: 0.8, b: 0.6))
        let extent = dev.image.extent
        for text in ["vig:-100", "vig:-37", "vig:+60", "vig:-37 vigs:50,0,50,0"] {
            let look = try Look.parse(text)
            let m = rules.k("vignette", "midpoint", 0.5), f = rules.k("vignette", "feather", 0.5), halfDiag = hypot(extent.width, extent.height) / 2
            let k = CIVector(x: look.vignette * rules.k("vignette", "stopsPerUnit", 0.02), y: m - f / 2, z: m + f / 2, w: 1 / halfDiag)
            let before = try XCTUnwrap(pipe.kernels.apply("lookVignette", extent: extent, [dev.image, k, CIVector(x: extent.midX, y: extent.midY)]))
            XCTAssertEqual(floats(pipe.apply(look, to: dev)), floats(before), text)
        }
        XCTAssertTrue(LookKernels.source.contains("float4 lookVignette(coreimage::sample_t s, float4 k, float2 c, coreimage::destination dest) {\n    float r = length(dest.coord() - c) * k.w;\n    float g = exp2(k.x * lk_smooth(k.y, k.z, r));\n    return float4(s.rgb * g, s.a);\n}"),
                      "the reset kernel's source is the one that shipped")
        XCTAssertFalse(LookKernels.source.contains("lookVignetteShape"), "the new kernels live in a source of their own")
    }

    /// The shaped vignette on the GPU equals `LookMath.vignetteShaped`, pixel by pixel across a
    /// frame that is not square, and meets the reset kernel next to the reset.
    func testVignetteShapeKernelEqualsLookMath() throws {
        let w = 96, h = 64
        for colour in [LookMath.RGB.gray(0.5), .gray(0.95), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25)] {
            let dev = LookPipeline.Developed(image: pipe.flat(colour, size: w).image.cropped(to: CGRect(x: 0, y: 0, width: w, height: h)), asShot: asShot, anchor: .reference)
            for text in ["vig:-80 vigs:30,0,50,0", "vig:-80 vigs:50,-50,50,0", "vig:-100 vigs:60,-100,30,0", "vig:-70 vigs:50,0,50,80", "vig:+60 vigs:40,-25,90,100", "vig:-100 vigs:50,0,0,0", "vig:-90 vigs:20,+60,100,40"] {
                let look = try Look.parse(text)
                XCTAssertFalse(look.vignetteShape.isDefault)
                let out = pipe.apply(look, to: dev)
                let form = LookMath.VignetteForm(shape: look.vignetteShape, vignette: look.vignette, aspect: Double(w) / Double(h), rules)
                for (x, y) in [(48, 32), (0, 0), (95, 63), (2, 61), (90, 30), (47, 3), (20, 20), (70, 50)] {
                    let u = (Double(x) + 0.5 - Double(w) / 2) / (Double(w) / 2), v = (Double(y) + 0.5 - Double(h) / 2) / (Double(h) / 2)
                    let d = form.distance(u: u, v: v)
                    // A hard edge (feather 0) is a step: skip the pixels the edge passes through.
                    if look.vignetteShape.feather == 0, abs(d - form.edge0) < 0.03 { continue }
                    let got = pipe.pixel(out, x: x, y: y), want = LookMath.flat(colour, look: look, asShot: asShot, rules: rules, vignetteR: d, aspect: Double(w) / Double(h))
                    for (g, e) in [(got.r, want.r), (got.g, want.g), (got.b, want.b)] { XCTAssertEqual(g, e, accuracy: max(0.004, 0.01 * abs(e)), "\(text) on \(colour) at \(x),\(y) d=\(d): \(got) vs \(want)") }
                    if colour.isNeutral { XCTAssertTrue(got.isNeutral(tolerance: 4e-3), "\(text) tinted a grey at \(x),\(y): \(got)") }
                }
            }
            // A hair off the reset, the shaped kernel draws what the reset kernel draws.
            let near = pipe.apply(try Look.parse("vig:-80 vigs:50.001,0,50,0"), to: dev), reset = pipe.apply(try Look.parse("vig:-80"), to: dev)
            for (x, y) in [(48, 32), (0, 0), (95, 63), (90, 30), (47, 3), (20, 20)] {
                XCTAssertEqual(pipe.pixel(near, x: x, y: y).g, pipe.pixel(reset, x: x, y: y).g, accuracy: 2e-3, "at \(x),\(y)")
            }
        }
        // Grey ramp through the shaped stage, at the frame's edge: monotonic and grey.
        let ramp = pipe.ramp(steps: 256, columnWidth: 1, height: 8, lo: 0, hi: 1.2)
        for text in ["vig:-100 vigs:0,-50,100,100", "vig:-100 vigs:0,0,100,60", "vig:+80 vigs:0,-100,100,0"] {
            let row = pipe.row(pipe.apply(try Look.parse(text), to: ramp), y: 4, width: 256)
            // Along the row the distance changes too, so compare each pixel with the maths rather than its neighbour…
            let look = try Look.parse(text), form = LookMath.VignetteForm(shape: look.vignetteShape, vignette: look.vignette, aspect: 256.0 / 8, rules)
            for x in stride(from: 0, to: 256, by: 5) {
                let d = form.distance(u: (Double(x) + 0.5 - 128) / 128, v: (4.5 - 4) / 4), v = 1.2 * Double(x) / 255
                let want = LookMath.flat(.gray(v), look: look, asShot: asShot, rules: rules, vignetteR: d, aspect: 256.0 / 8)
                XCTAssertEqual(row[x].g, want.g, accuracy: max(0.004, 0.01 * want.g), "\(text) x=\(x)")
                XCTAssertTrue(row[x].isNeutral(tolerance: 4e-3), "\(text) x=\(x) tinted a grey: \(row[x])")
            }
        }
        // …and at one place (a 1 px column at the frame's right edge), brighter in is brighter out.
        for text in ["vig:-100 vigs:0,-50,100,100", "vig:-100 vigs:50,0,50,60"] {
            var last = -1.0
            for i in 0...24 {
                let dev = LookPipeline.Developed(image: pipe.flat(.gray(Double(i) / 20), size: 64).image, asShot: asShot, anchor: .reference)
                let y = pipe.pixel(pipe.apply(try Look.parse(text), to: dev), x: 63, y: 32).g
                XCTAssertGreaterThanOrEqual(y, last - 2e-3, "\(text) grey \(Double(i) / 20)"); last = max(last, y)
            }
        }
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

    /// `rot`: the picture turned clockwise by quarter turns, after the crop, in `apply` (previews,
    /// exports), in the canvas's bases (their key and their size) and in the loupe's region maths.
    func testQuarterTurnIsGeometryAppliedAfterTheCrop() throws {
        // 64 × 32: red grows to the right, green toward the top.
        let w = 64, h = 32
        var data = [Float](repeating: 1, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let i = 4 * (y * w + x); data[i] = Float(x) / Float(w - 1); data[i + 1] = 1 - Float(y) / Float(h - 1); data[i + 2] = 0.25 } }       // bitmap row 0 is the top
        let img = CIImage(bitmapData: data.withUnsafeBufferPointer { Data(buffer: $0) }, bytesPerRow: w * 16, size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: pipe.workingSpace)
        let dev = LookPipeline.Developed(image: img, asShot: asShot, anchor: .reference)
        func corners(_ o: CIImage) -> (tl: LookMath.RGB, tr: LookMath.RGB, bl: LookMath.RGB, br: LookMath.RGB) {
            let ew = Int(o.extent.width), eh = Int(o.extent.height)
            return (pipe.pixel(o, x: 0, y: eh - 1), pipe.pixel(o, x: ew - 1, y: eh - 1), pipe.pixel(o, x: 0, y: 0), pipe.pixel(o, x: ew - 1, y: 0))
        }
        // (red, green) of the frame's corners: top left (0, 1), top right (1, 1), bottom left (0, 0), bottom right (1, 0).
        func isAt(_ c: LookMath.RGB, _ r: Double, _ g: Double, _ what: String) {
            XCTAssertEqual(c.r, r, accuracy: 0.01, what); XCTAssertEqual(c.g, g, accuracy: 0.01, what); XCTAssertEqual(c.b, 0.25, accuracy: 0.01, what)
        }
        XCTAssertTrue(pipe.apply(Look(), to: dev) === dev.image, "no turn: the image itself")
        var look = Look(); look.rot = 90
        var o = pipe.apply(look, to: dev)
        XCTAssertEqual(o.extent, CGRect(x: 0, y: 0, width: 32, height: 64))
        var c = corners(o)          // clockwise: the top left corner goes to the top right, the bottom left to the top left
        isAt(c.tr, 0, 1, "90 top right"); isAt(c.br, 1, 1, "90 bottom right"); isAt(c.bl, 1, 0, "90 bottom left"); isAt(c.tl, 0, 0, "90 top left")
        look.rot = 180; o = pipe.apply(look, to: dev); c = corners(o)
        XCTAssertEqual(o.extent, CGRect(x: 0, y: 0, width: 64, height: 32))
        isAt(c.br, 0, 1, "180 bottom right"); isAt(c.tl, 1, 0, "180 top left")
        look.rot = 270; o = pipe.apply(look, to: dev); c = corners(o)
        XCTAssertEqual(o.extent, CGRect(x: 0, y: 0, width: 32, height: 64))
        isAt(c.bl, 0, 1, "270 bottom left"); isAt(c.tl, 1, 1, "270 top left"); isAt(c.tr, 1, 0, "270 top right")
        // Four quarter turns are the picture again, pixel for pixel.
        var back = dev.image
        for _ in 0..<4 { back = LookPipeline.turned(back, rot: 90) }
        XCTAssertEqual(back.extent, dev.image.extent)
        for (x, y) in [(0, 0), (17, 5), (63, 31)] { XCTAssertEqual(pipe.pixel(back, x: x, y: y), pipe.pixel(dev.image, x: x, y: y)) }
        // The crop is taken in the frame as shot (its left half), then turned: red stays below 0.5.
        look = Look(); look.crop = Look.Crop(x: 0, y: 0, w: 0.5, h: 1); look.rot = 90
        o = pipe.apply(look, to: dev)
        XCTAssertEqual(o.extent, CGRect(x: 0, y: 0, width: 32, height: 32))
        c = corners(o)
        isAt(c.tr, 0, 1, "crop then turn, top right"); XCTAssertEqual(c.br.r, 31.0 / 63, accuracy: 0.02); XCTAssertEqual(c.br.g, 1, accuracy: 0.01)
        // crop: false leaves the geometry to the caller (the canvas's bases), turn included.
        XCTAssertTrue(pipe.apply(look, to: dev, crop: false) === dev.image)
        XCTAssertEqual(pipe.geometry(dev.image, look.crop, rot: 90).extent, o.extent)
        // The stages run on the turned picture: the same pixels as turning the finished render.
        var graded = try Look.parse("ev:+0.50 con:+20 sat:+15"); let flatRender = pipe.apply(graded, to: dev)
        graded.rot = 90
        let turnedRender = pipe.apply(graded, to: dev), want = LookPipeline.turned(flatRender, rot: 90)
        for (x, y) in [(0, 0), (9, 40), (31, 63)] {
            let a = pipe.pixel(turnedRender, x: x, y: y), b = pipe.pixel(want, x: x, y: y)
            XCTAssertEqual(a.r, b.r, accuracy: 1e-4); XCTAssertEqual(a.g, b.g, accuracy: 1e-4); XCTAssertEqual(a.b, b.b, accuracy: 1e-4)
        }

        // The bases: the turn is part of the key and of the size.
        let canvas = CGSize(width: 200, height: 200)
        var turned = Look(); turned.rot = 90
        let plain = LookBases.Key(rel: "s/p.png", decoder: nil, look: Look(), canvas: canvas), quarter = LookBases.Key(rel: "s/p.png", decoder: nil, look: turned, canvas: canvas)
        XCTAssertNotEqual(plain, quarter)
        XCTAssertEqual(plain.description, "s/p.png|d0||r0.0|200x200|nr-1", "a key without a turn reads as before")
        XCTAssertTrue(quarter.description.contains("|q90|"))
        XCTAssertEqual(LookBases.croppedSize(CGSize(width: 6000, height: 4000), nil, rot: 90), CGSize(width: 4000, height: 6000))
        XCTAssertEqual(LookBases.croppedSize(CGSize(width: 6000, height: 4000), Look.Crop(x: 0, y: 0, w: 0.5, h: 1), rot: 270), CGSize(width: 4000, height: 3000))
        XCTAssertEqual(LookBases.croppedSize(CGSize(width: 6000, height: 4000), Look.Crop(x: 0, y: 0, w: 0.5, h: 1), rot: 180), CGSize(width: 3000, height: 4000))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-rot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.png")
        try pipe.png(img).write(to: url)
        let bases = LookBases(pipeline: pipe, byteCap: 64 << 20, maxPhotos: 3)
        let e0 = try bases.build(plain, url: url, look: Look(), preview: nil), e90 = try bases.build(quarter, url: url, look: turned, preview: nil)
        XCTAssertGreaterThan(e0.baseSize.width, e0.baseSize.height); XCTAssertGreaterThan(e90.baseSize.height, e90.baseSize.width, "the turn is baked into the base")
        XCTAssertEqual(e90.photoSize, CGSize(width: 32, height: 64))
        // Upright after the turn: the frame's left edge (red 0) is the base's top row.
        let bw = Int(e90.baseSize.width), bh = Int(e90.baseSize.height)
        XCTAssertLessThan(pipe.pixel(e90.base, x: bw / 2, y: bh - 1).r, 0.1); XCTAssertGreaterThan(pipe.pixel(e90.base, x: bw / 2, y: 0).r, 0.9)

        // The loupe's region: a point of the frame lands where the whole frame's transform puts it.
        let t = LookPipeline.turnTransform(size: CGSize(width: 6000, height: 4000), rot: 90)
        XCTAssertEqual(CGRect(x: 0, y: 3000, width: 1000, height: 1000).applying(t), CGRect(x: 3000, y: 5000, width: 1000, height: 1000), "the frame's top left tile is the turned picture's top right")
        XCTAssertTrue(LookPipeline.turnTransform(size: CGSize(width: 6000, height: 4000), rot: 0).isIdentity)
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

    /// A file's embedded JPEG (its byte range), upright and scaled: the canvas's stand-in when
    /// the RAW can't be developed.
    func testPreviewFallbackDevelopsTheEmbeddedJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpeg = try pipe.jpeg(pipe.ramp(steps: 64, columnWidth: 4, height: 128).image)      // 256 × 128
        let prefix = Data(repeating: 0x42, count: 4096)
        let file = dir.appendingPathComponent("fake.ARW")
        try (prefix + jpeg + Data(repeating: 0, count: 100)).write(to: file)
        let dev = try LookPipeline.developPreview(url: file, offset: prefix.count, length: jpeg.count, orientation: 1, longEdge: 128)
        XCTAssertEqual(dev.extent, CGRect(x: 0, y: 0, width: 128, height: 64))
        let turned = try LookPipeline.developPreview(url: file, offset: prefix.count, length: jpeg.count, orientation: 6, longEdge: nil)
        XCTAssertEqual(turned.extent.size, CGSize(width: 128, height: 256), "orientation 6 turns the frame upright")
        XCTAssertThrowsError(try LookPipeline.developPreview(url: file, offset: 0, length: 100, orientation: 1, longEdge: nil))
        // CIRAWFilter may or may not accept a fake ARW (macOS 15 opens it as an image); either way
        // the develop must throw or yield a real image, never an empty one.
        if let dev = try? LookPipeline.develop(url: file, longEdge: 128, rules: rules) {
            XCTAssertFalse(dev.extent.isEmpty); XCTAssertFalse(dev.extent.isInfinite)
            print("LookPipelineTests: CIRAWFilter accepted the fake ARW: \(dev.extent.size), decoders \(LookPipeline.supportedDecoderVersions(url: file))")
        }
    }

    /// The canvas's bases from a PNG: `base` fits the canvas plus its 15 % margin, `small` is a
    /// quarter on each edge, both the right way up (the texture read-back flip is measured, not
    /// assumed), cached by key, pinned, and at most `maxPhotos` photos resident.
    func testBasesBuildUprightTexturesAndCacheByKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-bases-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 300 × 200, a vertical gradient: bright at the top, dark at the bottom, plus a horizontal ramp in red.
        let w = 300, h = 200
        var data = [Float](repeating: 1, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let i = 4 * (y * w + x); data[i] = Float(x) / Float(w); data[i + 1] = 1 - Float(y) / Float(h); data[i + 2] = 0.5; data[i + 3] = 1 } }
        let bytes = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let img = CIImage(bitmapData: bytes, bytesPerRow: w * 16, size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: pipe.workingSpace)
        let png = try pipe.png(img)
        var urls: [URL] = []
        for i in 0..<4 { let u = dir.appendingPathComponent("p\(i).png"); try png.write(to: u); urls.append(u) }

        let bases = LookBases(pipeline: pipe, byteCap: 64 << 20, maxPhotos: 3)
        let canvas = CGSize(width: 200, height: 200)
        let key = LookBases.Key(rel: "s/p0.png", decoder: nil, look: Look(), canvas: canvas)
        let e = try bases.build(key, url: urls[0], look: Look(), preview: nil)
        print("LookPipelineTests: bases on GPU = \(e.onGPU), flips on readback = \(bases.stats.flipsOnReadback), \(e.baseSize) / \(e.smallSize), \(e.developMs) ms")
        // Fits 230 × 230 (the canvas plus 15 %): 230 × 153.
        XCTAssertEqual(e.baseSize.width, 230, accuracy: 1); XCTAssertEqual(e.baseSize.height, 153, accuracy: 1.5)
        XCTAssertEqual(e.smallSize.width, (e.baseSize.width / 4).rounded(.down), accuracy: 1)
        XCTAssertEqual(e.source, "image", "a PNG is an image file, not a RAW")
        let bw = Int(e.baseSize.width), bh = Int(e.baseSize.height)
        // Upright: the top row (Core Image y = height − 1) is bright green, the bottom dark; red grows to the right.
        let top = pipe.pixel(e.base, x: bw / 2, y: bh - 2), bottom = pipe.pixel(e.base, x: bw / 2, y: 1)
        XCTAssertGreaterThan(top.g, 0.8, "top row bright: \(top)"); XCTAssertLessThan(bottom.g, 0.2, "bottom row dark: \(bottom)")
        XCTAssertLessThan(pipe.pixel(e.base, x: 2, y: bh / 2).r, pipe.pixel(e.base, x: bw - 3, y: bh / 2).r)
        let sw = Int(e.smallSize.width), sh = Int(e.smallSize.height)
        XCTAssertGreaterThan(pipe.pixel(e.small, x: sw / 2, y: sh - 1).g, 0.7); XCTAssertLessThan(pipe.pixel(e.small, x: sw / 2, y: 0).g, 0.3)
        XCTAssertEqual(Double(e.bytes), Double((bw * bh + sw * sh) * 8), accuracy: Double(bh * 256), "two half-float rasters")
        // Cached by key; a different canvas size is a different key.
        XCTAssertNotNil(bases.entry(key)); XCTAssertEqual(bases.stats.hits, 1)
        XCTAssertNil(bases.entry(LookBases.Key(rel: "s/p0.png", decoder: nil, look: Look(), canvas: CGSize(width: 100, height: 100))))
        var cropped = Look(); cropped.crop = Look.Crop(x: 0.25, y: 0, w: 0.5, h: 1)
        let c = try bases.build(LookBases.Key(rel: "s/p0.png", decoder: nil, look: cropped, canvas: canvas), url: urls[0], look: cropped, preview: nil)
        XCTAssertEqual(c.baseSize.width / c.baseSize.height, 0.75, accuracy: 0.02, "the crop is baked into the base")
        // At most 3 photos resident; the pinned one stays.
        bases.pin(key)
        for i in 1..<4 { _ = try bases.build(LookBases.Key(rel: "s/p\(i).png", decoder: nil, look: Look(), canvas: canvas), url: urls[i], look: Look(), preview: nil) }
        let st = bases.stats
        XCTAssertLessThanOrEqual(st.residentPhotos, 3, "\(st)")
        XCTAssertNotNil(bases.entry(key), "the pinned photo is never evicted")
        XCTAssertGreaterThanOrEqual(st.evicted, 1)
        bases.dropPrefetched()
        XCTAssertEqual(bases.stats.residentPhotos, 1)
        XCTAssertNotNil(bases.entry(key))
        XCTAssertThrowsError(try bases.build(LookBases.Key(rel: "s/missing.png", decoder: nil, look: Look(), canvas: canvas), url: dir.appendingPathComponent("missing.png"), look: Look(), preview: nil))
    }

    /// The lens-shading gain as an image: 1 at the centre, the camera's corner gain at the corners,
    /// the same in every quadrant.
    func testShadingGainImageIsRadialAndCoversTheFrame() throws {
        let s = LookLensShading(knots: [0, 48, 416, 1024, 1808, 2656, 3552, 4496, 5456, 6432, 7424, 8400, 9376, 10336, 11264, 12160])
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let g = try XCTUnwrap(LookPipeline.shadingGain(s, amount: 1, extent: extent))
        XCTAssertEqual(g.extent, extent)
        XCTAssertEqual(pipe.pixel(g, x: 300, y: 200).g, 1, accuracy: 0.01)
        let corner = pipe.pixel(g, x: 1, y: 1).g
        XCTAssertEqual(corner, s.gain(at: 1), accuracy: 0.03)
        for (x, y) in [(598, 1), (1, 398), (598, 398)] { XCTAssertEqual(pipe.pixel(g, x: x, y: y).g, corner, accuracy: 0.01) }
        XCTAssertGreaterThan(pipe.pixel(g, x: 500, y: 200).g, pipe.pixel(g, x: 400, y: 200).g)
        XCTAssertEqual(pipe.pixel(try XCTUnwrap(LookPipeline.shadingGain(s, amount: 0, extent: extent)), x: 1, y: 1).g, 1, accuracy: 1e-4)
        XCTAssertNil(LookPipeline.shadingGain(s, amount: 1, extent: .infinite))
    }

    /// The canvas holds the neighbours' builds while someone waits on it (a drag, the loupe, the
    /// current photo not yet on screen): a paused prefetch starts nothing until released.
    func testPausedPrefetchStartsNothingUntilReleased() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-prefetch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("ramp.png")
        try pipe.png(pipe.ramp(steps: 64, columnWidth: 2, height: 64).image).write(to: file)
        let bases = LookBases(pipeline: pipe, byteCap: 64 << 20, maxPhotos: 3)
        let key = LookBases.Key(rel: "s/ramp.png", decoder: nil, look: Look(), canvas: CGSize(width: 100, height: 100))
        bases.prefetchPaused = true
        bases.prefetch([(key: key, url: file, look: Look(), preview: nil)])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(bases.stats.prefetched, 0, "held while paused")
        XCTAssertEqual(bases.stats.built, 0)
        bases.prefetchPaused = false
        let deadline = Date().addingTimeInterval(10)
        while bases.stats.prefetched == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(bases.stats.prefetched, 1, "released: the neighbour builds")
    }

    /// Region requests are numbered by the tile queue: whoever asks last supersedes everyone, so
    /// one caller's numbering (the probe's) can't leave another's (the canvas's loupe) stale forever.
    func testRegionTilesNumberRequestsAndCancelOlderOnes() throws {
        let tiles = LookRegionTiles(pipeline: pipe)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).ARW")
        let roi = LookCanvasSchedule.ROI(x: 0.4, y: 0.4, w: 0.2, h: 0.2)
        let run = { (seq: Int) -> Result<LookRegionTiles.Region, Error> in
            let done = self.expectation(description: "region \(seq)")
            var out: Result<LookRegionTiles.Region, Error>!
            tiles.region(rel: "s/x.ARW", url: missing, decoder: 8, nr: nil, roi: roi, seq: seq, first: { _ in }, done: { out = $0; done.fulfill() })
            self.wait(for: [done], timeout: 10)
            return out
        }
        let older = tiles.nextSeq(), newer = tiles.nextSeq()
        XCTAssertGreaterThan(newer, older)
        guard case .failure(let e) = run(older) else { return XCTFail("a superseded request rendered") }
        XCTAssertTrue(e is LookRegionTiles.Cancelled, "\(e)")
        // The newest request runs (and fails on the missing file, not as superseded).
        guard case .failure(let f) = run(newer) else { return XCTFail("a missing file rendered") }
        XCTAssertFalse(f is LookRegionTiles.Cancelled, "\(f)")
        tiles.cancel()
        guard case .failure(let g) = run(newer) else { return XCTFail() }
        XCTAssertTrue(g is LookRegionTiles.Cancelled, "cancel() stops requests already numbered")
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

    // MARK: outputTransform (the display mapper)

    /// The shipped rules clamp; with `mapper: sigmoid` the Metal kernel equals `LookMath.output`,
    /// keeps a grey ramp grey and monotonic, and never leaves 0…1.
    func testDisplayMapperKernelEqualsLookMath() throws {
        let ramp = pipe.ramp(steps: 64, columnWidth: 2, height: 8, lo: 0, hi: 1.2)
        XCTAssertEqual(pipe.pixel(pipe.output(ramp.image), x: 127, y: 4).g, 1, accuracy: 2e-3, "the shipped mapper is the clamp")
        XCTAssertFalse(LookKernels.stageNames.contains("lookDisplay"), "nothing new compiles with the shipped mapper")

        var r = rules!
        r.stages["outputTransform", default: LookRules.Stage()].mapper = "sigmoid"
        let mapped = try LookPipeline(rules: r)
        for c in [LookMath.RGB.gray(0), .gray(0.18), .gray(0.6), .gray(0.9), .gray(1), .gray(1.5), .gray(4), .gray(40),
                  LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 1, g: 0.5, b: 0.05), LookMath.RGB(r: 4, g: 2, b: 0.2),
                  LookMath.RGB(r: 3, g: 0.24, b: 0.09), LookMath.RGB(r: 0.8, g: 1.6, b: 4), LookMath.RGB(r: 2, g: 1.2, b: 0.84),
                  LookMath.RGB(r: 0.4, g: 8, b: 0.2), LookMath.RGB(r: 30, g: 0, b: 0)] {
            let got = mapped.pixel(mapped.output(mapped.flat(c, size: 16).image), x: 8, y: 8)
            let want = LookMath.output(c, r)
            for (g, w) in [(got.r, want.r), (got.g, want.g), (got.b, want.b)] { XCTAssertEqual(g, w, accuracy: max(0.004, 0.01 * abs(w)), "\(c): graph \(got) vs maths \(want)") }
        }
        let wide = mapped.ramp(steps: 256, columnWidth: 1, height: 8, lo: 0, hi: 20)
        let row = mapped.row(mapped.output(wide.image), y: 4, width: 256)
        var last = -1.0
        for (x, c) in row.enumerated() {
            XCTAssertTrue(c.isNeutral(tolerance: 4e-3), "x=\(x): \(c)")
            XCTAssertTrue(c.g.isFinite && c.g >= last - 2e-3 && c.g <= 1 + 1e-3, "x=\(x): \(c.g) after \(last)")
            last = max(last, c.g)
        }
        XCTAssertEqual(last, 1, accuracy: 2e-3)
        // The encoders go through the same mapper.
        XCTAssertGreaterThan(try mapped.jpeg(mapped.apply(try Look.parse("ev:+2"), to: wide)).count, 100)
    }
}
