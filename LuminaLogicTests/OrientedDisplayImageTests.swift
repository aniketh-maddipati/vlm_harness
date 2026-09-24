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

    func testCanvasSelectionAcceptsIntendedTurnsAndCropsAcrossSourceShapes() throws {
        for size in [CGSize(width: 6000, height: 4000), CGSize(width: 4000, height: 6000),
                     CGSize(width: 4000, height: 4000)] {
            for degrees in [0.0, 90.0, 180.0, 270.0] {
                for crop in [nil, EditCrop(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                             EditCrop(x: 0.1, y: 0.25, width: 0.5, height: 0.7)] {
                    let assetID = UUID()
                    let browse = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: size))
                    let recipe = EditRecipe.neutral.updating {
                        $0.straightenDegrees = degrees
                        $0.crop = crop
                    }
                    let rendered = DevelopRenderGraph.applyGeometry(recipe, to: browse)
                    let candidate = frame(assetID, rendered, recipe)
                    let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: recipe,
                        promoted: candidate, fallback: frame(assetID, browse, nil), retained: nil))
                    XCTAssertTrue(selected.image === rendered, "\(size), \(degrees), \(String(describing: crop))")
                    XCTAssertEqual(selected.recipe?.valueFingerprint, recipe.valueFingerprint)
                }
            }
        }
    }

    func testCanvasSelectionRejectsWrongAssetRecipeAndSensorShape() throws {
        let assetID = UUID()
        let browse = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let recipe = EditRecipe.neutral.updating { $0.straightenDegrees = 90 }
        let rotated = DevelopRenderGraph.applyGeometry(recipe, to: browse)
        let fallback = frame(assetID, browse, nil)
        for candidate in [frame(UUID(), rotated, recipe), frame(assetID, rotated, .neutral),
                          frame(assetID, browse, recipe)] {
            let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: recipe,
                promoted: candidate, fallback: fallback, retained: nil))
            XCTAssertTrue(selected.image === browse)
        }
        XCTAssertNil(OrientedDisplayImage.select(assetID: UUID(), recipe: recipe,
            promoted: nil, fallback: fallback, retained: fallback))
    }

    func testRetainsOnlyPreviouslySelectedSameAssetWhileNewRecipeRenders() throws {
        let assetID = UUID()
        let image = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let previous = frame(assetID, image, .neutral)
        let requested = EditRecipe.neutral.updating { $0.straightenDegrees = 90 }
        let retained = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: requested,
            promoted: previous, fallback: nil, retained: previous))
        XCTAssertTrue(retained.image === image)
        XCTAssertNotEqual(retained.recipe?.valueFingerprint, requested.valueFingerprint)
        let replacement = DevelopRenderGraph.applyGeometry(requested, to: image)
        let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: requested,
            promoted: frame(assetID, replacement, requested), fallback: previous, retained: previous))
        XCTAssertTrue(selected.image === replacement)
    }

    func testUnchangedRecipeKeepsLayoutAcrossTierRoundingIncludingSquare() throws {
        for size in [CGSize(width: 600, height: 400), CGSize(width: 400, height: 600),
                     CGSize(width: 400, height: 400)] {
            let assetID = UUID()
            let browse = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: size))
            let interactive = frame(assetID, browse, .neutral)
            let rounded = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0,
                width: size.width * 2, height: size.height * 2 + 1))
            let selection = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
                promoted: frame(assetID, rounded, .neutral), fallback: frame(assetID, browse, nil), retained: interactive))
            XCTAssertTrue(selection.image === rounded)
            XCTAssertEqual(selection.layoutSize, interactive.layoutSize)
        }
    }

    func testSelectedFrameCannotRegressToOlderGenerationWithSameRecipe() throws {
        let assetID = UUID()
        let oldImage = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let newImage = CIImage(color: .blue).cropped(to: oldImage.extent)
        var old = frame(assetID, oldImage, .neutral)
        old.generation = 4
        var current = frame(assetID, newImage, .neutral)
        current.generation = 5
        let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
            promoted: old, fallback: nil, retained: current))
        XCTAssertTrue(selected.image === newImage)
    }

    func testDecodeGeometryAcceptsObservedRoundedBrowseWithoutChangingLayout() throws {
        let assetID = UUID()
        let browse = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1069))
        for size in [CGSize(width: 2560, height: 1707), CGSize(width: 6000, height: 4000)] {
            let source = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size))
            for degrees in [0.0, 90.0] {
                let recipe = EditRecipe.neutral.updating { $0.straightenDegrees = degrees }
                let rendered = DevelopRenderGraph.applyGeometry(recipe, to: source)
                var candidate = frame(assetID, rendered, recipe)
                candidate.preGeometryExtent = source.extent
                let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: recipe,
                    promoted: candidate, fallback: frame(assetID, browse, nil), retained: nil))
                XCTAssertTrue(selected.image === rendered)
                XCTAssertEqual(selected.layoutSize, DevelopRenderGraph.applyGeometry(recipe, to: browse).extent.size)
            }
        }
    }

    func testDecodeGeometryChecksCropRotationAndFractionalRasterBounds() throws {
        let assetID = UUID()
        let browse = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1069))
        for size in [CGSize(width: 2560, height: 1707), CGSize(width: 1707, height: 2560),
                     CGSize(width: 1400.25, height: 1400.25)] {
            let source = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size))
            for degrees in [0.0, 90.0, 180.0, 270.0, 92.5] {
                for crop in [nil, EditCrop(x: 0.1, y: 0.25, width: 0.5, height: 0.7)] {
                    let recipe = EditRecipe.neutral.updating {
                        $0.straightenDegrees = degrees
                        $0.crop = crop
                    }
                    let rendered = DevelopRenderGraph.applyGeometry(recipe, to: source)
                    var candidate = frame(assetID, rendered, recipe)
                    candidate.preGeometryExtent = source.extent
                    let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: recipe,
                        promoted: candidate, fallback: frame(assetID, browse, nil), retained: nil))
                    XCTAssertTrue(selected.image === rendered)
                }
            }
        }
    }

    func testDecodeGeometryRejectsMislabeledShapeAndInvalidReference() throws {
        let assetID = UUID()
        let reference = CGRect(x: 0, y: 0, width: 2560, height: 1707)
        let browse = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1069))
        let unrotated = CIImage(color: .blue).cropped(to: reference)
        let rotatedRecipe = EditRecipe.neutral.updating { $0.straightenDegrees = 90 }
        let cropRecipe = EditRecipe.neutral.updating { $0.crop = EditCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.7) }
        for recipe in [rotatedRecipe, cropRecipe] {
            var candidate = frame(assetID, unrotated, recipe)
            candidate.preGeometryExtent = reference
            let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: recipe,
                promoted: candidate, fallback: frame(assetID, browse, nil), retained: nil))
            XCTAssertTrue(selected.image === browse)
        }
        for invalid in [CGRect.zero, CGRect.infinite, CGRect.null,
                        CGRect(x: 0, y: 0, width: CGFloat.nan, height: 1707)] {
            var candidate = frame(assetID, unrotated, .neutral)
            candidate.preGeometryExtent = invalid
            XCTAssertNil(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
                promoted: candidate, fallback: nil, retained: nil))
        }
        let missingReference = frame(assetID, unrotated, .neutral)
        let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
            promoted: missingReference, fallback: frame(assetID, browse, nil), retained: nil))
        XCTAssertTrue(selected.image === browse)
    }

    func testDecodeReferenceDoesNotBypassIdentityOrGeneration() throws {
        let assetID = UUID()
        let image = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 2560, height: 1707))
        var previous = frame(assetID, image, .neutral)
        previous.generation = 8
        for candidateAsset in [assetID, UUID()] {
            var candidate = frame(candidateAsset, image, .neutral)
            candidate.preGeometryExtent = image.extent
            candidate.generation = 7
            let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
                promoted: candidate, fallback: nil, retained: previous))
            XCTAssertEqual(selected.generation, 8)
        }
        var candidate = frame(assetID, image, .neutral)
        candidate.preGeometryExtent = image.extent
        let requested = EditRecipe.neutral.updating { $0.exposure = 1 }
        XCTAssertNil(OrientedDisplayImage.select(assetID: assetID, recipe: requested,
            promoted: candidate, fallback: nil, retained: nil))
    }

    func testFreshGraphAndCachePreserveReferenceAndROIUsesLegacyValidation() async throws {
        let url = try writeJPEG(width: 32, height: 16, orientation: 1)
        let assetID = UUID()
        let recipe = EditRecipe.neutral.updating { $0.straightenDegrees = 90 }
        let cache = DevelopPresentationCache()
        for quality in [DevelopRenderQuality.settled, .oneToOne] {
            let request = RawRenderRequest(generation: 1, photoID: assetID, rawURL: url,
                proxyURL: url, recipe: recipe, quality: quality, source: .jpegProxy,
                region: DevelopRenderRegion(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
            let result = await DevelopRenderGraph.render(request)
            let image = try XCTUnwrap(result.ciImage)
            let expected: CGRect? = quality == .oneToOne ? nil : CGRect(x: 0, y: 0, width: 32, height: 16)
            XCTAssertEqual(result.preGeometryExtent, expected)
            await cache.put(key: request.cacheKey, ciImage: image, cgImage: result.cgImage,
                fidelity: result.fidelity, preGeometryExtent: result.preGeometryExtent)
            let entry = await cache.get(request.cacheKey)
            let cached = try XCTUnwrap(entry)
            XCTAssertEqual(cached.preGeometryExtent, expected)
            XCTAssertTrue(cached.ciImage === image)
        }
    }

    @MainActor
    func testWarmedBeforeReplacesAfterWithRoundedBrowseAndKeepsReferenceOnRewarm() async throws {
        let assetID = UUID()
        let scheduler = DevelopRenderScheduler()
        let browse = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1600, height: 1069))
        let size = CGSize(width: 2560, height: 1707)
        let url = try writeJPEG(width: Int(size.width), height: Int(size.height), orientation: 1)
        XCTAssertNil(scheduler.beforeImage(for: assetID))
        XCTAssertNil(scheduler.beforePreGeometryExtent(for: assetID))
        for exposure in [1.0, 2.0] {
            let recipe = EditRecipe.neutral.updating { $0.exposure = exposure }
            await scheduler.warmBeforeAfter(photoID: assetID, rawURL: url, proxyURL: url, recipe: recipe)
            let before = try XCTUnwrap(scheduler.beforeImage(for: assetID))
            let after = try XCTUnwrap(scheduler.afterImage(for: assetID))
            let reference = try XCTUnwrap(scheduler.beforePreGeometryExtent(for: assetID))
            XCTAssertEqual(reference.size, size)
            XCTAssertEqual(before.extent, reference)
            var candidate = frame(assetID, before, .neutral)
            candidate.preGeometryExtent = reference
            let selected = try XCTUnwrap(OrientedDisplayImage.select(assetID: assetID, recipe: .neutral,
                promoted: candidate, fallback: frame(assetID, browse, nil), retained: frame(assetID, after, recipe)))
            XCTAssertTrue(selected.image === before)
            XCTAssertEqual(selected.recipe?.valueFingerprint, EditRecipe.neutral.valueFingerprint)
        }
        let differentAsset = UUID()
        XCTAssertNil(scheduler.beforeImage(for: differentAsset))
        XCTAssertNil(scheduler.beforePreGeometryExtent(for: differentAsset))
    }

    private func frame(_ assetID: UUID, _ image: CIImage, _ recipe: EditRecipe?) -> OrientedDisplayImage.DisplayFrame {
        OrientedDisplayImage.DisplayFrame(assetID: assetID, image: image, recipe: recipe,
            layoutSize: image.extent.size, identity: nil)
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
