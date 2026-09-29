import XCTest
@testable import Lumina

/// Trust rules at the Mac layer only (no page): what must hold whatever the design does.
/// ROADMAP trust list: never change originals, keep a .lumina-bak before replacing, never write
/// into the source or onto the card, copies verified, nothing half-written left behind.
final class SetsTrustTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-trust-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func leftovers(_ d: URL) -> [String] {
        ((fm.enumerator(atPath: d.path)?.allObjects as? [String]) ?? []).filter { $0.contains(".lumina-tmp-") }
    }

    // MARK: .lumina-bak

    /// Two exports into a folder holding Lightroom's sidecar: the backup must still be Lightroom's
    /// file, not Lumina's first export (the page's undo says "remove .lumina-bak from the old name").
    func testSecondExportKeepsTheOriginalBackup() throws {
        let url = dir.appendingPathComponent("DSC00001.xmp")
        try Data("lightroom".utf8).write(to: url)
        XCTAssertTrue(try SetsFileOps.write(Data("lumina 3 stars".utf8), to: url).backedUp)
        _ = try SetsFileOps.write(Data("lumina 5 stars".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "lumina 5 stars")
        XCTAssertEqual(try String(contentsOf: SetsFileOps.backupURL(for: url), encoding: .utf8), "lightroom",
                       "the pre-Lumina original must survive any number of exports")
    }

    // MARK: Where writes land

    /// A destination folder that contains a symlink into the source folder: files written "into the
    /// destination" would land next to the originals. Every item's real landing place is checked.
    func testASymlinkInTheDestinationCannotLeadIntoTheSource() throws {
        let src = dir.appendingPathComponent("shoot"), dest = dir.appendingPathComponent("export")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("raw".utf8).write(to: src.appendingPathComponent("DSC00001.ARW"))
        try fm.createSymbolicLink(at: dest.appendingPathComponent("RAW"), withDestinationURL: src)
        let job = SetsExportJob(label: "both", destination: dest, items: [.bytes(name: "RAW/DSC00001.xmp", data: Data("x".utf8))])
        let r = job.run(journal: nil, sources: [src])
        XCTAssertEqual(r.n, 0)
        XCTAssertFalse(r.failed.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: src.appendingPathComponent("DSC00001.xmp").path), "nothing may be written into the source folder")
    }

    func testItemNamesCannotClimbOutOfTheDestination() throws {
        let dest = dir.appendingPathComponent("export")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let job = SetsExportJob(label: "lr", destination: dest, items: [.bytes(name: "../escaped.xmp", data: Data("x".utf8))])
        let r = job.run(journal: nil, sources: [])
        XCTAssertEqual(r.n, 0)
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("escaped.xmp").path))
    }

    // MARK: Copies

    /// A copy that can't finish (source vanished mid-way, as with a pulled card) leaves neither a
    /// partial file nor a temp file, and the journal says what was done.
    func testACopyThatFailsLeavesNothingBehind() throws {
        let src = dir.appendingPathComponent("card"), dest = dir.appendingPathComponent("export")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try Data(count: 2 << 20).write(to: src.appendingPathComponent("A.ARW"))
        let missing = src.appendingPathComponent("B.ARW")                  // listed, then gone
        let job = SetsExportJob(label: "both", destination: dest, items: [.copy(name: "RAW/A.ARW", source: src.appendingPathComponent("A.ARW")),
                                                                         .copy(name: "RAW/B.ARW", source: missing)])
        let jdir = dir.appendingPathComponent("journal")
        let r = job.run(journal: SetsExportJournal(directory: jdir), sources: [src])
        XCTAssertEqual(r.n, 1)
        XCTAssertEqual(r.failed.first, "the card was removed · re-insert it and export again")
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("RAW/B.ARW").path))
        XCTAssertEqual(leftovers(dest), [])
        XCTAssertEqual(SetsExportJournal.unfinished(in: jdir).first?.done, ["RAW/A.ARW"])
    }

    /// Kill -9 mid-write leaves `.name.lumina-tmp-*`; the next launch removes exactly those, and
    /// never a file the user owns, even one whose name looks similar.
    func testRecoveryRemovesOnlyLuminasOwnTempFiles() throws {
        let dest = dir.appendingPathComponent("export"), jdir = dir.appendingPathComponent("journal")
        try fm.createDirectory(at: dest.appendingPathComponent("RAW"), withIntermediateDirectories: true)
        let journal = SetsExportJournal(directory: jdir)
        journal.begin(label: "both", destination: dest, names: ["DSC00001.xmp", "RAW/DSC00001.ARW"])
        let ours = [".DSC00001.xmp.lumina-tmp-1234abcd", ".DSC00001.xmp.lumina-bak.lumina-tmp-5678abcd", "RAW/.DSC00001.ARW.lumina-tmp-9abcdef0", "RAW/.DSC00001-2.ARW.lumina-tmp-0fedcba9"]
        let theirs = ["DSC00001.xmp", ".DSC00002.xmp.lumina-tmp-1234abcd", "notes.lumina-tmp-x.txt", "RAW/.hidden"]
        for f in ours + theirs { try Data("x".utf8).write(to: dest.appendingPathComponent(f)) }
        let rec = SetsExportJournal.recover(in: jdir)
        XCTAssertEqual(rec.first?.tempsRemoved, ours.count)
        for f in ours { XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent(f).path), f) }
        for f in theirs { XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(f).path), "must not touch \(f)") }
        XCTAssertTrue(SetsExportJournal.recover(in: jdir).isEmpty, "recovered once")
        XCTAssertEqual(SetsExportJournal.unfinished(in: jdir).count, 1, "still reported as cut short")
    }

    // MARK: Reading

    /// Files that change between the listing and the read: deleted → unreadable (not "card
    /// removed"); cut short → the preview is refused rather than half read.
    func testFilesChangingAfterTheListing() throws {
        let root = dir.appendingPathComponent("shoot")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(count: 500_000).write(to: root.appendingPathComponent("A.ARW"))
        try Data(count: 500_000).write(to: root.appendingPathComponent("B.ARW"))
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        XCTAssertEqual(SetsIngest.list(root).files.count, 2)
        try fm.removeItem(at: root.appendingPathComponent("A.ARW"))
        XCTAssertThrowsError(try ingest.head("shoot/A.ARW")) { XCTAssertEqual(($0 as? SetsIngest.Failure)?.kind, .notFound) }
        let h = try FileHandle(forWritingTo: root.appendingPathComponent("B.ARW")); try h.truncate(atOffset: 300_000); try h.close()
        XCTAssertThrowsError(try ingest.preview(.init(rel: "shoot/B.ARW", offset: 280_000, length: 100_000, orientation: 1)))
        XCTAssertTrue(ingest.snapshot.gone.isEmpty)
    }

    /// A symlink inside the opened folder that points elsewhere is neither listed nor read.
    func testSymlinksInsideTheFolderAreNotFollowed() throws {
        let root = dir.appendingPathComponent("shoot"), outside = dir.appendingPathComponent("private.ARW")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("LINK.ARW"), withDestinationURL: outside)
        XCTAssertEqual(SetsIngest.list(root).files.count, 0)
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        XCTAssertThrowsError(try ingest.head("shoot/LINK.ARW"))
    }

    /// Ingest opens files read-only: the card's bytes and dates are the same after a read.
    func testReadingChangesNothing() throws {
        let root = dir.appendingPathComponent("shoot")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let f = root.appendingPathComponent("A.ARW")
        try Data((0..<400_000).map { UInt8($0 % 7) }).write(to: f)
        let before = try fm.attributesOfItem(atPath: f.path)
        let ingest = SetsIngest(workers: 1)
        ingest.register(root)
        _ = try ingest.head("shoot/A.ARW")
        _ = try? ingest.preview(.init(rel: "shoot/A.ARW", offset: 1000, length: 1000, orientation: 1))
        let after = try fm.attributesOfItem(atPath: f.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(before[.size] as? Int, after[.size] as? Int)
    }
}
