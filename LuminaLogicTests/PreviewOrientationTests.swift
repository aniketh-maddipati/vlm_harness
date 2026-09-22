import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// The browse tier must hand on pixels that are already the right way up.
///
/// `PreviewExtractor.extract` falls back to `exiftool -b -PreviewImage` when
/// ImageIO cannot thumbnail a RAW. That preview is the camera's embedded JPEG
/// verbatim: sensor space, and with no orientation tag of its own. Nothing
/// downstream can recover it — a decode transform is a no-op on an untagged file
/// — so a portrait frame was displayed on its side, and stayed there, because the
/// file survives every reopen.
///
/// These tests pin the bake that fixes it, and the no-ops that keep it from
/// becoming the same bug facing the other way.
final class PreviewOrientationTests: XCTestCase {

    /// A picture with a bright top-left, written with `orientation` in EXIF, or
    /// with no orientation tag at all when `orientation` is nil.
    private func writeJPEG(
        width: Int,
        height: Int,
        orientation: UInt32?
    ) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        let image = try XCTUnwrap(context.makeImage())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-orientation-\(UUID().uuidString).jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - The bake

    /// The reported flip, in one assertion: a landscape sensor-space preview of a
    /// portrait frame must come back portrait.
    func testSensorSpacePreviewOfAPortraitFrameIsTurnedUpright() throws {
        for orientation in [6, 8].map({ UInt32($0) }) {
            let source = try writeJPEG(width: 240, height: 160, orientation: orientation)
            let preview = try writeJPEG(width: 120, height: 80, orientation: nil)

            let upright = try XCTUnwrap(
                OrientedDisplayImage.uprightPreview(at: preview, fromSourceAt: source)
            )
            XCTAssertTrue(upright.rotated, "orientation \(orientation) was left in sensor space")
            XCTAssertEqual(upright.image.width, 80)
            XCTAssertEqual(upright.image.height, 120)
        }
    }

    /// A preview that is already the right way up must be left exactly alone.
    /// Rotating it is the same bug pointing the other way.
    func testUprightPreviewIsNotTurnedAgain() throws {
        let source = try writeJPEG(width: 240, height: 160, orientation: 8)
        // Already in the source's display shape — portrait.
        let preview = try writeJPEG(width: 80, height: 120, orientation: nil)

        let result = try XCTUnwrap(
            OrientedDisplayImage.uprightPreview(at: preview, fromSourceAt: source)
        )
        XCTAssertFalse(result.rotated)
        XCTAssertEqual(result.image.width, 80)
        XCTAssertEqual(result.image.height, 120)
    }

    /// A preview carrying its own tag is already handled by the ordinary decode.
    func testPreviewWithItsOwnTagIsLeftToTheDecoder() throws {
        let source = try writeJPEG(width: 240, height: 160, orientation: 8)
        let preview = try writeJPEG(width: 120, height: 80, orientation: 8)

        let result = try XCTUnwrap(
            OrientedDisplayImage.uprightPreview(at: preview, fromSourceAt: source)
        )
        XCTAssertFalse(result.rotated, "the decode transform already turned this one")
        XCTAssertEqual(result.image.width, 80, "decoded with its own orientation applied")
        XCTAssertEqual(result.image.height, 120)
    }

    /// An unrotated source leaves every preview untouched, which is the common case.
    func testUnrotatedSourceChangesNothing() throws {
        let source = try writeJPEG(width: 240, height: 160, orientation: 1)
        let preview = try writeJPEG(width: 120, height: 80, orientation: nil)

        let result = try XCTUnwrap(
            OrientedDisplayImage.uprightPreview(at: preview, fromSourceAt: source)
        )
        XCTAssertFalse(result.rotated)
        XCTAssertEqual(result.image.width, 120)
        XCTAssertEqual(result.image.height, 80)
    }

    // MARK: - Stale files already on disk

