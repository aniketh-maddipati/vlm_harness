import AppKit
import XCTest
@testable import Lumina

/// P2 item 5 — one bounded, distance-ordered queue for every grid-tier miss.
/// A request that leaves the window, or loses its last waiter, before its
/// decode starts is dropped there and counted, the way the develop scheduler
/// counts `stale` and `cancel`.
final class BrowsePixelGridQueueTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grid-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Big enough that a decode takes a few milliseconds, so a width-1 queue
    /// actually queues.
    private func writeJPEG(named name: String) throws -> String {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1600, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedHue: CGFloat(abs(name.hashValue) % 100) / 100, saturation: 0.7, brightness: 0.7, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 2400, height: 1600).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        let url = directory.appendingPathComponent("\(name).jpg")
        try data.write(to: url)
        return url.path
    }

    private func settle(_ service: BrowsePixelService, timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let d = await service.diagnostics()
            if d.gridQueued == 0, d.gridActive == 0, d.floorQueued == 0 { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testAWindowThatMovesOnDropsWhatItQueuedBeforeItStarted() async throws {
        let paths = try (0..<12).map { try writeJPEG(named: "w\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 0, gridDecodeWidth: 1)
        await service.setScrollOrder(paths: paths)

        // Ten ahead, one at a time. Then the window moves elsewhere before
        // most of them ran.
        await service.setGridPrefetchWindow(ahead: Array(paths[0..<10]), keep: Set(paths[0..<10]))
        await service.setGridPrefetchWindow(ahead: [paths[11]], keep: [paths[11]])
        await settle(service)

        let d = await service.diagnostics()
        XCTAssertGreaterThanOrEqual(d.gridStale, 7, "most of the first window never cost a decode")
        XCTAssertTrue(service.isResident(path: paths[11], tier: .grid), "the new window is served")
        XCTAssertLessThanOrEqual(d.gridStarted, 4)
    }

    func testACancelledWaiterWithdrawsItsRequest() async throws {
        let paths = try (0..<6).map { try writeJPEG(named: "c\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 0, gridDecodeWidth: 1)
        await service.setScrollOrder(paths: paths)
        await service.setViewportCenter(index: 0)

        // Five tiles ahead of the farthest one in a width-1 queue, so the
        // farthest cannot have started when its tile disappears.
        let ahead = (0..<5).map { index in Task { await service.image(path: paths[index], tier: .grid) } }
        let farthest = Task { await service.image(path: paths[5], tier: .grid) }
        // Let the waiter register before cancelling it.
        var registered = false
        for _ in 0..<200 where !registered {
            let d = await service.diagnostics()
            registered = d.gridQueued + d.gridActive >= 6
            if !registered { try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        XCTAssertTrue(registered)
        farthest.cancel()
        let cancelledResult = await farthest.value
        for task in ahead { _ = await task.value }
        await settle(service)

        let d = await service.diagnostics()
        XCTAssertNil(cancelledResult)
        XCTAssertEqual(d.gridCancelled, 1)
        XCTAssertFalse(service.isResident(path: paths[5], tier: .grid), "never decoded")
        XCTAssertTrue(service.isResident(path: paths[0], tier: .grid))
    }

    func testConcurrentAsksForOnePathShareOneDecode() async throws {
        let path = try writeJPEG(named: "shared")
        let service = BrowsePixelService(floorBudgetBytes: 0, gridDecodeWidth: 2)
        async let a = service.image(path: path, tier: .grid)
        async let b = service.image(path: path, tier: .grid)
        async let c = service.image(path: path, tier: .grid)
        let results = await [a, b, c]
        XCTAssertEqual(results.compactMap { $0 }.count, 3)
        let d = await service.diagnostics()
        XCTAssertEqual(d.gridStarted, 1)
        XCTAssertEqual(d.cacheMisses, 1)
    }

    func testAWaitingTileGoesAheadOfTheWindow() async throws {
        let paths = try (0..<6).map { try writeJPEG(named: "p\($0)") }
        let service = BrowsePixelService(floorBudgetBytes: 0, gridDecodeWidth: 1)
        await service.setScrollOrder(paths: paths)
        await service.setViewportCenter(index: 0)
        // Window queues 1…4 (nearest first); a tile then asks for 5, the
        // farthest. The tile is served before the rest of the window.
        await service.setGridPrefetchWindow(ahead: Array(paths[1...4]), keep: Set(paths[1...5]))
        let tile = Task { await service.image(path: paths[5], tier: .grid) }
        _ = await tile.value
        let d = await service.diagnostics()
        XCTAssertLessThanOrEqual(d.gridStarted, 3, "the tile did not wait behind four prefetches")
        await settle(service)
    }
}
