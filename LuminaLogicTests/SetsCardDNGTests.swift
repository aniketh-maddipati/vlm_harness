import XCTest
@testable import Lumina

/// Card inspection counts every supported RAW format while preserving Sony-folder preference.
@MainActor
final class SetsCardDNGTests: XCTestCase {
    private let fm = FileManager.default
    private var volume: URL!

    override func setUpWithError() throws {
        volume = fm.temporaryDirectory
            .appendingPathComponent("sets-card-dng-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: volume, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: volume)
    }

    @discardableResult
    private func folder(_ relativePath: String) throws -> URL {
        let url = volume.appendingPathComponent(relativePath, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ relativePath: String, bytes: Int) throws {
        let url = volume.appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    func testSonyFolderWithARWs() throws {
        try file("DCIM/100MSDCF/DSC00001.ARW", bytes: 11)
        try file("DCIM/100MSDCF/DSC00002.arw", bytes: 13)

        let card = try XCTUnwrap(SetsCardWatcher.inspect(volume))
        XCTAssertEqual(card.folders.map(\.lastPathComponent), ["100MSDCF"])
        XCTAssertTrue(card.sony)
        XCTAssertEqual(card.arwCount, 2)
        XCTAssertEqual(card.bytes, 24)
    }

    func testSonyFolderCountsARWAndDNG() throws {
        try file("DCIM/100MSDCF/DSC00001.ArW", bytes: 17)
        try file("DCIM/100MSDCF/PHONE0001.dNg", bytes: 19)

        let card = try XCTUnwrap(SetsCardWatcher.inspect(volume))
        XCTAssertTrue(card.sony)
        XCTAssertEqual(card.arwCount, 2)
        XCTAssertEqual(card.bytes, 36)
    }

    func testNonSonyFolderWithDNGsOnly() throws {
        try file("DCIM/100APPLE/IMG_0001.DNG", bytes: 23)
        try file("DCIM/100APPLE/IMG_0002.dng", bytes: 29)

        let card = try XCTUnwrap(SetsCardWatcher.inspect(volume))
        XCTAssertEqual(card.folders.map(\.lastPathComponent), ["100APPLE"])
        XCTAssertTrue(card.sony)
        XCTAssertEqual(card.arwCount, 2)
        XCTAssertEqual(card.bytes, 52)
    }

    func testEmptySonyFolderIsNotSupportedRAWCard() throws {
        try folder("DCIM/100MSDCF")

        let card = try XCTUnwrap(SetsCardWatcher.inspect(volume))
        XCTAssertEqual(card.folders.map(\.lastPathComponent), ["100MSDCF"])
        XCTAssertFalse(card.sony)
        XCTAssertEqual(card.arwCount, 0)
        XCTAssertEqual(card.bytes, 0)
    }

    func testJPEGOnlyCardAndHiddenRAWAreNotCounted() throws {
        try file("DCIM/100APPLE/IMG_0001.JPG", bytes: 31)
        try file("DCIM/100APPLE/.hidden.ARW", bytes: 37)

        let card = try XCTUnwrap(SetsCardWatcher.inspect(volume))
        XCTAssertFalse(card.sony)
        XCTAssertEqual(card.arwCount, 0)
        XCTAssertEqual(card.bytes, 0)
    }

    func testVolumeWithoutDCIMIsNotACard() {
        XCTAssertNil(SetsCardWatcher.inspect(volume))
    }
}
