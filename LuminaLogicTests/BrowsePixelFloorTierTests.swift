import AppKit
import XCTest
@testable import Lumina

/// The floor tier: a small entry for every frame the viewport can reach,
/// capped by bytes, evicted by distance from the viewport — never by recency.
final class BrowsePixelFloorTierTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floor-tier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A 600×400 JPEG — decodes to 256×171 at the floor, ~175 KB.
    private func writeJPEG(named name: String) throws -> String {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedHue: CGFloat(name.hashValue % 100) / 100, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 600, height: 400).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
        let url = directory.appendingPathComponent("\(name).jpg")
        try data.write(to: url)
        return url.path
    }

    private func settle(_ service: BrowsePixelService, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await service.diagnostics().floorQueued == 0 { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testEveryFrameGetsAFloorEntryWhenTheBudgetAllows() async throws {
        let paths = try (0..<12).map { try writeJPEG(named: "f\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 64 * 1024 * 1024)
        await service.setScrollOrder(paths: paths)
        await settle(service)

        let resident = await service.floorResidentPaths()
        XCTAssertEqual(resident, Set(paths))
        XCTAssertTrue(service.isResident(path: paths[7], tier: .floor))
        XCTAssertFalse(service.isResident(path: paths[7], tier: .grid), "the floor is its own tier")
        let diagnostics = await service.diagnostics()
        XCTAssertEqual(diagnostics.floorResidentCount, 12)
        XCTAssertGreaterThan(diagnostics.floorBytes, 0)
    }

    func testOverBudgetTheFarthestFromTheViewportGoFirst() async throws {
        let paths = try (0..<20).map { try writeJPEG(named: "g\($0)") }
        // Room for about five 256×171 entries. Warm from the top first, the
        // way a fresh open does, then move the viewport to the middle: what
        // was decoded first must not be what survives.
        let service = BrowsePixelService(floorBudgetBytes: 5 * 256 * 171 * 4 + 1024)
        await service.setScrollOrder(paths: paths)
        await settle(service)
        XCTAssertTrue(service.isResident(path: paths[0], tier: .floor), "a fresh open warms the top")

        await service.setViewportCenter(index: 10)
        await settle(service)

        let resident = await service.floorResidentPaths()
        let indices = resident.compactMap { paths.firstIndex(of: $0) }.sorted()
        XCTAssertFalse(indices.isEmpty)
        XCTAssertLessThanOrEqual(indices.count, 6)
        XCTAssertTrue(resident.contains(paths[10]), "the centre is resident")
        let farthestKept = indices.map { abs($0 - 10) }.max() ?? 0
        let nearestEvicted = (0..<20).filter { !resident.contains(paths[$0]) }.map { abs($0 - 10) }.min() ?? 0
        XCTAssertLessThanOrEqual(farthestKept, nearestEvicted + 1,
                                 "nothing kept is farther than something evicted — recency plays no part")
        XCTAssertFalse(resident.contains(paths[0]), "the far end is the first to go")
        XCTAssertFalse(resident.contains(paths[19]))
    }

    func testMovingTheViewportRecentersTheFloor() async throws {
        let paths = try (0..<20).map { try writeJPEG(named: "h\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 5 * 256 * 171 * 4 + 1024)
        await service.setScrollOrder(paths: paths)
        await service.setViewportCenter(index: 2)
        await settle(service)
        XCTAssertTrue(service.isResident(path: paths[2], tier: .floor))

        await service.setViewportCenter(index: 17)
        await settle(service)
        XCTAssertTrue(service.isResident(path: paths[17], tier: .floor), "the new centre is warmed")
        XCTAssertFalse(service.isResident(path: paths[2], tier: .floor), "the old centre is now far and evicted")
    }

    func testANewOrderDropsFramesThatLeftTheShoot() async throws {
        let paths = try (0..<6).map { try writeJPEG(named: "k\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 64 * 1024 * 1024)
        await service.setScrollOrder(paths: paths)
        await settle(service)
        await service.setScrollOrder(paths: Array(paths.prefix(3)))
        await settle(service)
        let resident = await service.floorResidentPaths()
        XCTAssertEqual(resident, Set(paths.prefix(3)))
    }
}
