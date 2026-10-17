import CoreImage
import ImageIO
import XCTest
@testable import Lumina

/// Adjustments inside a mask in the real graph (DESIGN-ASKS Prompt 29, `Look.locals`): a mask's
/// sliders change only the picture inside it, the mask stays on the same content through the
/// crop, the straighten, the quarter turn and the canvas's bases, an unknown mask renders as the
/// look without it, and the image path and the export render the same thing.
final class LookMaskPipelineTests: XCTestCase {
    var pipe: LookPipeline!
    let asShot = Look.WhiteBalance(kelvin: 5500, tint: 0)

    override func setUpWithError() throws {
        pipe = try LookPipeline(rules: LookTestRules.load())
    }

    private typealias P = LookMasks.Point

    /// A found mask whose outline is the box x0 … x1, y0 … y1 (fractions of the photo, from its top left).
    private func box(_ id: String, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> LookMasks.Found {
        LookMasks.Found(id: id, kind: .object, score: 1, box: LookMasks.Box(x: x0, y: y0, w: x1 - x0, h: y1 - y0), area: (x1 - x0) * (y1 - y0),
                        outline: [[P(x: x0, y: y0), P(x: x1, y: y0), P(x: x1, y: y1), P(x: x0, y: y1)]])
    }

    /// `w × h`: red grows to the right, green toward the top, blue 0.25 (bitmap row 0 is the top).
    private func gradient(_ w: Int, _ h: Int) -> LookPipeline.Developed {
        var data = [Float](repeating: 1, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let i = 4 * (y * w + x); data[i] = 0.05 + 0.6 * Float(x) / Float(w - 1); data[i + 1] = 0.05 + 0.6 * (1 - Float(y) / Float(h - 1)); data[i + 2] = 0.25 } }
        let img = CIImage(bitmapData: data.withUnsafeBufferPointer { Data(buffer: $0) }, bytesPerRow: w * 16, size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: pipe.workingSpace)
        return LookPipeline.Developed(image: img, asShot: asShot, anchor: .reference)
    }

