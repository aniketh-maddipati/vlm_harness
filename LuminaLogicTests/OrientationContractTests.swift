import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// The orientation contract between the decoder and Metal.
///
/// `CIRAWFilter` applies the file's EXIF orientation itself — a frame tagged 8
/// comes out of the decoder already swapped — so `aligning(_:toFile:)` is a
/// no-op on the live path and `CIRenderDestination.isFlipped` is the only
/// remaining Y conversion.
///
/// `aligning` exists as a safety net for a decoder that leaves pixels in sensor
/// space, and that net has a hole worth naming: it decides whether to rotate by
/// comparing extents, and orientations 2, 3 and 4 do not change the extent. If a
/// non-orienting backend is ever linked (`libraw` and `rawspeed` are registered
/// `linked: false`), those three would render mirrored or upside down and the
/// extent check could not tell. These tests pin both halves so that change is
/// caught at the seam rather than discovered on screen.
final class OrientationContractTests: XCTestCase {

    /// EXIF values that rotate by a quarter turn, so width and height swap.
    private let swapping: [UInt32] = [5, 6, 7, 8]
    private let nonSwapping: [UInt32] = [1, 2, 3, 4]

    private func writeJPEG(width: Int, height: Int, orientation: UInt32) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        let unwrapped = try XCTUnwrap(context)
        // Asymmetric on both axes, so a wrong rotation is detectable in pixels
        // and not only in the extent.
        unwrapped.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        unwrapped.fill(CGRect(x: 0, y: 0, width: width, height: height))
        unwrapped.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        unwrapped.fill(CGRect(x: 0, y: height / 2, width: width / 3, height: height / 2))

        let image = try XCTUnwrap(unwrapped.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orientation-\(orientation)-\(UUID().uuidString).jpg")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - orientedSize

    func testOrientedSizeSwapsOnlyForQuarterTurns() {
        for orientation in swapping {
            let size = OrientedDisplayImage.orientedSize(
                pixelWidth: 6000, pixelHeight: 4000, orientation: orientation
            )
            XCTAssertEqual(size.width, 4000, "orientation \(orientation) must swap")
            XCTAssertEqual(size.height, 6000, "orientation \(orientation) must swap")
        }
        for orientation in nonSwapping {
            let size = OrientedDisplayImage.orientedSize(
                pixelWidth: 6000, pixelHeight: 4000, orientation: orientation
            )
            XCTAssertEqual(size.width, 6000, "orientation \(orientation) must not swap")
            XCTAssertEqual(size.height, 4000, "orientation \(orientation) must not swap")
        }
    }

    func testFileOrientationReadsTheTagBack() throws {
        for orientation in nonSwapping + swapping {
            let url = try writeJPEG(width: 120, height: 80, orientation: orientation)
            let file = try XCTUnwrap(OrientedDisplayImage.fileOrientation(at: url))
            XCTAssertEqual(file.orientation, orientation)
            XCTAssertEqual(file.pixelWidth, 120)
            XCTAssertEqual(file.pixelHeight, 80)
        }
    }

    // MARK: - The live path

    /// Pixels that already carry the orientation must pass through untouched.
    /// This is every frame today, because the decoder orients.
    func testAligningLeavesAlreadyOrientedPixelsAlone() throws {
        for orientation in nonSwapping + swapping {
            let url = try writeJPEG(width: 120, height: 80, orientation: orientation)
            let oriented = OrientedDisplayImage.orientedSize(
                pixelWidth: 120, pixelHeight: 80, orientation: orientation
            )
            let already = CIImage(color: .gray).cropped(to: CGRect(
                x: 0, y: 0, width: CGFloat(oriented.width), height: CGFloat(oriented.height)
            ))

            let result = OrientedDisplayImage.aligning(already, toFile: url)

            XCTAssertEqual(
                result.extent.width, CGFloat(oriented.width), accuracy: 1,
                "orientation \(orientation) was rotated a second time"
            )
            XCTAssertEqual(
                result.extent.height, CGFloat(oriented.height), accuracy: 1,
                "orientation \(orientation) was rotated a second time"
            )
            XCTAssertEqual(result.extent.origin.x, 0, accuracy: 0.001)
            XCTAssertEqual(result.extent.origin.y, 0, accuracy: 0.001)
        }
    }

    /// The decoder that reads a RAW today hands back oriented pixels. If this
    /// stops being true, `aligning`'s extent heuristic becomes load-bearing and
    /// the hole below starts mattering.
    func testRawDecoderAppliesFileOrientation() throws {
        guard let directory = ProcessInfo.processInfo.environment["LUMINA_RAW_DIR"],
              let contents = try? FileManager.default.contentsOfDirectory(
                  atPath: directory
              ) else {
            throw XCTSkip("set LUMINA_RAW_DIR to a folder of RAW frames")
        }
        let raws = contents
            .filter { $0.uppercased().hasSuffix(".ARW") }
            .sorted()
            .map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
        guard !raws.isEmpty else { throw XCTSkip("no .ARW frames in LUMINA_RAW_DIR") }

        var checked = 0
        for url in raws {
            guard let file = OrientedDisplayImage.fileOrientation(at: url),
                  let filter = CIRAWFilter(imageURL: url),
                  let output = filter.outputImage else { continue }
            let oriented = file.orientedSize
            XCTAssertEqual(
                Int(output.extent.width), oriented.width,
                "\(url.lastPathComponent): decoder output is not display-upright"
            )
            XCTAssertEqual(Int(output.extent.height), oriented.height)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no RAW frame could be opened")
    }

    // MARK: - The hole, named

    /// Sensor-space pixels at a quarter turn are recoverable: the extent tells
    /// `aligning` the rotation has not been applied yet.
    func testAligningRotatesSensorSpacePixelsForQuarterTurns() throws {
        for orientation in swapping {
            let url = try writeJPEG(width: 120, height: 80, orientation: orientation)
            let sensor = CIImage(color: .gray)
                .cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))

            let result = OrientedDisplayImage.aligning(sensor, toFile: url)

            XCTAssertEqual(
                result.extent.width, 80, accuracy: 1,
                "orientation \(orientation) left sensor-space pixels unrotated"
            )
            XCTAssertEqual(result.extent.height, 120, accuracy: 1)
        }
    }

    /// Orientations 2, 3 and 4 do not change the extent, so sensor-space pixels
    /// are indistinguishable from oriented ones and `aligning` cannot recover
    /// them. This is why the decoder — not this function — owns orientation.
    ///
    /// If a backend ever hands back sensor-space pixels, this test is the place
    /// the design decision gets revisited; it is not a bug to paper over here.
    func testAligningCannotRecoverNonSwappingOrientations() throws {
        for orientation in [2, 3, 4] as [UInt32] {
            let url = try writeJPEG(width: 120, height: 80, orientation: orientation)
            let sensor = CIImage(color: .gray)
                .cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))

            let result = OrientedDisplayImage.aligning(sensor, toFile: url)

            XCTAssertEqual(
                result.extent.width, 120, accuracy: 1,
                "orientation \(orientation) is extent-identical to sensor space; if "
                    + "this now rotates, the contract changed and the comment above is stale"
            )
            XCTAssertEqual(result.extent.height, 80, accuracy: 1)
        }
    }
}