    /// The bake fixes what gets written from now on. A proxy written before it,
    /// sitting in a catalog, must still come out of the render graph upright.
    func testSidewaysProxyIsHealedByTheRenderGraph() async throws {
        // A portrait frame, and a proxy of it left in sensor space.
        let raw = try writeJPEG(width: 240, height: 160, orientation: 8)
        let staleProxy = try writeJPEG(width: 120, height: 80, orientation: nil)

        let result = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 1,
            photoID: UUID(),
            rawURL: raw,
            proxyURL: staleProxy,
            recipe: .neutral,
            quality: .browse,
            source: .jpegProxy
        ))
        let image = try XCTUnwrap(result.ciImage)
        XCTAssertEqual(
            image.extent.width, 80, accuracy: 1,
            "a stale sensor-space proxy still reached the drawable on its side"
        )
        XCTAssertEqual(image.extent.height, 120, accuracy: 1)

        let probe = try XCTUnwrap(PhotoPresentProof.probe(
            image,
            drawableSize: CGSize(width: 320, height: 240)
        ))
        XCTAssertFalse(probe.isBlank, "healing the orientation must not cost the pixels")
    }

    /// And a correct proxy must survive that healing untouched.
    func testUprightProxyIsNotHealedIntoBeingWrong() async throws {
        let raw = try writeJPEG(width: 240, height: 160, orientation: 8)
        let goodProxy = try writeJPEG(width: 80, height: 120, orientation: nil)

        let result = await DevelopRenderGraph.render(RawRenderRequest(
            generation: 1,
            photoID: UUID(),
            rawURL: raw,
            proxyURL: goodProxy,
            recipe: .neutral,
            quality: .browse,
            source: .jpegProxy
        ))
        let image = try XCTUnwrap(result.ciImage)
        XCTAssertEqual(image.extent.width, 80, accuracy: 1)
        XCTAssertEqual(image.extent.height, 120, accuracy: 1)
    }

    // MARK: - Real frames

    /// The synthetic cases pin the rule; this one runs it over the frames the flip
    /// was measured on. Skips rather than passing vacuously with no fixtures.
    func testEveryRawFixturePreviewEndsUpUpright() throws {
        let home = NSHomeDirectory()
        let candidates = [
            ProcessInfo.processInfo.environment["LUMINA_RAW_DIR"],
            home + "/LuminaFixtures/card-elastic-v4/frames",
            home + "/Pictures/LuminaFixtures/card-elastic-v4/frames",
        ].compactMap { $0 }
        guard let directory = candidates
            .map({ URL(fileURLWithPath: $0, isDirectory: true) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no RAW fixture folder")
        }
        try XCTSkipUnless(ExifToolService.isAvailable, "exiftool not installed")

        let raws = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.uppercased() == "ARW" }
        .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1_000_000 }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(raws.isEmpty, "no .ARW frames in the fixture folder")

        var rotated = 0
        var checkedRotatedSource = 0
        for url in raws.prefix(8) {
            let file = try XCTUnwrap(OrientedDisplayImage.fileOrientation(at: url))
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("fixture-preview-\(UUID().uuidString).jpg")
            guard (try? ExifToolService.extractPreview(from: url, to: temp)) != nil else { continue }
            defer { try? FileManager.default.removeItem(at: temp) }

            let upright = try XCTUnwrap(
                OrientedDisplayImage.uprightPreview(at: temp, fromSourceAt: url),
                "\(url.lastPathComponent): no preview could be read"
            )
            if upright.rotated { rotated += 1 }
            if file.orientation != 1 { checkedRotatedSource += 1 }

            let oriented = file.orientedSize
            XCTAssertEqual(
                upright.image.height > upright.image.width,
                oriented.height > oriented.width,
                "\(url.lastPathComponent): preview is \(upright.image.width)×"
                    + "\(upright.image.height) for a \(oriented.width)×\(oriented.height) frame"
            )
        }

        XCTAssertGreaterThan(
            checkedRotatedSource, 0,
            "no rotated frame in the fixture folder, so nothing here was exercised"
        )
        XCTAssertGreaterThan(
            rotated, 0,
            "no preview needed turning — the fixture card measured seven that do, so "
                + "either the fixtures changed or the bake stopped running"
        )
    }
}
