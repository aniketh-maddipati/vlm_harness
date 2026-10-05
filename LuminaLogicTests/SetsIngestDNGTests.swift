import Foundation
import XCTest
@testable import Lumina

/// Phone DNGs take the same native listing path as Sony ARWs. Classification as a phone remains
/// the page's job, from EXIF Make/Model rather than the file extension.
final class SetsIngestDNGTests: XCTestCase {
    private var dir: URL!
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-ingest-dng-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("shoot", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func put(_ rel: String, _ data: Data) throws {
        let url = root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func testDNGsAreListedLikeARWsWithoutChangingSidecarsOrOtherFiles() throws {
        try put("A.ARW", Data(repeating: 0x01, count: 11))
        try put("b.dng", Data(repeating: 0x02, count: 22))
        try put("C.DNG", Data(repeating: 0x03, count: 33))
        try put("d.jpg", Data(repeating: 0x04, count: 44))
        try put("e.heic", Data(repeating: 0x05, count: 55))
        try put("A.xmp", Data("<x:a/>".utf8))
        try put("c.xmp", Data("<x:c/>".utf8))
        try put("._b.dng", Data(repeating: 0x06, count: 66))
        try put("b.dng.lumina-bak", Data(repeating: 0x07, count: 77))
        try put("sub/f.DNG", Data(repeating: 0x08, count: 88))

        let listing = SetsIngest.list(root)
        let files = listing.files.sorted { $0.rel < $1.rel }

        XCTAssertNil(listing.stopped)
        XCTAssertEqual(files.map(\.rel), [
            "shoot/A.ARW",
            "shoot/C.DNG",
            "shoot/b.dng",
            "shoot/sub/f.DNG",
        ])
        XCTAssertEqual(files.map(\.size), [11, 33, 22, 88])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: listing.xmp.map { ($0.rel, $0.text) }),
            ["shoot/A.xmp": "<x:a/>", "shoot/c.xmp": "<x:c/>"]
        )
        XCTAssertEqual(Set(listing.others), ["shoot/d.jpg", "shoot/e.heic"])
        XCTAssertFalse(listing.files.contains { $0.rel.contains("._") || $0.rel.hasSuffix(".lumina-bak") })
        XCTAssertFalse(listing.others.contains { $0.contains("._") || $0.hasSuffix(".lumina-bak") })
    }

    func testEntryLimitStillRefusesTheWholeListingWithDNGs() throws {
        try put("A.DNG", Data(count: 1))
        try put("B.dng", Data(count: 2))
        var limits = SetsIngest.Limits()
        limits.entries = 1

        let stopped = SetsIngest.list(root, limits: limits)

        XCTAssertEqual(stopped.stopped, .tooManyFiles)
        XCTAssertTrue(stopped.files.isEmpty)
        limits.entries = 2
        let complete = SetsIngest.list(root, limits: limits)
        XCTAssertNil(complete.stopped)
        XCTAssertEqual(Set(complete.files.map(\.rel)), ["shoot/A.DNG", "shoot/B.dng"])
    }

    func testDepthLimitStillRefusesTheWholeListingWithDNGs() throws {
        try put("A.DNG", Data(count: 1))
        try put("d1/d2/B.dng", Data(count: 2))
        var limits = SetsIngest.Limits()
        limits.depth = 1

        let stopped = SetsIngest.list(root, limits: limits)

        XCTAssertEqual(stopped.stopped, .tooDeep)
        XCTAssertTrue(stopped.files.isEmpty)
        limits.depth = 2
        let complete = SetsIngest.list(root, limits: limits)
        XCTAssertNil(complete.stopped)
        XCTAssertEqual(Set(complete.files.map(\.rel)), ["shoot/A.DNG", "shoot/d1/d2/B.dng"])
    }
}
