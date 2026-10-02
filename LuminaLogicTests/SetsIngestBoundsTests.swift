import Darwin
import XCTest
@testable import Lumina

/// Threat model T5: what a folder can make the listing walk, read and hold, and what the page may
/// store as a session. Synthetic trees in a temp folder only: no test walks `/` or a home folder.
final class SetsIngestBoundsTests: XCTestCase {
    private var dir: URL!
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-bounds-\(UUID().uuidString)", isDirectory: true)
        root = dir.appendingPathComponent("shoot", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("100MSDCF"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func put(_ rel: String, _ data: Data = Data(count: 4)) throws {
        let url = root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// `n` empty files spread over folders of 100, as a card lays them out.
    private func tree(_ n: Int, ext: String = "ARW") throws {
        for i in 0 ..< n {
            let folder = root.appendingPathComponent(String(format: "%03dMSDCF", 100 + i / 100), isDirectory: true)
            if i % 100 == 0 { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
            guard fm.createFile(atPath: folder.appendingPathComponent(String(format: "DSC%05d.%@", i, ext)).path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    /// The process's memory footprint (what Activity Monitor shows), in bytes.
    private func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    // MARK: Sidecars

    func testSidecarOver1MBIsSkippedUnreadAndNamed() throws {
        try put("100MSDCF/DSC00001.ARW")
        try put("100MSDCF/DSC00002.ARW")
        try put("100MSDCF/DSC00001.xmp", Data("<x:xmpmeta/>".utf8))
        // 500 MB on paper, a few blocks on disk: a sparse file, never written.
        let huge = root.appendingPathComponent("100MSDCF/DSC00002.xmp")
        XCTAssertTrue(fm.createFile(atPath: huge.path, contents: nil))
        let h = try FileHandle(forWritingTo: huge)
        try h.truncate(atOffset: 500 << 20)
        try h.close()
        XCTAssertEqual(try huge.resourceValues(forKeys: [.fileSizeKey]).fileSize, 500 << 20)

        let before = footprint()
        let l = SetsIngest.list(root)
        let grew = footprint() - before
        XCTAssertNil(l.stopped)
        XCTAssertEqual(l.files.count, 2, "the ARWs are listed as usual")
        XCTAssertEqual(l.xmp.map(\.rel), ["shoot/100MSDCF/DSC00001.xmp"])
        XCTAssertEqual(l.skippedXmp, ["shoot/100MSDCF/DSC00002.xmp"])
        XCTAssertEqual(l.dictionary["skippedXmp"] as? [String], ["shoot/100MSDCF/DSC00002.xmp"], "the page gets the count")
        XCTAssertLessThan(grew, 32 << 20, "memory stays flat: the 500 MB sidecar is never read (grew \(grew) bytes)")
    }

    func testSidecarAtTheLimitIsReadAndOneByteMoreIsNot() throws {
        try put("100MSDCF/A.xmp", Data(repeating: 0x61, count: 100))
        try put("100MSDCF/B.xmp", Data(repeating: 0x62, count: 101))
        var limits = SetsIngest.Limits()
        limits.sidecarBytes = 100
        let l = SetsIngest.list(root, limits: limits)
        XCTAssertEqual(l.xmp.map(\.rel), ["shoot/100MSDCF/A.xmp"])
        XCTAssertEqual(l.xmp.first?.text.count, 100)
        XCTAssertEqual(l.skippedXmp, ["shoot/100MSDCF/B.xmp"])
    }

    // MARK: Too big

    func testTreeOverTheEntryLimitIsRefusedWholeAndQuickly() throws {
        try tree(600)
        var limits = SetsIngest.Limits()
        limits.entries = 500
        let t0 = Date()
        let l = SetsIngest.list(root, limits: limits)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        XCTAssertEqual(l.stopped, .tooManyFiles)
        XCTAssertTrue(l.files.isEmpty && l.xmp.isEmpty && l.others.isEmpty && l.skippedXmp.isEmpty, "nothing that could pass for the whole folder")
        XCTAssertEqual(l.name, "shoot")

        limits.entries = 700                                     // 600 files + 6 folders
        let all = SetsIngest.list(root, limits: limits)
        XCTAssertNil(all.stopped)
        XCTAssertEqual(all.files.count, 600)
    }

    func testFolderBelowTheDepthLimitIsRefused() throws {
        let deep = (1 ... 13).map { "d\($0)" }.joined(separator: "/")
        try put(deep + "/DSC00001.ARW")
        let l = SetsIngest.list(root)
        XCTAssertEqual(SetsIngest.Limits().depth, 12)
        XCTAssertEqual(l.stopped, .tooDeep)
        XCTAssertTrue(l.files.isEmpty)
    }

    func testTwelveLevelsDownIsStillAShoot() throws {
        let deep = (1 ... 12).map { "d\($0)" }.joined(separator: "/")
        try put(deep + "/DSC00001.ARW")
        let l = SetsIngest.list(root)
        XCTAssertNil(l.stopped)
        XCTAssertEqual(l.files.map(\.rel), ["shoot/" + deep + "/DSC00001.ARW"])
    }

    /// The default entry limit stands in for `/`, a home folder or a whole disk. Measured on a
    /// synthetic 20,000-file tree and projected to the limit: about 2 s at most to the refusal.
    func testWalkRateKeepsTheDefaultLimitUnderAboutTwoSeconds() throws {
        try tree(20_000, ext: "JPG")
        _ = SetsIngest.list(root)                                // warm the file system's caches, as a real walk of a busy disk is
        let t0 = Date()
        let l = SetsIngest.list(root)
        let secs = Date().timeIntervalSince(t0)
        XCTAssertEqual(l.others.count, 20_000)
        let entries = 20_000 + 200
        let projected = secs * Double(SetsIngest.Limits().entries) / Double(entries)
        print("SetsIngestBounds: walked \(entries) entries in \(String(format: "%.3f", secs)) s; the \(SetsIngest.Limits().entries) limit ≈ \(String(format: "%.2f", projected)) s")
        // About 1.7 s on an M-series Mac; 3 s leaves room for a slower CI runner.
        XCTAssertLessThan(projected, 3, "the default limit should stop a huge folder in about 2 s (projected \(projected) s)")
    }

    // MARK: Cancelled

    func testCancelledListingStopsAndCarriesNothing() throws {
        try tree(2_000)
        var asks = 0
        let l = SetsIngest.list(root, isCancelled: { asks += 1; return asks >= 3 })
        XCTAssertEqual(l.stopped, .cancelled)
        XCTAssertTrue(l.files.isEmpty)
        XCTAssertEqual(asks, 3, "asked every 128 entries, stopped at the first yes")
    }

    func testCancellingTheTaskStopsTheListing() async throws {
        try tree(5_000)
        let root = self.root!
        let task = Task.detached(priority: .userInitiated) { SetsIngest.list(root) }
        task.cancel()
        let l = await task.value
        XCTAssertEqual(l.stopped, .cancelled, "the bridge cancels the listing task when another folder is opened")
        XCTAssertTrue(l.files.isEmpty)
        // Not cancelled, the same tree lists whole.
        let whole = await Task.detached { SetsIngest.list(root) }.value
        XCTAssertNil(whole.stopped)
        XCTAssertEqual(whole.files.count, 5_000)
    }

    // MARK: Sessions

    @MainActor
    func testSessionOverTheLimitIsRefused() {
        XCTAssertEqual(SetsBridge.maxSessionBytes, 16 << 20)
        XCTAssertNil(SetsBridge.sessionRefusal(String(repeating: "x", count: SetsBridge.maxSessionBytes)))
        let refusal = SetsBridge.sessionRefusal(String(repeating: "x", count: SetsBridge.maxSessionBytes + 1))
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("too big") ?? false, "plumbing.js matches \"too big\" to say it")
        // Counted in bytes, not characters: 6 M three-byte characters is 18 MB.
        XCTAssertNotNil(SetsBridge.sessionRefusal(String(repeating: "あ", count: 6 << 20)))
    }
}
