import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lumina

/// A cache that keeps everything it is given. The reader's own NSCache may drop an entry at any
/// moment under memory pressure (seen with the whole logic suite running: the head was gone between
/// `head` and `preview`, so the "not read twice" counts were off). What the reader does with an
/// entry it still holds is tested with this one; what it does without, with `DroppingCache`.
private final class KeepingCache: NSCache<NSString, NSData>, @unchecked Sendable {
    private var held: [NSString: NSData] = [:]
    private let lock = NSLock()
    override func object(forKey key: NSString) -> NSData? { lock.withLock { held[key] } }
    override func setObject(_ obj: NSData, forKey key: NSString) { lock.withLock { held[key] = obj } }
    override func setObject(_ obj: NSData, forKey key: NSString, cost g: Int) { lock.withLock { held[key] = obj } }
    override func removeObject(forKey key: NSString) { lock.withLock { held[key] = nil } }
    override func removeAllObjects() { lock.withLock { held.removeAll() } }
}

/// A cache under the worst memory pressure: it holds nothing.
private final class DroppingCache: NSCache<NSString, NSData>, @unchecked Sendable {
    override func object(forKey key: NSString) -> NSData? { nil }
    override func setObject(_ obj: NSData, forKey key: NSString) {}
    override func setObject(_ obj: NSData, forKey key: NSString, cost g: Int) {}
}

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

    /// A reader whose caches hold (see `KeepingCache`).
    private func reader(workers: Int) -> SetsIngest { SetsIngest(workers: workers, previews: KeepingCache(), heads: KeepingCache()) }

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
        let ingest = reader(workers: 2)
        ingest.register(root)
        XCTAssertEqual(try ingest.head("shoot/100MSDCF/BIG.ARW"), big.prefix(SetsIngest.headBytes))
        XCTAssertEqual(try ingest.head("shoot/100MSDCF/SMALL.ARW"), Data([1, 2, 3]))
        XCTAssertEqual(ingest.snapshot.bytesRead, Int64(SetsIngest.headBytes + 3), "only the heads were read")
    }

    func testPreviewIsReadByByteRangeAndTurnedUpright() throws {
        let jpg = jpeg(64, 32)
        var raw = Data(count: 1000); raw.append(jpg); raw.append(Data(count: 5000))
        try put("100MSDCF/DSC00001.ARW", raw)
        let ingest = reader(workers: 2)
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

    func testAPreviewThatStartsInsideTheHeadIsNotReadFromTheCardTwice() throws {
        // A Sony ARW: the preview starts at about 130 KB, so the 256 KB head already holds its start.
        let raw = Data((0..<600_000).map { UInt8(($0 &* 31 &+ $0 / 7) % 251) })
        try put("100MSDCF/DSC00001.ARW", raw)
        let rel = "shoot/100MSDCF/DSC00001.ARW", head = SetsIngest.headBytes
        let ingest = reader(workers: 2)
        ingest.register(root)
        _ = try ingest.head(rel)
        let pv = try ingest.preview(.init(rel: rel, offset: 130_000, length: 400_000, orientation: 1))
        XCTAssertEqual(pv, raw.subdata(in: 130_000..<530_000), "the same bytes as one read of the range")
        XCTAssertEqual(ingest.snapshot.bytesRead, 530_000, "the file's first 530 KB, each byte once")
        XCTAssertEqual(ingest.snapshot.bytesFromHead, Int64(head - 130_000))
        // A preview that lies wholly inside the head costs no read at all.
        let before = ingest.snapshot.bytesRead
        XCTAssertEqual(try ingest.preview(.init(rel: rel, offset: 1000, length: 5000, orientation: 1)), raw.subdata(in: 1000..<6000))
        XCTAssertEqual(ingest.snapshot.bytesRead, before)
        // Without its head (another card under the same folder name, or long after the read): the whole range.
        ingest.register(root)
        XCTAssertEqual(try ingest.preview(.init(rel: rel, offset: 140_000, length: 300_000, orientation: 1)), raw.subdata(in: 140_000..<440_000))
        XCTAssertEqual(ingest.snapshot.bytesRead, before + 300_000)
    }

    func testACacheThatDropsEverythingCostsReadsNeverBytes() throws {
        // Memory pressure at its worst: nothing read is held. Every ask goes to the card and gives the same bytes.
        let jpg = jpeg(64, 32)
        var raw = Data((0..<130_000).map { UInt8($0 % 251) }); raw.append(jpg); raw.append(Data(count: 300_000))
        try put("100MSDCF/DSC00001.ARW", raw)
        let rel = "shoot/100MSDCF/DSC00001.ARW"
        let ingest = SetsIngest(workers: 2, previews: DroppingCache(), heads: DroppingCache())
        ingest.register(root)
        XCTAssertEqual(try ingest.head(rel), raw.prefix(SetsIngest.headBytes))
        let p = SetsIngest.Preview(rel: rel, offset: 130_000, length: jpg.count, orientation: 1)
        XCTAssertEqual(try ingest.preview(p), jpg, "the head is gone: the whole range comes off the card")
        XCTAssertEqual(try ingest.preview(p), jpg)
        XCTAssertTrue(size(try ingest.thumb(p)) == (64, 32))
        XCTAssertTrue(size(try ingest.preview(.init(rel: rel, offset: 130_000, length: jpg.count, orientation: 6))) == (32, 64))
        let s = ingest.snapshot
        XCTAssertEqual(s.bytesRead, Int64(SetsIngest.headBytes + 4 * jpg.count), "the head once, the preview range four times")
        XCTAssertEqual(s.bytesFromHead, 0)
        XCTAssertEqual(s.cacheHits, 0)
        // A pulled card is still refused when nothing is held.
        XCTAssertFalse(ingest.markGone(volume: dir).isEmpty)
        XCTAssertThrowsError(try ingest.preview(p))
    }

    func testAPreviewInsideTheHeadOfAPulledCardIsRefused() throws {
        try put("100MSDCF/DSC00001.ARW", Data(count: 300_000))
        let rel = "shoot/100MSDCF/DSC00001.ARW"
        let ingest = reader(workers: 1)
        ingest.register(root)
        _ = try ingest.head(rel)
        XCTAssertFalse(ingest.markGone(volume: dir).isEmpty)
        XCTAssertThrowsError(try ingest.preview(.init(rel: rel, offset: 1000, length: 5000, orientation: 1)))
    }

    func testThumbCoversTheLargestRetinaTileUprightAndIsNeverUpscaled() throws {
        let big = jpeg(1616, 1080), small = jpeg(640, 427)
        var raw = Data(count: 1000); raw.append(big); raw.append(small); raw.append(Data(count: 5000))
        try put("100MSDCF/DSC00001.ARW", raw)
        let ingest = reader(workers: 2)
        ingest.register(root)
        let rel = "shoot/100MSDCF/DSC00001.ARW"
        // The page reads the preview as stored first; the thumbnail then comes from the cache.
        _ = try ingest.preview(.init(rel: rel, offset: 1000, length: big.count, orientation: 1))
        let before = ingest.snapshot.bytesRead
        let t1 = try ingest.thumb(.init(rel: rel, offset: 1000, length: big.count, orientation: 1))
        XCTAssertEqual(ingest.snapshot.bytesRead, before, "no second read off the card")
        XCTAssertTrue(size(t1).0 == 720 && (480...482).contains(size(t1).1), "landscape covers 720 × 480: \(size(t1))")
        let t6 = try ingest.thumb(.init(rel: rel, offset: 1000, length: big.count, orientation: 6))
        XCTAssertTrue((320...322).contains(size(t6).0) && size(t6).1 == 480, "portrait fits 480 high, upright: \(size(t6))")
        let ts = try ingest.thumb(.init(rel: rel, offset: 1000 + big.count, length: small.count, orientation: 1))
        XCTAssertTrue(size(ts) == (640, 427), "a small preview is kept at its size: \(size(ts))")
        XCTAssertEqual(ingest.snapshot.thumbs, 3)
    }

    func testAPreviewPastTheEndOfTheFileIsRefused() throws {
        try put("100MSDCF/CUT.ARW", Data(count: 4096))
        let ingest = reader(workers: 1)
        ingest.register(root)
        XCTAssertThrowsError(try ingest.preview(.init(rel: "shoot/100MSDCF/CUT.ARW", offset: 3000, length: 5000, orientation: 1)))
    }

    func testPathsOutsideAnOpenedFolderAreRefused() throws {
        try Data("secret".utf8).write(to: dir.appendingPathComponent("outside.ARW"))
        let ingest = reader(workers: 1)
        ingest.register(root)
        XCTAssertNil(ingest.resolve("shoot/../outside.ARW"))
        XCTAssertNil(ingest.resolve("other/DSC00001.ARW"))
        XCTAssertThrowsError(try ingest.head("shoot/../outside.ARW"))
    }

    /// A file that was renamed or deleted still resolves (so an export can say what happened),
    /// even under /private/tmp where its existing folder's path loses the /private prefix.
    func testAMissingFileStillResolvesInsideItsFolder() throws {
        let ingest = reader(workers: 1)
        ingest.register(root)
        XCTAssertNotNil(ingest.resolve("shoot/100MSDCF/GONE.ARW"))
        XCTAssertNil(ingest.resolve("shoot/100MSDCF/../../GONE.ARW"))
    }

    func testAPulledCardStopsEveryReadWithoutOpeningFiles() throws {
        try put("100MSDCF/DSC00001.ARW", Data(count: 1000))
        let ingest = reader(workers: 1)
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
        let ingest = reader(workers: 1)
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
