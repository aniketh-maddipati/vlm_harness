import XCTest
@testable import Lumina

/// Live AirDrop's decisions (`SkimAirdrop`): what counts as an arrival, when it has settled, how arrivals are batched, and
/// that what was in the folder when the switch went on is never handed over. Plus the switch's store and a real watch on a
/// temporary folder (copies only). Foundation only.
final class SkimAirdropTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-airdrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testArrivalsAreClipsNotHiddenNotPartial() {
        XCTAssertTrue(SkimAirdrop.isArrival("IMG_0042.MOV"))
        XCTAssertTrue(SkimAirdrop.isArrival("C0001.mp4"))
        XCTAssertTrue(SkimAirdrop.isArrival("clip.m4v"))
        XCTAssertFalse(SkimAirdrop.isArrival(".IMG_0042.MOV"))
        XCTAssertFalse(SkimAirdrop.isArrival("._C0001.MP4"))
        XCTAssertFalse(SkimAirdrop.isArrival("~C0001.MP4"))
        XCTAssertFalse(SkimAirdrop.isArrival("C0001.MP4~"))
        XCTAssertFalse(SkimAirdrop.isArrival("C0001.MP4.download"))
        XCTAssertFalse(SkimAirdrop.isArrival("C0001.mp4.crdownload"))
        XCTAssertFalse(SkimAirdrop.isArrival("C0001.mov.part"))
        XCTAssertFalse(SkimAirdrop.isArrival(".C0001.mov.icloud"))
        XCTAssertFalse(SkimAirdrop.isArrival("photo.HEIC"))
        XCTAssertFalse(SkimAirdrop.isArrival("C0001M01.XML"))
    }

    func testSettlesOnlyAfterTheSameSizeTwiceApart() {
        var a = SkimAirdrop(existing: [])
        a.look(sizes: ["a.mov": 100], at: 0)
        XCTAssertTrue(a.waiting)
        a.look(sizes: ["a.mov": 200], at: 0.5)     // still growing
        a.look(sizes: ["a.mov": 200], at: 1.0)     // only 0.5 s the same
        XCTAssertTrue(a.settled.isEmpty)
        a.look(sizes: ["a.mov": 200], at: 1.4)
        XCTAssertEqual(a.settled["a.mov"]?.size, 200)
        XCTAssertNil(a.take(at: 1.4))              // gathering: 1.5 s of quiet after the last change
        XCTAssertEqual(a.take(at: 2.1), ["a.mov"])
        XCTAssertFalse(a.waiting)
    }

    func testEmptyFileNeverSettles() {
        var a = SkimAirdrop(existing: [])
        for t in stride(from: 0.0, through: 5, by: 0.5) { a.look(sizes: ["a.mov": 0], at: t) }
        XCTAssertTrue(a.settled.isEmpty)
        XCTAssertNil(a.take(at: 5))
    }

    func testFilledInPlaceWaitsForItsTimeToStop() {
        var a = SkimAirdrop(existing: [])
        a.look(["a.mov": .init(size: 500, modified: 1)], at: 0)
        a.look(["a.mov": .init(size: 500, modified: 2)], at: 0.5)
        a.look(["a.mov": .init(size: 500, modified: 3)], at: 1.0)
        XCTAssertTrue(a.settled.isEmpty)
        a.look(["a.mov": .init(size: 500, modified: 3)], at: 1.9)
        XCTAssertNotNil(a.settled["a.mov"])
    }

    func testWhatWasThereAtSwitchOnIsNeverHandedOver() {
        var a = SkimAirdrop(existing: ["old.mov"])
        for t in stride(from: 0.0, through: 4, by: 0.5) { a.look(sizes: ["old.mov": 10, "new.mov": 20], at: t) }
        XCTAssertEqual(a.take(at: 4), ["new.mov"])
        // old.mov grows: still not an arrival
        a.look(sizes: ["old.mov": 11, "new.mov": 20], at: 4.5)
        XCTAssertFalse(a.waiting)
        // it goes away and comes back: now it is
        a.look(sizes: ["new.mov": 20], at: 5)
        a.look(sizes: ["old.mov": 11, "new.mov": 20], at: 5.5)
        XCTAssertTrue(a.settling["old.mov"] != nil)
    }

    func testBatchesTogetherAndHandsEachOnce() {
        var a = SkimAirdrop(existing: [])
        a.look(sizes: ["b.mov": 5], at: 0)
        a.look(sizes: ["b.mov": 5, "a.mov": 7], at: 0.6)
        a.look(sizes: ["b.mov": 5, "a.mov": 7], at: 1.0)   // b settled, a not yet
        XCTAssertNil(a.take(at: 1.0))
        a.look(sizes: ["b.mov": 5, "a.mov": 7], at: 1.5)   // a settled
        XCTAssertNil(a.take(at: 1.5))
        XCTAssertEqual(a.take(at: 2.2), ["a.mov", "b.mov"])
        for t in stride(from: 2.5, through: 6, by: 0.5) { a.look(sizes: ["b.mov": 5, "a.mov": 7], at: t) }
        XCTAssertNil(a.take(at: 6))
        // replaced by a different file of the same name: new again
        a.look(sizes: ["b.mov": 9, "a.mov": 7], at: 6.5)
        a.look(sizes: ["b.mov": 9, "a.mov": 7], at: 7.5)
        XCTAssertEqual(a.take(at: 9), ["b.mov"])
    }

    func testASettledClipWaitsAtMostHoldForOneStillArriving() {
        var a = SkimAirdrop(existing: [])
        a.look(sizes: ["small.mov": 1], at: 0)
        a.look(sizes: ["small.mov": 1, "big.mov": 1], at: 1)   // small settled at 1
        var t = 1.5, size: Int64 = 1
        while t < 10.9 { size += 1; a.look(sizes: ["small.mov": 1, "big.mov": size], at: t); XCTAssertNil(a.take(at: t)); t += 0.5 }
        a.look(sizes: ["small.mov": 1, "big.mov": size + 1], at: 11)
        XCTAssertEqual(a.take(at: 11), ["small.mov"])
        XCTAssertTrue(a.waiting)                                 // big still on its way
    }

    func testRemovedBeforeItSettledIsForgotten() {
        var a = SkimAirdrop(existing: [])
        a.look(sizes: ["a.mov": 3], at: 0)
        a.look(sizes: [:], at: 0.5)
        XCTAssertFalse(a.waiting)
        XCTAssertNil(a.take(at: 5))
    }

    func testStoreKeepsTheSwitchAndBookmark() {
        let s = SkimAirdropStore(file: tmp.appendingPathComponent("skim/airdrop.json"))
        XCTAssertNil(s.read())
        XCTAssertTrue(s.write(.init(bookmark: Data([1, 2]), path: "/Users/x/Downloads", on: true)))
        XCTAssertEqual(s.read(), .init(bookmark: Data([1, 2]), path: "/Users/x/Downloads", on: true))
        XCTAssertTrue(s.write(nil))
        XCTAssertNil(s.read())
    }

    /// A real watch on a temporary folder: a clip there at the start is never handed over; one written after is, once,
    /// and the file is left where it is.
    func testWatchHandsOverOnlyNewSettledClips() throws {
        try Data(repeating: 1, count: 10).write(to: tmp.appendingPathComponent("before.mov"))
        let got = expectation(description: "batch")
        let box = Box()
        let watch = SkimAirdropWatch(folder: tmp, onBatch: { urls in box.add(urls); got.fulfill() }, onGone: {})
        XCTAssertTrue(watch.start())
        defer { watch.stop() }
        try Data(repeating: 2, count: 1000).write(to: tmp.appendingPathComponent("new.mov"))
        try Data(repeating: 3, count: 10).write(to: tmp.appendingPathComponent("notes.txt"))
        wait(for: [got], timeout: 10)
        XCTAssertEqual(box.names, ["new.mov"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("new.mov").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("before.mov").path))
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ u: [URL]) { lock.lock(); urls += u; lock.unlock() }
        var names: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.lastPathComponent) }
    }
}
