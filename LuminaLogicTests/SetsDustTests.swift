import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// The Mac half of dust: a preview's bytes become linear luma as stored (not turned, top row first),
/// and a run over frames of different scenes finds a spot placed in all of them.
final class SetsDustTests: XCTestCase {
    /// An sRGB JPEG, EXIF-turned by `orientation`, from a function of the stored pixel.
    private func jpeg(_ w: Int, _ h: Int, orientation: Int = 1, _ value: (Int, Int) -> Double) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let v = UInt8(max(0, min(255, (value(x, y) * 255).rounded())))
            bytes[(y * w + x) * 4] = v; bytes[(y * w + x) * 4 + 1] = v; bytes[(y * w + x) * 4 + 2] = v; bytes[(y * w + x) * 4 + 3] = 255
        } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let made = bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let image = try XCTUnwrap(made)
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 1.0, kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func testLumaIsLinearAndAsStored() throws {
        // Top half mid grey, bottom half white; turned 90° for display, which the measure ignores.
        let data = try jpeg(64, 48, orientation: 6) { _, y in y < 24 ? 0.5 : 1.0 }
        let p = try XCTUnwrap(SetsDust.luma(jpeg: data))
        XCTAssertEqual(p.width, 64); XCTAssertEqual(p.height, 48, "as stored, not turned")
        XCTAssertEqual(Double(p[32, 10]), 0.214, accuracy: 0.03, "sRGB 0.5 is about 0.21 in linear light, and the top row comes first")
        XCTAssertEqual(Double(p[32, 40]), 1.0, accuracy: 0.03)
    }

    func testFindsASpotThroughTheJPEGs() throws {
        let w = 480, h = 320
        let acc = LookDust.Accumulator(width: w, height: h)
        for seed in 0..<24 {
            let a = 0.35 + 0.02 * Double(seed % 7), gx = 0.1 * sin(Double(seed)), gy = 0.1 * cos(Double(seed) * 1.7)
            let data = try jpeg(w, h) { x, y in
                let dx = Double(x) + 0.5 - 300, dy = Double(y) + 0.5 - 100
                let sky = a + gx * Double(x) / Double(w) + gy * Double(y) / Double(h)
                return sky * (1 - 0.25 * exp(-(dx * dx + dy * dy) / 8))
            }
            XCTAssertTrue(acc.add(try XCTUnwrap(SetsDust.luma(jpeg: data))))
        }
        let spots = acc.spots()
        XCTAssertEqual(spots.count, 1, "\(spots)")
        XCTAssertEqual(try XCTUnwrap(spots.first).x * Double(w), 300, accuracy: 1.5)
        XCTAssertEqual(try XCTUnwrap(spots.first).y * Double(h), 100, accuracy: 1.5)
    }
}
