import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

final class OrientedDisplayImageTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oriented-display-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testOrientedSizeSwapsOnlyQuarterTurns() {
        for orientation in UInt32(1)...UInt32(8) {
            let size = OrientedDisplayImage.orientedSize(
                pixelWidth: 4000,
                pixelHeight: 3000,
                orientation: orientation
            )
            if OrientedDisplayImage.swapDimensions.contains(orientation) {
                XCTAssertEqual(size.width, 3000, "orientation \(orientation)")
                XCTAssertEqual(size.height, 4000, "orientation \(orientation)")
            } else {
                XCTAssertEqual(size.width, 4000, "orientation \(orientation)")
                XCTAssertEqual(size.height, 3000, "orientation \(orientation)")
            }
        }
    }

    func testImageIOBakesEveryEXIFOrientationIntoPixelSize() throws {
        for orientation in UInt32(1)...UInt32(8) {
            let url = try writeJPEG(width: 32, height: 16, orientation: orientation)
            let cg = try XCTUnwrap(
                OrientedDisplayImage.cgImage(at: url, maxPixelSize: 64),
                "orientation \(orientation)"
            )
            let expected = OrientedDisplayImage.orientedSize(
                pixelWidth: 32,
                pixelHeight: 16,
                orientation: orientation
            )
            XCTAssertEqual(cg.width, expected.width, "orientation \(orientation)")
            XCTAssertEqual(cg.height, expected.height, "orientation \(orientation)")

            let ci = OrientedDisplayImage.ciImage(fromOrientedPixels: cg)
            XCTAssertEqual(Int(ci.extent.width.rounded()), expected.width, "orientation \(orientation)")
            XCTAssertEqual(Int(ci.extent.height.rounded()), expected.height, "orientation \(orientation)")
            XCTAssertEqual(ci.extent.origin, .zero, "orientation \(orientation)")
        }
    }

    func testAligningRotatesSensorExtentForEXIF6() throws {
        let url = try writeJPEG(width: 40, height: 24, orientation: 6)
        let sensor = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 24))
        let aligned = OrientedDisplayImage.aligning(sensor, toFile: url)
        XCTAssertEqual(Int(aligned.extent.width.rounded()), 24)
        XCTAssertEqual(Int(aligned.extent.height.rounded()), 40)
        XCTAssertEqual(aligned.extent.origin, .zero)
    }

    func testAligningLeavesAlreadyOrientedExtentAlone() throws {
        let url = try writeJPEG(width: 40, height: 24, orientation: 6)
        let upright = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 24, height: 40))
        let aligned = OrientedDisplayImage.aligning(upright, toFile: url)
        XCTAssertEqual(Int(aligned.extent.width.rounded()), 24)
        XCTAssertEqual(Int(aligned.extent.height.rounded()), 40)
    }

    func testStablePresentKeepsOrientedFallbackAcrossAspectMismatch() {
        let landscape = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let portrait = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 1600))
        let kept = OrientedDisplayImage.stablePresent(promoted: landscape, fallback: portrait)
        XCTAssertEqual(kept?.extent, portrait.extent)

        let promoted = OrientedDisplayImage.stablePresent(promoted: portrait, fallback: portrait)
        XCTAssertEqual(promoted?.extent, portrait.extent)
    }

    func testRefusesRAWExtensionsWithoutOpeningTheFile() {
        let url = tempDir.appendingPathComponent("frame.ARW")
        FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        XCTAssertNil(OrientedDisplayImage.cgImage(at: url, maxPixelSize: 64))
        XCTAssertNil(OrientedDisplayImage.ciImage(at: url, maxPixelSize: 64))
    }

    private func writeJPEG(width: Int, height: Int, orientation: UInt32) throws -> URL {
        let url = tempDir.appendingPathComponent("o\(orientation)-\(UUID().uuidString).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "OrientedDisplayImageTests", code: 1)
        }
        ctx.setFillColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: height - 4, width: 4, height: 4))
        ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: width - 4, y: 0, width: 4, height: 4))
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "OrientedDisplayImageTests", code: 2)
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "OrientedDisplayImageTests", code: 3)
        }
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest), "failed to write orientation \(orientation)")
        return url
    }
}
