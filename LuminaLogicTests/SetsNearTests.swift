import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import Lumina

/// `lumina.near`: the distance between two photos' embedded previews (DESIGN-ASKS Prompt 2 C).
/// The arithmetic, the threshold's tie to the feature print revision and the cache are checked
/// everywhere; the tests that need Vision say so and skip where it can't run.
final class SetsNearTests: XCTestCase {
    private var dir: URL!
    private var root: URL!
    private var ingest: SetsIngest!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-near-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ingest = SetsIngest(workers: 2)
        ingest.register(root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: Fixtures

    private enum Scene { case hills, stripes }

    /// A picture with enough in it for a feature print: `hills` (sky, ground, a sun) moved sideways
    /// by `shift` of its width, or `stripes` (another picture altogether).
    private func picture(_ scene: Scene, shift: CGFloat = 0, w: Int = 600, h: Int = 400) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let W = CGFloat(w), H = CGFloat(h), dx = shift * W
        switch scene {
        case .hills:
            ctx.setFillColor(CGColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(CGColor(red: 0.20, green: 0.55, blue: 0.25, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -0.2 * W + dx, y: -0.55 * H, width: 0.9 * W, height: H))
            ctx.setFillColor(CGColor(red: 0.15, green: 0.40, blue: 0.20, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 0.4 * W + dx, y: -0.6 * H, width: 0.9 * W, height: H))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 0.68 * W + dx, y: 0.62 * H, width: 0.14 * W, height: 0.14 * W))
        case .stripes:
            ctx.setFillColor(CGColor(red: 0.12, green: 0.10, blue: 0.14, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            for i in 0..<9 {
                ctx.setFillColor(CGColor(red: i % 2 == 0 ? 0.9 : 0.6, green: 0.2, blue: i % 3 == 0 ? 0.7 : 0.1, alpha: 1))
                ctx.fill(CGRect(x: CGFloat(i) * W / 9 + 6, y: 0.1 * H, width: W / 9 - 12, height: 0.8 * H))
            }
        }
        return ctx.makeImage()!
    }

    /// The image turned a quarter turn, as a camera held upright stores it (EXIF orientation 6
    /// turns it back).
    private func stored(forOrientation6 image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.translateBy(x: CGFloat(h) / 2, y: CGFloat(w) / 2)
        ctx.rotate(by: .pi / 2)
        ctx.draw(image, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()!
    }

    private func jpeg(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// A stand-in ARW: 64 bytes, then the preview. Returns where the preview is.
    private func put(_ name: String, _ image: CGImage, orientation: Int = 1) throws -> SetsIngest.Preview {
        let j = jpeg(image)
        try (Data(count: 64) + j).write(to: root.appendingPathComponent(name))
        return SetsIngest.Preview(rel: "shoot/\(name)", offset: 64, length: j.count, orientation: orientation)
    }

    private func needVision() throws {
        try XCTSkipIf(SetsNear.featurePrint(picture(.hills)) == nil, "Vision makes no feature print on this machine: the measure itself is not checked here")
    }

    // MARK: No Vision needed

    func testDistanceIsEuclidean() {
        XCTAssertEqual(SetsNear.distance([0, 0, 0], [0, 0, 0]), 0)
        XCTAssertEqual(SetsNear.distance([1, 2, 2], [1, 2, 2]), 0)
        XCTAssertEqual(SetsNear.distance([0, 0], [3, 4])!, 5, accuracy: 1e-9)
        XCTAssertEqual(SetsNear.distance([0.5, -0.5], [-0.5, 0.5])!, 2.0.squareRoot(), accuracy: 1e-6)
        XCTAssertNil(SetsNear.distance([1, 2], [1, 2, 3]), "vectors of two revisions never compare")
        XCTAssertNil(SetsNear.distance([], []))
    }

    func testTheThresholdBelongsToTheRevisionItWasMeasuredWith() {
        XCTAssertEqual(SetsNear.revision, VNGenerateImageFeaturePrintRequestRevision2)
        XCTAssertEqual(SetsNear.limit(for: VNGenerateImageFeaturePrintRequestRevision2), 0.35)
        XCTAssertNil(SetsNear.limit(for: VNGenerateImageFeaturePrintRequestRevision1))
        XCTAssertNil(SetsNear.limit(for: VNGenerateImageFeaturePrintRequestRevision2 + 1), "a newer revision has no threshold until someone measures one")
        XCTAssertEqual(SetsNear.limit, 0.35)
    }

    func testThePageNamesAPreviewWithNumbersOrStrings() {
        let a = SetsBridge.ingestPreview(["p": "shoot/DSC1.ARW", "o": 64, "l": 1000, "ori": 6])
        XCTAssertEqual(a, SetsIngest.Preview(rel: "shoot/DSC1.ARW", offset: 64, length: 1000, orientation: 6))
        XCTAssertEqual(SetsBridge.ingestPreview(["p": "shoot/DSC1.ARW", "o": "64", "l": "1000", "ori": "6"]), a)
        XCTAssertEqual(SetsBridge.ingestPreview(["p": "shoot/DSC1.ARW"])?.orientation, 1)
        XCTAssertNil(SetsBridge.ingestPreview(["o": 64, "l": 1000]))
        XCTAssertNil(SetsBridge.ingestPreview(nil))
    }

    func testAPhotoThatCannotBeReadHasNoDistance() async throws {
        let near = SetsNear(ingest: ingest)
        let a = try put("DSC1.ARW", picture(.hills))
        let d1 = await near.distance(a, SetsIngest.Preview(rel: "shoot/NOPE.ARW", offset: 64, length: 100, orientation: 1))
        XCTAssertNil(d1, "a file that isn't there")
        let d2 = await near.distance(a, SetsIngest.Preview(rel: "shoot/DSC1.ARW", offset: 0, length: 0, orientation: 1))
        XCTAssertNil(d2, "a photo with no preview range")
        let d3 = await near.distance(a, SetsIngest.Preview(rel: "elsewhere/DSC1.ARW", offset: 64, length: 100, orientation: 1))
        XCTAssertNil(d3, "a folder that was never opened")
    }

    func testAPulledCardStopsTheMeasure() async throws {
        let near = SetsNear(ingest: ingest)
        let a = try put("DSC1.ARW", picture(.hills)), b = try put("DSC2.ARW", picture(.stripes))
        ingest.markGone(volume: dir)
        let d = await near.distance(a, b)
        XCTAssertNil(d)
        XCTAssertEqual(ingest.snapshot.opensAfterGone, 0, "nothing is opened on a card that is out")
        XCTAssertEqual(near.count, 0)
    }

    // MARK: The measure (Vision)

    func testTheSamePictureMovedALittleIsNearerThanAnotherPicture() async throws {
        try needVision()
        let near = SetsNear(ingest: ingest)
        let a = try put("DSC1.ARW", picture(.hills)), again = try put("DSC2.ARW", picture(.hills, shift: 0.03)), other = try put("DSC3.ARW", picture(.stripes))
        let same = await near.distance(a, a), retake = await near.distance(a, again), different = await near.distance(a, other)
        XCTAssertEqual(same, 0)
        let r = try XCTUnwrap(retake), d = try XCTUnwrap(different)
        XCTAssertGreaterThan(r, 0)
        XCTAssertLessThan(r, d, "a retake is nearer than another picture")
        let back = await near.distance(again, a)
        XCTAssertEqual(back, r, "the distance has no direction")
    }

    func testEachPhotoIsMeasuredOnceHoweverManyPairsAsk() async throws {
        try needVision()
        let near = SetsNear(ingest: ingest)
        let p = [try put("DSC1.ARW", picture(.hills)), try put("DSC2.ARW", picture(.hills, shift: 0.02)), try put("DSC3.ARW", picture(.stripes))]
        async let d01 = near.distance(p[0], p[1]), d12 = near.distance(p[1], p[2]), d02 = near.distance(p[0], p[2]), d10 = near.distance(p[1], p[0])
        let all = await [d01, d12, d02, d10]
        XCTAssertTrue(all.allSatisfy { $0 != nil })
        XCTAssertEqual(near.measured, 3, "three photos, three measures, for four pairs asked at once")
        XCTAssertEqual(near.count, 3)
    }

    func testTheCacheHoldsNoMoreThanItsCapacity() async throws {
        try needVision()
        let near = SetsNear(ingest: ingest, capacity: 2)
        let p = [try put("DSC1.ARW", picture(.hills)), try put("DSC2.ARW", picture(.hills, shift: 0.02)), try put("DSC3.ARW", picture(.stripes))]
        _ = await near.distance(p[0], p[1])
        _ = await near.distance(p[1], p[2])
        XCTAssertEqual(near.count, 2)
        XCTAssertEqual(near.measured, 3)
        _ = await near.distance(p[0], p[1])
        XCTAssertEqual(near.measured, 4, "the oldest was dropped and is measured again when asked for")
    }

    func testAPhotoTakenUprightIsMeasuredUpright() async throws {
        try needVision()
        let near = SetsNear(ingest: ingest)
        let upright = picture(.hills, w: 400, h: 600)
        let a = try put("DSC1.ARW", upright)
        let turned = try put("DSC2.ARW", stored(forOrientation6: upright), orientation: 6)
        let asStored = SetsIngest.Preview(rel: turned.rel, offset: turned.offset, length: turned.length, orientation: 1)
        let d = await near.distance(a, turned), dStored = await near.distance(a, asStored)
        let withTurn = try XCTUnwrap(d), without = try XCTUnwrap(dStored)
        XCTAssertLessThan(withTurn, without, "turned upright, the photo matches its upright twin; left as stored it doesn't")
        XCTAssertLessThan(withTurn, SetsNear.limit ?? 0.35, "the same picture, saved twice")
    }
}
