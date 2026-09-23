import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// Proof that the photograph itself renders.
///
/// Every capture the harness writes hosts a view offscreen and reads it back with
/// `cacheDisplay`; SwiftUI's `.task` does not run for such a view and Metal layers
/// do not composite through it, so a photograph is exactly the thing those captures
/// cannot see. These tests need no view at all: they push real files through
/// `DevelopRenderGraph` — the graph the app displays from — put the result through
/// the same present transform `DevelopMetalView` uses, and read the pixels back
/// with the drawable's own `isFlipped` convention.
///
/// A photograph that stops rendering, comes out blank, or comes out the wrong way
/// up fails here.
final class PhotoRenderProofTests: XCTestCase {

    /// Big enough that a quadrant mean is a real average, small enough to stay fast.
    private let drawable = CGSize(width: 320, height: 240)

    // MARK: - Fixtures

    /// A photograph with one bright corner, written with `orientation` in EXIF.
    ///
    /// The bright patch sits in the **stored** top-left. Which display corner that
    /// becomes is the orientation contract, and `displayCorner(for:)` names it.
    private func writePhotograph(
        width: Int,
        height: Int,
        orientation: UInt32
    ) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext's origin is bottom-left, so the stored top-left half-quadrant
        // is the high-y, low-x one.
        context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1))
        context.fill(CGRect(
            x: 0, y: height / 2,
            width: width / 2, height: height - height / 2
        ))
        let image = try XCTUnwrap(context.makeImage())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-proof-\(orientation)-\(UUID().uuidString).jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(
            destination, image,
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1.0,
            ] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Where the stored top-left corner lands once EXIF orientation is applied,
    /// as an index into `PhotoPresentProof.Probe.quadrants`
    /// (`0` top-left, `1` top-right, `2` bottom-left, `3` bottom-right).
    ///
    /// Read off the EXIF definitions: 2 mirrors horizontally, 3 turns 180°,
    /// 4 mirrors vertically, 6 turns 90° clockwise, 8 turns 90° counter-clockwise,
    /// and 5 / 7 are those two quarter turns with a horizontal mirror first.
    private func displayCorner(for orientation: UInt32) -> Int {
        switch orientation {
        case 1, 5: return 0
        case 2, 6: return 1
        case 4, 8: return 2
        case 3, 7: return 3
        default:
            XCTFail("orientation \(orientation) is not one of the eight EXIF values")
            return 0
        }
    }

    private func renderThroughGraph(
        _ url: URL,
        recipe: EditRecipe = .neutral,
        quality: DevelopRenderQuality = .browse
    ) async -> DevelopRenderResult {
        await DevelopRenderGraph.render(RawRenderRequest(
            generation: 1,
            photoID: UUID(),
            rawURL: url,
            recipe: recipe,
            quality: quality
        ))
    }

    // MARK: - The photograph reaches the drawable

    func testGraphPutsRealPixelsOnTheDrawable() async throws {
        let url = try writePhotograph(width: 240, height: 160, orientation: 1)

        let result = await renderThroughGraph(url)
        let image = try XCTUnwrap(result.ciImage, "the graph produced no image at all")
        XCTAssertEqual(image.extent.width, 240, accuracy: 1)
        XCTAssertEqual(image.extent.height, 160, accuracy: 1)

        let probe = try XCTUnwrap(
            PhotoPresentProof.probe(image, drawableSize: drawable),
            "the present transform produced nothing to draw"
        )
        XCTAssertFalse(
            probe.isBlank,
            "the drawable is empty: coverage \(probe.coverage), contrast \(probe.contrast)"
        )
        // 240×160 aspect-fitted into 320×240 fills the full width and 213 of the
        // 240 rows. An empty well reads far below that, and a photograph stretched
        // to fill the well reads 1.0.
        let fitted = 320.0 * (320.0 / 240.0 * 160.0)
        XCTAssertEqual(
            probe.coverage, fitted / (320.0 * 240.0), accuracy: 0.02,
            "the photograph does not cover its aspect-fitted box"
        )
    }

    /// The one a reader notices. Every EXIF orientation must land its bright corner
    /// where the contract says, through the real decode-and-present path.
    func testPhotographIsNeverPresentedUpsideDown() async throws {
        for orientation in (1...8).map({ UInt32($0) }) {
            let url = try writePhotograph(width: 240, height: 160, orientation: orientation)

            let result = await renderThroughGraph(url)
            let image = try XCTUnwrap(
                result.ciImage,
                "orientation \(orientation) produced no image"
            )
            let probe = try XCTUnwrap(
                PhotoPresentProof.probe(image, drawableSize: drawable),
                "orientation \(orientation) produced nothing to draw"
            )

            XCTAssertFalse(probe.isBlank, "orientation \(orientation) drew a blank frame")
            let expected = displayCorner(for: orientation)
            XCTAssertEqual(
                probe.brightestQuadrant, expected,
                "orientation \(orientation): the bright corner is in quadrant "
                    + "\(probe.brightestQuadrant), expected \(expected) — "
                    + "quadrants \(probe.quadrants)"
            )
        }
    }

    /// A quarter turn swaps the extent, and the presented image must swap with it.
    /// A portrait frame drawn landscape is the flip the user reported, seen in numbers.
    func testQuarterTurnPresentsPortrait() async throws {
        for orientation in [5, 6, 7, 8].map({ UInt32($0) }) {
            let url = try writePhotograph(width: 240, height: 160, orientation: orientation)
            let result = await renderThroughGraph(url)
            let image = try XCTUnwrap(result.ciImage)
            XCTAssertEqual(
                image.extent.width, 160, accuracy: 1,
                "orientation \(orientation) did not swap width and height"
            )
            XCTAssertEqual(image.extent.height, 240, accuracy: 1)
        }
    }

    // MARK: - The present transform itself

    /// `positioned` must not invert. The probe reads row zero as the top, exactly as
    /// the drawable does, so a flipped transform shows up as a swapped quadrant pair.
    func testPresentTransformKeepsTheTopEdgeOnTop() throws {
        let url = try writePhotograph(width: 240, height: 160, orientation: 1)
        let image = try XCTUnwrap(OrientedDisplayImage.ciImage(at: url))

        let probe = try XCTUnwrap(PhotoPresentProof.probe(image, drawableSize: drawable))

        XCTAssertGreaterThan(
            probe.quadrants[0], probe.quadrants[2],
            "the top-left quadrant is darker than the bottom-left one — the "
                + "photograph is upside down on the drawable"
        )
        XCTAssertGreaterThan(probe.quadrants[0], probe.quadrants[1])
    }

    /// Zoom and pan move the photograph; they must not turn it over.
    func testZoomAndPanDoNotInvertThePhotograph() throws {
        let url = try writePhotograph(width: 240, height: 160, orientation: 1)
        let image = try XCTUnwrap(OrientedDisplayImage.ciImage(at: url))

        let panned = try XCTUnwrap(PhotoPresentProof.probe(
            image,
            drawableSize: drawable,
            zoom: 2,
            panOffset: CGSize(width: 12, height: 8)
        ))
        XCTAssertFalse(panned.isBlank)
        XCTAssertGreaterThan(
            panned.quadrants[0], panned.quadrants[3],
            "zoom and pan inverted the photograph: \(panned.quadrants)"
        )
    }

    /// No pixels means an honest empty drawable, not a stale photograph — and the
    /// probe must be able to tell the two apart, or none of the above proves anything.
    func testBlankIsDetectedAsBlank() throws {
        let flat = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 240, height: 160))
        let probe = try XCTUnwrap(PhotoPresentProof.probe(flat, drawableSize: drawable))
        XCTAssertTrue(probe.isBlank, "a flat field must read as blank: \(probe.quadrants)")

        let empty = CIImage.empty()
        XCTAssertNil(
            PhotoPresentProof.positioned(empty, in: drawable),
            "an image with no extent cannot be positioned on a drawable"
        )
    }

    // MARK: - Real RAW frames

    /// Where real RAW frames live, if they do on this machine.
    ///
    /// `LUMINA_RAW_DIR` first, to match the other fixture-gated tests — but note
    /// that **xcodebuild cannot put an environment variable into a hosted logic
    /// test's process**: neither `TEST_RUNNER_LUMINA_RAW_DIR=` nor a plain
    /// `LUMINA_RAW_DIR=` argument arrives (both measured, both still skip). The
    /// host app is launched through launchd with a scrubbed environment, so the
    /// env path only works from a scheme or test plan. The disk candidates below
    /// are what makes this gate actually run: the elastic fixture card as
    /// `Scripts/harness/fixtures/elastic_cards.py` writes it, and the develop
    /// lab's own fixture folder.
    private func rawFixtureDirectory() -> URL? {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["LUMINA_RAW_DIR"], !env.isEmpty {
            candidates.append(env)
        }
        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            home + "/LuminaFixtures/card-elastic-v4/frames",
            home + "/Pictures/LuminaFixtures/card-elastic-v4/frames",
            home + "/Pictures/LuminaFixtures",
        ])
        return candidates
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The synthetic cases above pin the contract; this one pins the decoder that
    /// actually runs. Fixture-gated, never fixture-faked: with no RAW folder it
    /// skips rather than passing vacuously.
    func testRawFramesRenderUprightThroughTheGraph() async throws {
        guard let directory = rawFixtureDirectory() else {
            throw XCTSkip("no RAW fixture folder — see rawFixtureDirectory()")
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let raws = contents
            .filter { $0.pathExtension.uppercased() == "ARW" }
            .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1_000_000 }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(raws.isEmpty, "no .ARW frames in LUMINA_RAW_DIR")

        var checkedPortrait = 0
        var checkedAgainstReference = 0
        for url in raws.prefix(6) {
            let file = try XCTUnwrap(
                OrientedDisplayImage.fileOrientation(at: url),
                "\(url.lastPathComponent): no orientation metadata"
            )
            let result = await renderThroughGraph(url, quality: .settled)
            let image = try XCTUnwrap(
                result.ciImage,
                "\(url.lastPathComponent): the graph produced no image"
            )

            let oriented = file.orientedSize
            let expectedAspect = Double(oriented.width) / Double(oriented.height)
            let presentedAspect = Double(image.extent.width / image.extent.height)
            XCTAssertEqual(
                presentedAspect, expectedAspect, accuracy: 0.01,
                "\(url.lastPathComponent): presented \(image.extent.size) for a file "
                    + "whose oriented size is \(oriented.width)×\(oriented.height)"
            )
            if expectedAspect < 1 { checkedPortrait += 1 }

            let probe = try XCTUnwrap(
                PhotoPresentProof.probe(image, drawableSize: drawable),
                "\(url.lastPathComponent): nothing reached the drawable"
            )
            XCTAssertFalse(
                probe.isBlank,
                "\(url.lastPathComponent): drew a blank frame — coverage "
                    + "\(probe.coverage), contrast \(probe.contrast)"
            )

            // Second opinion. ImageIO orients the embedded preview itself and
            // never touches `CIRAWFilter`, so if the RAW path ever hands back
            // sensor-space pixels — the hole `OrientationContractTests` names —
            // the two disagree about which way up the photograph is.
            if let reference = referenceProbe(for: url) {
                assertSameWayUp(probe, reference, file: url.lastPathComponent)
                checkedAgainstReference += 1
            }
        }

        XCTAssertGreaterThan(
            checkedPortrait, 0,
            "no portrait frame in the fixture folder, so a swapped aspect would "
                + "not have been caught"
        )
        XCTAssertGreaterThan(
            checkedAgainstReference, 0,
            "no frame could be compared against its ImageIO preview, so nothing "
                + "here would have caught the RAW path turning a photograph over"
        )
    }

    /// Every tier must present the photograph the same way up.
    ///
    /// This is the flip the user reported, and it was in neither of the places the
    /// backlog looked. The interactive tier evaluates the RAW graph into an
    /// `MTLTexture` and wraps it with `CIImage(mtlTexture:)`, which reads the
    /// texture's rows as Core Image's own bottom-up rows. The render into that
    /// texture was flipped on the assumption that the wrap would flip back, so
    /// every frame arrived upside down the moment it was opened and righted itself
    /// only when the settled render replaced it.
    ///
    /// Settled is the reference for what the frame should look like, and ImageIO's
    /// own preview is the second opinion that keeps settled honest.
    func testEveryTierPresentsTheSameWayUp() async throws {
        guard let directory = rawFixtureDirectory() else {
            throw XCTSkip("no RAW fixture folder")
        }
        let raws = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.uppercased() == "ARW" }
        .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1_000_000 }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(raws.isEmpty, "no .ARW frames in the fixture folder")

        var compared = 0
        for url in raws.prefix(4) {
            let name = url.lastPathComponent
            let reference = try XCTUnwrap(referenceProbe(for: url), "\(name): no preview")

            for quality in [DevelopRenderQuality.interactive, .settled] {
                let result = await renderThroughGraph(url, quality: quality)
                let image = try XCTUnwrap(
                    result.ciImage,
                    "\(name) \(quality.rawValue): the graph produced no image"
                )
                let probe = try XCTUnwrap(
                    PhotoPresentProof.probe(image, drawableSize: drawable),
                    "\(name) \(quality.rawValue): nothing reached the drawable"
                )
                XCTAssertFalse(probe.isBlank, "\(name) \(quality.rawValue): blank frame")
                assertSameWayUp(probe, reference, file: "\(name) \(quality.rawValue)")
                compared += 1
            }
        }

        XCTAssertGreaterThan(compared, 0, "no frame was compared at any tier")
    }

    /// The same frame as ImageIO orients it, measured the same way.
    private func referenceProbe(for url: URL) -> PhotoPresentProof.Probe? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
              ] as CFDictionary) else { return nil }
        return PhotoPresentProof.probe(
            CIImage(cgImage: thumbnail),
            drawableSize: drawable
        )
    }

    /// Compare which half is brighter, vertically and horizontally.
    ///
    /// Absolute luminance is not comparable — one side is a camera-tonemapped
    /// preview, the other a demosaic — but a photograph that is upside down or
    /// mirrored flips the sign of these differences. Halves that are too evenly
    /// lit to carry a sign are skipped rather than guessed at.
    private func assertSameWayUp(
        _ probe: PhotoPresentProof.Probe,
        _ reference: PhotoPresentProof.Probe,
        file: String
    ) {
        func vertical(_ p: PhotoPresentProof.Probe) -> Double {
            (p.quadrants[0] + p.quadrants[1]) - (p.quadrants[2] + p.quadrants[3])
        }
        func horizontal(_ p: PhotoPresentProof.Probe) -> Double {
            (p.quadrants[0] + p.quadrants[2]) - (p.quadrants[1] + p.quadrants[3])
        }

        // Half a stop of separation between halves, on a 0…1 luminance scale.
        let decisive = 0.06
        if abs(vertical(reference)) > decisive {
            XCTAssertEqual(
                vertical(probe) > 0, vertical(reference) > 0,
                "\(file): the render path and ImageIO disagree about which half is "
                    + "the top — presented \(probe.quadrants), preview \(reference.quadrants)"
            )
        }
        if abs(horizontal(reference)) > decisive {
            XCTAssertEqual(
                horizontal(probe) > 0, horizontal(reference) > 0,
                "\(file): the render path and ImageIO disagree about which half is "
                    + "the left — presented \(probe.quadrants), preview \(reference.quadrants)"
            )
        }
    }
}
