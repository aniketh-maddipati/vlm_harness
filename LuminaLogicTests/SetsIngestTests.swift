import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// The native reader behind the page's folder open: what it lists, what it reads, what it refuses,
/// and that a pulled card stops it.
final class SetsIngestTests: XCTestCase {
    private var dir: URL!
    private var root: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-ingest-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("100MSDCF"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func put(_ rel: String, _ data: Data) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A small JPEG, `w`×`h`, left half black and right half white (so a quarter turn is visible).
    private func jpeg(_ w: Int, _ h: Int) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func size(_ jpeg: Data) -> (Int, Int) {
        let src = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        return (img.width, img.height)
    }

    func testListingIsRecursiveSkipsHiddenAndStubsAndReadsSidecars() throws {
        try put("100MSDCF/DSC00001.ARW", Data(count: 10))
        try put("100MSDCF/DSC00002.arw", Data(count: 20))
        try put("100MSDCF/DSC00001.xmp", Data("<x:xmpmeta/>".utf8))
        try put("100MSDCF/._DSC00001.ARW", Data(count: 4))
        try put("100MSDCF/.DS_Store", Data(count: 4))
        try put("100MSDCF/IMG_0001.CR3", Data(count: 4))
        let l = SetsIngest.list(root)
        XCTAssertEqual(l.name, "shoot")
        XCTAssertEqual(l.files.map(\.rel).sorted(), ["shoot/100MSDCF/DSC00001.ARW", "shoot/100MSDCF/DSC00002.arw"])
        XCTAssertEqual(l.files.first { $0.rel.hasSuffix("2.arw") }?.size, 20)
        XCTAssertEqual(l.xmp.map(\.rel), ["shoot/100MSDCF/DSC00001.xmp"])
        XCTAssertEqual(l.xmp.first?.text, "<x:xmpmeta/>")
    }

    func testHeadIsTheFirst256KBAndShortFilesComeBackWhole() throws {
        let big = Data((0..<400_000).map { UInt8($0 % 251) })
        try put("100MSDCF/BIG.ARW", big)
        try put("100MSDCF/SMALL.ARW", Data([1, 2, 3]))
        let ingest = SetsIngest(workers: 2)
        ingest.register(root)
        XCTAssertEqual(try ingest.head("shoot/100MSDCF/BIG.ARW"), big.prefix(SetsIngest.headBytes))
        XCTAssertEqual(try ingest.head("shoot/100MSDCF/SMALL.ARW"), Data([1, 2, 3]))
        XCTAssertEqual(ingest.snapshot.bytesRead, Int64(SetsIngest.headBytes + 3), "only the heads were read")
    }

    func testPreviewIsReadByByteRangeAndTurnedUpright() throws {
        let jpg = jpeg(64, 32)
        var raw = Data(count: 1000); raw.append(jpg); raw.append(Data(count: 5000))
        try put("100MSDCF/DSC00001.ARW", raw)
        let ingest = SetsIngest(workers: 2)
        ingest.register(root)
        let as1 = try ingest.preview(.init(rel: "shoot/100MSDCF/DSC00001.ARW", offset: 1000, length: jpg.count, orientation: 1))
        XCTAssertEqual(as1, jpg, "orientation 1: the embedded bytes as stored")
        let as6 = try ingest.preview(.init(rel: "shoot/100MSDCF/DSC00001.ARW", offset: 1000, length: jpg.count, orientation: 6))
        XCTAssertTrue(size(as6) == (32, 64), "orientation 6 comes back portrait")
        // Asking again is a cache hit, not another read.
        let before = ingest.snapshot.bytesRead
        _ = try ingest.preview(.init(rel: "shoot/100MSDCF/DSC00001.ARW", offset: 1000, length: jpg.count, orientation: 6))
        XCTAssertEqual(ingest.snapshot.bytesRead, before)
    }

    func testAPreviewPastTheEndOfTheFileIsRefused() throws {
        try put("100MSDCF/CUT.ARW", Data(count: 4096))
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        XCTAssertThrowsError(try ingest.preview(.init(rel: "shoot/100MSDCF/CUT.ARW", offset: 3000, length: 5000, orientation: 1)))
    }

    func testPathsOutsideAnOpenedFolderAreRefused() throws {
        try Data("secret".utf8).write(to: dir.appendingPathComponent("outside.ARW"))
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        XCTAssertNil(ingest.resolve("shoot/../outside.ARW"))
        XCTAssertNil(ingest.resolve("other/DSC00001.ARW"))
        XCTAssertThrowsError(try ingest.head("shoot/../outside.ARW"))
    }

    func testAPulledCardStopsEveryReadWithoutOpeningFiles() throws {
        try put("100MSDCF/DSC00001.ARW", Data(count: 1000))
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        XCTAssertEqual(ingest.markGone(volume: dir), ["shoot"])
        XCTAssertThrowsError(try ingest.head("shoot/100MSDCF/DSC00001.ARW")) { e in
            XCTAssertEqual((e as? SetsIngest.Failure)?.kind, .gone)
        }
        XCTAssertEqual(ingest.snapshot.opensAfterGone, 0)
        XCTAssertEqual(ingest.snapshot.bytesRead, 0)
        // Same card back at the same place: its folder reads again.
        XCTAssertEqual(ingest.revive(volume: dir), ["shoot"])
        XCTAssertEqual(try ingest.head("shoot/100MSDCF/DSC00001.ARW").count, 1000)
    }

    func testAFolderThatVanishesMidReadIsReportedGone() throws {
        try put("100MSDCF/DSC00001.ARW", Data(count: 1000))
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        try FileManager.default.removeItem(at: root)
        XCTAssertThrowsError(try ingest.head("shoot/100MSDCF/DSC00001.ARW")) { e in
            XCTAssertEqual((e as? SetsIngest.Failure)?.kind, .gone)
        }
        XCTAssertEqual(ingest.snapshot.gone, ["shoot"])
    }

    func testPrivatePrefixDoesNotHideAVolume() {
        XCTAssertEqual(SetsIngest.plainPath(URL(fileURLWithPath: "/private/tmp/x/LTCARD")), "/tmp/x/LTCARD")
        XCTAssertEqual(SetsIngest.plainPath(URL(fileURLWithPath: "/Volumes/Untitled/")), "/Volumes/Untitled")
    }
}
