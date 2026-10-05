import XCTest
@testable import Lumina

/// AirDrop completeness rules run against a fake clock; only the final test touches a synthetic
/// temporary folder to cover the timer driver's lifetime.
final class SetsDownloadsWatcherTests: XCTestCase {
    typealias Watcher = SetsDownloadsWatcher
    typealias Entry = Watcher.Entry

    private func file(_ name: String, _ size: Int64 = 10) -> Entry {
        Entry(name: name, size: size, isDirectory: false)
    }

    func testBaselineIsSilent() {
        var core = Watcher.Core()
        XCTAssertTrue(core.scan(entries: [file("before.DNG")], now: 0).isEmpty)
        XCTAssertTrue(core.scan(entries: [file("before.DNG")], now: 2).isEmpty)
    }

    func testGrowingDNGReportsAfterOneStableSecondAndOnlyOnce() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        XCTAssertTrue(core.scan(entries: [file("IMG.DNG", 10)], now: 0.1).isEmpty)
        XCTAssertTrue(core.scan(entries: [file("IMG.DNG", 20)], now: 0.6).isEmpty)
        XCTAssertTrue(core.scan(entries: [file("IMG.DNG", 20)], now: 1.1).isEmpty)
        XCTAssertEqual(
            core.scan(entries: [file("IMG.DNG", 20)], now: 1.61),
            Watcher.Batch(raws: [.init(name: "IMG.DNG", size: 20)], lossy: 0)
        )
        XCTAssertTrue(core.scan(entries: [file("IMG.DNG", 20)], now: 3).isEmpty)
    }

    func testHalfASecondStableIsNotComplete() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        _ = core.scan(entries: [file("IMG.ARW")], now: 1)
        XCTAssertTrue(core.scan(entries: [file("IMG.ARW")], now: 1.5).isEmpty)
    }

    func testDownloadSiblingHoldsStableRAWUntilSiblingGoes() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        let raw = file("IMG.dng")
        let bundle = Entry(name: "IMG.dng.download", size: 0, isDirectory: true)
        _ = core.scan(entries: [raw, bundle], now: 0.1)
        XCTAssertTrue(core.scan(entries: [raw, bundle], now: 1.2).isEmpty)
        XCTAssertEqual(core.scan(entries: [raw], now: 1.3).raws, [.init(name: "IMG.dng", size: 10)])
    }

    func testPartialHiddenStubAndUnrelatedFilesAreIgnored() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        let entries = [
            file("IMG.dng.crdownload"),
            file("IMG.ARW.part"),
            file("._IMG.dng"),
            file(".hidden.ARW"),
            file("notes.txt")
        ]
        _ = core.scan(entries: entries, now: 0.1)
        XCTAssertTrue(core.scan(entries: entries, now: 2).isEmpty)
    }

    func testHEICAndJPGAreCountedOnce() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        let entries = [file("IMG.HEIC"), file("IMG.jpg")]
        _ = core.scan(entries: entries, now: 0.1)
        XCTAssertEqual(core.scan(entries: entries, now: 1.2), Watcher.Batch(raws: [], lossy: 2))
        XCTAssertTrue(core.scan(entries: entries, now: 3).isEmpty)
    }

    func testRemovedFileReaddedAtAnotherSizeIsANewArrival() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        _ = core.scan(entries: [file("IMG.dng", 10)], now: 0.1)
        XCTAssertEqual(core.scan(entries: [file("IMG.dng", 10)], now: 1.2).raws.count, 1)
        XCTAssertTrue(core.scan(entries: [], now: 2).isEmpty)
        _ = core.scan(entries: [file("IMG.dng", 20)], now: 2.1)
        XCTAssertEqual(
            core.scan(entries: [file("IMG.dng", 20)], now: 3.2).raws,
            [.init(name: "IMG.dng", size: 20)]
        )
    }

    func testZeroByteFileIsNeverReported() {
        var core = Watcher.Core()
        _ = core.scan(entries: [], now: 0)
        _ = core.scan(entries: [file("empty.ARW", 0)], now: 0.1)
        XCTAssertTrue(core.scan(entries: [file("empty.ARW", 0)], now: 5).isEmpty)
    }

    func testDriverWaitsForStableFileAndStopsImmediately() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let arrived = expectation(description: "one complete RAW")
        let afterStop = expectation(description: "no callback after stop")
        afterStop.isInverted = true
        let lock = NSLock()
        var batches: [Watcher.Batch] = []
        var stopped = false
        let watcher = Watcher(stabilityInterval: 0.1)
        watcher.start(folder: folder, every: 0.05) { batch in
            lock.lock()
            batches.append(batch)
            let isStopped = stopped
            lock.unlock()
            if isStopped { afterStop.fulfill() } else { arrived.fulfill() }
        }

        // Let the immediate empty-folder scan establish the baseline.
        Thread.sleep(forTimeInterval: 0.08)
        let first = folder.appendingPathComponent("AIR.DNG")
        try Data([1, 2]).write(to: first)
        Thread.sleep(forTimeInterval: 0.07)
        let handle = try FileHandle(forWritingTo: first)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([3, 4]))
        try handle.close()

        wait(for: [arrived], timeout: 2)
        watcher.stop()
        lock.lock()
        stopped = true
        let captured = batches
        lock.unlock()
        XCTAssertEqual(captured, [Watcher.Batch(raws: [.init(name: "AIR.DNG", size: 4)], lossy: 0)])

        try Data([5]).write(to: folder.appendingPathComponent("LATE.ARW"))
        wait(for: [afterStop], timeout: 0.3)
        lock.lock()
        XCTAssertEqual(batches.count, 1)
        lock.unlock()
    }
}
