import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import Lumina

/// `lumina.masks`: the selections Vision finds in a photo's preview (DESIGN-ASKS Prompt 28). The
/// pixel-buffer and luminance reads are checked everywhere; the finding itself needs Vision's
/// instance-mask requests and skips where this Mac can't run them. The maths is LookMasksTests.
final class SetsMasksTests: XCTestCase {
    private func buffer(_ format: OSType, w: Int, h: Int, fill: (Int, Int, UnsafeMutableRawPointer, Int) -> Void) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, w, h, format, nil, &pb), kCVReturnSuccess)
        let b = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(b, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(b)), row = CVPixelBufferGetBytesPerRow(b)
        for y in 0..<h { for x in 0..<w { fill(x, y, base.advanced(by: y * row), x) } }
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }

    func testFloatAndByteBuffersReadAsPlanes() throws {
        let f = try buffer(kCVPixelFormatType_OneComponent32Float, w: 5, h: 3) { x, y, row, i in
            row.assumingMemoryBound(to: Float.self)[i] = x == 4 ? 1.5 : Float(x + y) / 10
        }
        let pf = try XCTUnwrap(SetsMasks.plane(f))
        XCTAssertEqual(pf.width, 5); XCTAssertEqual(pf.height, 3)
        XCTAssertEqual(pf[2, 1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(pf[4, 0], 1, "clamped to 0 … 1")
        let b = try buffer(kCVPixelFormatType_OneComponent8, w: 4, h: 2) { x, _, row, i in
            row.assumingMemoryBound(to: UInt8.self)[i] = x == 0 ? 255 : 0
        }
        let pb = try XCTUnwrap(SetsMasks.plane(b))
        XCTAssertEqual(pb.values, [1, 0, 0, 0, 1, 0, 0, 0])
        var other: CVPixelBuffer?
        CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &other)
        XCTAssertNil(SetsMasks.plane(try XCTUnwrap(other)), "not a one-channel buffer")
    }

    /// A dark room with a bright figure and a ball: something for the foreground finder.
    private func picture(w: Int = 768, h: Int = 512) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let W = CGFloat(w), H = CGFloat(h)
        ctx.setFillColor(CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(CGColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 0.25 * H))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 0.30 * W, y: 0.20 * H, width: 0.30 * H, height: 0.30 * H))
        ctx.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1)); ctx.fill(CGRect(x: 0.62 * W, y: 0.20 * H, width: 0.10 * W, height: 0.50 * H))
        ctx.fillEllipse(in: CGRect(x: 0.635 * W, y: 0.70 * H, width: 0.07 * W, height: 0.07 * W))
        return ctx.makeImage()!
    }

    func testLuminanceIsTheGuideAtThePicturesSize() throws {
        let img = picture()
        let l = try XCTUnwrap(SetsMasks.luminance(img))
        XCTAssertEqual(l.width, img.width); XCTAssertEqual(l.height, img.height)
        XCTAssertTrue(l.values.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(l.values.max()!, 0.6); XCTAssertLessThan(l.values.min()!, 0.2)
    }

    func testFindsSelectionsInAPictureOrSaysVisionCannot() throws {
        guard let found = SetsMasks.masks(picture()) else { throw XCTSkip("Vision's instance-mask requests don't run on this Mac") }
        // Vision may find nothing in a drawing; what it finds must be well formed.
        for f in found {
            XCTAssertTrue((0...1).contains(f.score)); XCTAssertTrue((0...1).contains(f.area))
            XCTAssertTrue([f.box.x, f.box.y, f.box.w, f.box.h].allSatisfy { (0...1).contains($0) })
            XCTAssertFalse(f.outline.isEmpty, "\(f.id) has an outline")
        }
        if !found.isEmpty { XCTAssertEqual(found.first?.kind, .subject, "the subject comes first") }
        XCTAssertTrue(JSONSerialization.isValidJSONObject(found.map(\.dictionary)))
    }

    /// A blue sky, darker at the top, over green hills with a jagged ridge and some texture:
    /// something the scene classifier may call sky.
    private func skyPicture(w: Int = 1024, h: Int = 683) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let W = CGFloat(w), H = CGFloat(h)
        let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                             colors: [CGColor(red: 0.20, green: 0.42, blue: 0.85, alpha: 1), CGColor(red: 0.62, green: 0.78, blue: 0.95, alpha: 1)] as CFArray,
                             locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0.4 * H), options: [.drawsAfterEndLocation])
        let ridge = CGMutablePath()
        ridge.move(to: .zero)
        for i in 0...16 {
            let peak: CGFloat = i % 2 == 0 ? 0.08 : 0, step: CGFloat = 0.04 * CGFloat(i % 3)
            ridge.addLine(to: CGPoint(x: W * CGFloat(i) / 16, y: H * (0.42 + peak + step)))
        }
        ridge.addLine(to: CGPoint(x: W, y: 0)); ridge.closeSubpath()
        ctx.setFillColor(CGColor(red: 0.22, green: 0.38, blue: 0.16, alpha: 1)); ctx.addPath(ridge); ctx.fillPath()
        var seed: UInt64 = 1
        for _ in 0..<4000 {                                              // texture: small dark and light leaves
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let x = CGFloat(seed >> 40 & 0xFFFF) / 65535 * W, y = CGFloat(seed >> 20 & 0xFFFF) / 65535 * 0.42 * H, k = CGFloat(seed & 0xFF) / 255
            ctx.setFillColor(CGColor(red: 0.12 + 0.3 * k, green: 0.25 + 0.3 * k, blue: 0.08 + 0.1 * k, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
        return ctx.makeImage()!
    }

    func testColourPlanesAreThePicturesOwn() throws {
        let img = skyPicture(w: 64, h: 48)
        let c = try XCTUnwrap(SetsMasks.rgb(img))
        XCTAssertEqual(c.red.width, 64); XCTAssertEqual(c.blue.height, 48)
        XCTAssertGreaterThan(c.blue[32, 0], c.red[32, 0] + 0.3, "the top row is the sky (row 0 is the picture's top)")
        XCTAssertGreaterThan(c.green[32, 47], c.blue[32, 47], "the bottom row is the hills")
    }

    /// The classifier is the gate: a picture it calls sky gets a "sky" mask, between the objects
    /// and the background. Skips where Vision can't classify, or doesn't call this drawing sky.
    func testASkyPictureGetsASkyMaskWhenTheClassifierSaysSky() throws {
        let img = skyPicture()
        guard let labels = SetsMasks.scene(img) else { throw XCTSkip("Vision's scene classifier doesn't run on this Mac") }
        XCTAssertFalse(labels.isEmpty, "the classifier answered with labels")
        XCTAssertNil(SetsMasks.sky(img, labels: [:]), "no sky label, no sky looked for")
        guard let score = LookMasks.skyScore(labels) else {
            throw XCTSkip("Vision doesn't call this drawing sky: \(labels.filter { $0.value > 0.1 }.sorted { $0.value > $1.value }.prefix(8))")
        }
        let region = try XCTUnwrap(SetsMasks.sky(img, labels: labels), "the finder finds the drawn sky")
        XCTAssertEqual(region.score, score, accuracy: 1e-9)
        XCTAssertGreaterThan(LookMasks.area(region.mask), 0.3)
        let found = try XCTUnwrap(SetsMasks.masks(img))
        let sky = try XCTUnwrap(found.first { $0.kind == .sky })
        XCTAssertEqual(sky.id, "sky")
        if let bg = found.firstIndex(where: { $0.kind == .background }) { XCTAssertLessThan(found.firstIndex(where: { $0.kind == .sky })!, bg) }
        XCTAssertTrue(JSONSerialization.isValidJSONObject(found.map(\.dictionary)))
    }

    func testAJPEGThatIsNotOneIsNil() {
        XCTAssertNil(SetsMasks.masks(jpeg: Data("not a jpeg".utf8)))
    }

    /// Skim's frame arrives as base64 from the page (`skimMasks`): only a JPEG under the limit is read.
    func testSkimFrameIsABase64JPEGUnderTheLimit() throws {
        XCTAssertNil(SetsMasks.masks(frame: nil)); XCTAssertNil(SetsMasks.masks(frame: 42)); XCTAssertNil(SetsMasks.masks(frame: ""))
        XCTAssertNil(SetsMasks.masks(frame: "not base64 at all"))
        XCTAssertNil(SetsMasks.masks(frame: Data("not a jpeg".utf8).base64EncodedString()))
        XCTAssertNil(SetsMasks.masks(frame: String(repeating: "A", count: SetsMasks.frameLimit + 4)), "over the limit, not decoded")
        let out = NSMutableData()
        let dst = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dst, picture(), nil); XCTAssertTrue(CGImageDestinationFinalize(dst))
        guard let found = SetsMasks.masks(frame: (out as Data).base64EncodedString()) else { throw XCTSkip("Vision's instance-mask requests don't run on this Mac") }
        XCTAssertTrue(JSONSerialization.isValidJSONObject(found.map(\.dictionary)))
    }
}