    private func luma(_ c: LookMath.RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    // MARK: The mask's place

    func testALeftHalfMaskBrightensOnlyTheLeftHalf() throws {
        let dev = pipe.flat(.gray(0.18), size: 64).withMasks([box("left", 0, 0, 0.5, 1)], key: "test/left")
        let plain = pipe.apply(Look(), to: dev)
        let out = pipe.apply(try Look.parse("mask:left/ev=+1"), to: dev)
        XCTAssertEqual(out.extent, plain.extent)
        for y in [2, 32, 61] {
            XCTAssertGreaterThan(pipe.pixel(out, x: 8, y: y).g, pipe.pixel(plain, x: 8, y: y).g * 1.5, "left, row \(y): brighter")
            XCTAssertEqual(pipe.pixel(out, x: 56, y: y).g, pipe.pixel(plain, x: 56, y: y).g, accuracy: 1e-3, "right, row \(y): untouched")
        }
        // The same stages as the global slider: inside the mask the picture is the global ev:+1's.
        let global = pipe.apply(try Look.parse("ev:+1"), to: dev)
        XCTAssertEqual(pipe.pixel(out, x: 4, y: 32).g, pipe.pixel(global, x: 4, y: 32).g, accuracy: 2e-3)
    }

    /// The outline's y runs down from the photo's top; Core Image's runs up from the bottom.
    func testATopMaskIsTheTopOfThePicture() throws {
        let dev = pipe.flat(.gray(0.18), size: 64).withMasks([box("top", 0, 0, 1, 0.25)], key: "test/top")
        let plain = pipe.apply(Look(), to: dev), out = pipe.apply(try Look.parse("mask:top/ev=+1"), to: dev)
        XCTAssertGreaterThan(pipe.pixel(out, x: 32, y: 60).g, pipe.pixel(plain, x: 32, y: 60).g * 1.5, "the top rows (Core Image y near 63)")
        XCTAssertEqual(pipe.pixel(out, x: 32, y: 4).g, pipe.pixel(plain, x: 32, y: 4).g, accuracy: 1e-3, "the bottom rows")
        XCTAssertEqual(pipe.pixel(out, x: 32, y: 40).g, pipe.pixel(plain, x: 32, y: 40).g, accuracy: 1e-3, "below the top quarter")
    }

    /// Crop (the left half) then a quarter turn: the photo's left quarter is the cropped picture's
    /// left half, which the turn puts on top. The mask follows it there.
    func testCropAndTurnKeepTheMaskOnTheSameContent() throws {
        let dev = gradient(64, 32).withMasks([box("lq", 0, 0, 0.25, 1)], key: "test/lq")
        var look = try Look.parse("mask:lq/ev=+1"); look.crop = Look.Crop(x: 0, y: 0, w: 0.5, h: 1); look.rot = 90
        var bare = look; bare.locals = []
        let out = pipe.apply(look, to: dev), plain = pipe.apply(bare, to: dev)
        XCTAssertEqual(out.extent, CGRect(x: 0, y: 0, width: 32, height: 32))
        for x in [4, 16, 28] {
            XCTAssertGreaterThan(luma(pipe.pixel(out, x: x, y: 28)), luma(pipe.pixel(plain, x: x, y: 28)) * 1.3, "top (the photo's left quarter), x \(x)")
            XCTAssertEqual(luma(pipe.pixel(out, x: x, y: 3)), luma(pipe.pixel(plain, x: x, y: 3)), accuracy: 1e-3, "bottom, x \(x)")
        }
        // A straighten moves the mask with the picture: where the transform says a photo point
        // went, the picture there is that point's colour.
        var straight = Look(); straight.crop = Look.Crop(x: 0.1, y: 0.1, w: 0.8, h: 0.8, rotate: 8); straight.rot = 270
        let g = pipe.geometryPlaced(dev.image, straight.crop, rot: straight.rot)
        let photo = LookPipeline.frameTransform(dev.extent).concatenating(g.transform)
        for (u, v) in [(0.3, 0.3), (0.5, 0.5), (0.7, 0.6)] {
            let at = CGPoint(x: u, y: v).applying(photo), src = CGPoint(x: u, y: v).applying(LookPipeline.frameTransform(dev.extent))
            let a = pipe.pixel(g.image, x: Int(at.x), y: Int(at.y)), b = pipe.pixel(dev.image, x: Int(src.x), y: Int(src.y))
            XCTAssertEqual(a.r, b.r, accuracy: 0.03, "(\(u), \(v)) red"); XCTAssertEqual(a.g, b.g, accuracy: 0.05, "(\(u), \(v)) green")
        }
    }

    func testAnUnknownMaskRendersLikeTheLookWithoutIt() throws {
        let dev = gradient(48, 32)
        let with = dev.withMasks([box("subject", 0.2, 0.2, 0.8, 0.8)], key: "test/u")
        let base = try Look.parse("con:+10 sat:+5"), unknown = try Look.parse("con:+10 sat:+5 mask:person-9/ev=+1")
        let want = pipe.apply(base, to: dev)
        for img in [pipe.apply(unknown, to: with), pipe.apply(unknown, to: dev), pipe.apply(try Look.parse("con:+10 sat:+5 mask:subject/ev=+1"), to: dev)] {
            for (x, y) in [(3, 3), (24, 16), (44, 29)] { XCTAssertEqual(pipe.pixel(img, x: x, y: y), pipe.pixel(want, x: x, y: y)) }
        }
    }

    // MARK: Every caller lines up

    /// The canvas's bases bake the crop and the turn in and scale: `Entry.toPhoto` carries the
    /// photo there, so a mask lands on the same content in `base` and `small` as in the full render.
    func testBasesPlaceTheMaskWhereTheFullRenderDoes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-mask-bases-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("g.png")
        try pipe.png(gradient(300, 200).image).write(to: url)
        let bases = LookBases(pipeline: pipe, byteCap: 64 << 20, maxPhotos: 3)
        var look = try Look.parse("mask:lq/ev=+1"); look.crop = Look.Crop(x: 0, y: 0, w: 0.5, h: 1); look.rot = 90
        var bare = look; bare.locals = []
        let e = try bases.build(LookBases.Key(rel: "s/g.png", decoder: nil, look: look, canvas: CGSize(width: 200, height: 200)), url: url, look: look, preview: nil)
        let found = [box("lq", 0, 0, 0.25, 1)]
        let masks = LookPipeline.PhotoMasks(key: "test/bases", found: found, toImage: .identity)
        // The photo's top left is the cropped picture's top left, turned clockwise: the base's top right.
        let tl = CGPoint(x: 0, y: 0).applying(e.toPhoto(small: false))
        XCTAssertEqual(tl.x, e.baseSize.width, accuracy: 1.5); XCTAssertEqual(tl.y, e.baseSize.height, accuracy: 1.5)
        for small in [false, true] {
            let src = small ? e.small : e.base, size = small ? e.smallSize : e.baseSize
            let dev = LookPipeline.Developed(image: src, asShot: e.asShot, anchor: e.anchor, masks: masks.placed(photo: e.toPhoto(small: small)))
            let out = pipe.apply(look, to: dev, crop: false), plain = pipe.apply(bare, to: dev, crop: false)
            func at(_ u: Double, _ v: Double) -> (Double, Double) {
                let p = CGPoint(x: u, y: v).applying(e.toPhoto(small: small))
                let x = min(Int(size.width) - 1, max(0, Int(p.x))), y = min(Int(size.height) - 1, max(0, Int(p.y)))
                return (luma(pipe.pixel(out, x: x, y: y)), luma(pipe.pixel(plain, x: x, y: y)))
            }
            let inside = at(0.1, 0.5), outside = at(0.4, 0.5)
            XCTAssertGreaterThan(inside.0, inside.1 * 1.3, "small \(small): inside the mask")
            XCTAssertEqual(outside.0, outside.1, accuracy: 1e-3, "small \(small): outside it")
        }
        // An entry made elsewhere (no transform) is the whole photo, upright.
        let t = LookBases.Entry(base: e.base, small: e.small, asShot: e.asShot, anchor: e.anchor, baseSize: CGSize(width: 300, height: 200), smallSize: CGSize(width: 75, height: 50),
                                photoSize: e.photoSize, bytes: 0, source: "image", decoder: nil, developMs: 0, onGPU: false, textures: []).toPhoto(small: true)
        XCTAssertEqual(CGPoint(x: 1, y: 0).applying(t), CGPoint(x: 75, y: 50))
    }

    func testFrameTransformsAndMappings() {
        let f = LookPipeline.frameTransform(CGRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(f), CGPoint(x: 0, y: 400), "the photo's top left is Core Image's (0, height)")
        XCTAssertEqual(CGPoint(x: 1, y: 1).applying(f), CGPoint(x: 600, y: 0))
        // A turned region (the loupe's tiles): the whole frame, then the turn.
        let turned = f.concatenating(LookPipeline.turnTransform(size: CGSize(width: 600, height: 400), rot: 90))
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(turned), CGPoint(x: 400, y: 600), "clockwise: the top left goes to the top right")
        let m = LookPipeline.mapping(from: CGRect(x: 0, y: 0, width: 200, height: 100), to: CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(CGPoint(x: 200, y: 100).applying(m), CGPoint(x: 110, y: 70))
    }

    /// The image path (`LookRenderer`) and the export (`SetsLookExport`) take the photo's masks
    /// the same way: the developed image is the whole photo. The same file and look render the
    /// same pixels through both; an unknown id renders as the look without it.
    func testImagePathAndExportRenderTheMaskAlike() throws {
        if (try? LookRules.bundled()) == nil { setenv("LUMINA_RULES", LookTestRules.url().path, 1) }
        guard (try? LookRules.bundled()) != nil else { throw XCTSkip("rules-v1.json is neither bundled nor reachable through LUMINA_RULES") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("look-mask-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("g.png")
        try pipe.png(gradient(64, 48).image).write(to: url)
        let found = [box("subject", 0.25, 0.25, 0.75, 0.75)]
        func pixels(_ data: Data) throws -> [UInt8] {
            let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil)), cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            let ctx = try XCTUnwrap(CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: cg.width * cg.height * 4))
        }
        let masked = try pixels(SetsLookExport.render(raw: url, look: "mask:subject/ev=+1", px: nil, format: "png", decoder: nil, masks: found).0)
        let plain = try pixels(SetsLookExport.render(raw: url, look: "", px: nil, format: "png", decoder: nil).0)
        let unknown = try pixels(SetsLookExport.render(raw: url, look: "mask:person-3/ev=+1", px: nil, format: "png", decoder: nil, masks: found).0)
        XCTAssertEqual(unknown, plain, "an id the photo does not have: the look without it")
        // Row 24 (from the top), column 32 is inside the box; column 4 is not.
        let w = 64, centre = 4 * (24 * w + 32), edge = 4 * (24 * w + 4)
        XCTAssertGreaterThan(Int(masked[centre + 1]), Int(plain[centre + 1]) + 20, "inside: brighter")
        XCTAssertEqual(Int(masked[edge + 1]), Int(plain[edge + 1]), accuracy: 1, "outside: the same")
        // The image path: the same file, look and masks through LookRenderer, as a JPEG.
        let renderer = try LookRenderer(rules: LookTestRules.load())
        renderer.requested(rel: "s/g.png", seq: 1)
        let jpeg = try pixels(renderer.renderJPEG(url: url, rel: "s/g.png", look: "mask:subject/ev=+1", px: 64, seq: 1, masks: { found }))
        let jpegPlain = try pixels(renderer.renderJPEG(url: url, rel: "s/g.png", look: "", px: 64, seq: 1))
        XCTAssertGreaterThan(Int(jpeg[centre + 1]), Int(jpegPlain[centre + 1]) + 20, "the image path brightens the same place")
        XCTAssertEqual(Int(jpeg[centre + 1]), Int(masked[centre + 1]), accuracy: 4, "as the export does (JPEG rounding aside)")
        XCTAssertEqual(Int(jpeg[edge + 1]), Int(jpegPlain[edge + 1]), accuracy: 2)
    }
}
