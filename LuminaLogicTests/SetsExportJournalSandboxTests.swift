import XCTest
@testable import Lumina

/// R1d: the export journal reaches its destination after a relaunch through the bookmark it kept
/// when the export began, never through the stored path (the sandbox refuses that path once the
/// panel's grant is gone). Temp folders only.
final class SetsExportJournalSandboxTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-journal-sandbox-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    /// Access that counts its calls. `resolveTo` overrides what a bookmark resolves to (nil = it fails).
    private final class Counting {
        var bookmarks = 0, resolves = 0, starts = 0, stops = 0
        var resolveTo: URL??
        var startResult = true
        var access: SetsExportJournal.Access {
            SetsExportJournal.Access(bookmark: { [unowned self] url in self.bookmarks += 1; return Data(url.path.utf8) },
                                     resolve: { [unowned self] data in
                                         self.resolves += 1
                                         if let r = self.resolveTo { return r }
                                         return URL(fileURLWithPath: String(decoding: data, as: UTF8.self))
                                     },
                                     start: { [unowned self] _ in self.starts += 1; return self.startResult },
                                     stop: { [unowned self] _ in self.stops += 1 })
        }
    }

    private func entries(_ jdir: URL) throws -> [SetsExportJournal.Entry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try fm.contentsOfDirectory(at: jdir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            .map { try dec.decode(SetsExportJournal.Entry.self, from: Data(contentsOf: $0)) }
    }

    /// An export cut short in `dest` with one of Lumina's temp files and one of the user's files.
    private func cutShort(access: SetsExportJournal.Access) throws -> (dest: URL, jdir: URL, ours: URL, theirs: URL) {
        let dest = dir.appendingPathComponent("export"), jdir = dir.appendingPathComponent("journal")
        try fm.createDirectory(at: dest.appendingPathComponent("RAW"), withIntermediateDirectories: true)
        let journal = SetsExportJournal(directory: jdir, access: access)
        journal.begin(label: "both", destination: dest, names: ["DSC00001.xmp", "RAW/DSC00001.ARW"])
        journal.done("DSC00001.xmp")
        let ours = dest.appendingPathComponent("RAW/.DSC00001.ARW.lumina-tmp-1234abcd"), theirs = dest.appendingPathComponent("RAW/.DSC00002.ARW.lumina-tmp-1234abcd")
        for f in [ours, theirs] { try Data("x".utf8).write(to: f) }
        return (dest, jdir, ours, theirs)
    }

    func testJournalWithBookmarkRecoversItsTempFiles() throws {
        let c = Counting()
        let (_, jdir, ours, theirs) = try cutShort(access: c.access)
        XCTAssertEqual(c.bookmarks, 1, "one bookmark, made when the export began")
        XCTAssertNotNil(try entries(jdir).first?.destinationBookmark)
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.count, 1)
        XCTAssertEqual(rec.first?.tempsRemoved, 1)
        XCTAssertNil(rec.first?.recoveryRefused)
        XCTAssertNotNil(rec.first?.recovered)
        XCTAssertFalse(fm.fileExists(atPath: ours.path))
        XCTAssertTrue(fm.fileExists(atPath: theirs.path), "not a planned file: not Lumina's to remove")
        XCTAssertEqual(c.resolves, 1)
        XCTAssertEqual(c.starts, 1); XCTAssertEqual(c.stops, 1, "access stopped once started")
        XCTAssertTrue(SetsExportJournal.recover(in: jdir, access: c.access).isEmpty, "recovered once")
        XCTAssertEqual(c.starts, c.stops)
    }

    /// The bookmark resolves to wherever the folder went: the clean-up follows it, not the old path.
    func testRecoveryFollowsTheBookmarkNotThePath() throws {
        let c = Counting()
        let (dest, jdir, _, _) = try cutShort(access: c.access)
        let moved = dir.appendingPathComponent("moved")
        try fm.moveItem(at: dest, to: moved)
        c.resolveTo = .some(moved)
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.first?.tempsRemoved, 1)
        XCTAssertFalse(fm.fileExists(atPath: moved.appendingPathComponent("RAW/.DSC00001.ARW.lumina-tmp-1234abcd").path))
    }

    /// A journal written before R1d (no bookmark field) still decodes; recovery leaves its files,
    /// says why, and tries again next time.
    func testOldJournalDecodesAndIsRefusedNotGuessed() throws {
        let dest = dir.appendingPathComponent("export"), jdir = dir.appendingPathComponent("journal")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.createDirectory(at: jdir, withIntermediateDirectories: true)
        let temp = dest.appendingPathComponent(".DSC00001.xmp.lumina-tmp-1234abcd")
        try Data("x".utf8).write(to: temp)
        let old = """
        {"id":"export-1","label":"lr","destination":"\(dest.path)","started":"2026-09-01T10:00:00Z",
         "planned":["DSC00001.xmp"],"done":[]}
        """
        try Data(old.utf8).write(to: jdir.appendingPathComponent("export-1.json"))
        XCTAssertEqual(try entries(jdir).first?.planned, ["DSC00001.xmp"])
        XCTAssertNil(try entries(jdir).first?.destinationBookmark)
        XCTAssertEqual(SetsExportJournal.unfinished(in: jdir).count, 1)

        let c = Counting()
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.count, 1)
        XCTAssertNotNil(rec.first?.recoveryRefused)
        XCTAssertNil(rec.first?.recovered)
        XCTAssertTrue(fm.fileExists(atPath: temp.path), "no bookmark: the stored path is not used")
        XCTAssertEqual(c.resolves + c.starts + c.stops, 0)
        XCTAssertNotNil(try entries(jdir).first?.recoveryRefused, "written into the journal")
        XCTAssertEqual(SetsExportJournal.recover(in: jdir, access: c.access).count, 1, "tried again on the next launch")
    }

    func testBookmarkThatDoesNotResolveIsMarkedAndLeavesFiles() throws {
        let c = Counting()
        let (_, jdir, ours, _) = try cutShort(access: c.access)
        c.resolveTo = .some(nil)
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.first?.recoveryRefused?.contains("does not resolve"), true)
        XCTAssertNil(rec.first?.recovered)
        XCTAssertTrue(fm.fileExists(atPath: ours.path))
        XCTAssertEqual(c.starts, 0); XCTAssertEqual(c.stops, 0)
        // The disk comes back: the next launch cleans up.
        c.resolveTo = nil
        let again = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(again.first?.tempsRemoved, 1)
        XCTAssertNil(again.first?.recoveryRefused)
        XCTAssertFalse(fm.fileExists(atPath: ours.path))
        XCTAssertEqual(c.starts, 1); XCTAssertEqual(c.stops, 1)
    }

    /// A folder the bookmark names but the process may not list: refused, files left, access stopped.
    func testUnreachableFolderIsRefusedAndAccessBalanced() throws {
        let c = Counting()
        let (_, jdir, _, _) = try cutShort(access: c.access)
        c.resolveTo = .some(dir.appendingPathComponent("gone"))
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.first?.recoveryRefused?.contains("can't be listed"), true)
        XCTAssertNil(rec.first?.recovered)
        XCTAssertEqual(c.starts, 1); XCTAssertEqual(c.stops, 1)
    }

    /// Access that did not start is not stopped (Apple's rule), and the clean-up still runs.
    func testAccessNotStartedIsNotStopped() throws {
        let c = Counting(); c.startResult = false
        let (_, jdir, ours, _) = try cutShort(access: c.access)
        let rec = SetsExportJournal.recover(in: jdir, access: c.access)
        XCTAssertEqual(rec.first?.tempsRemoved, 1)
        XCTAssertFalse(fm.fileExists(atPath: ours.path))
        XCTAssertEqual(c.starts, 1); XCTAssertEqual(c.stops, 0)
    }

    /// The real bookmark calls (unsandboxed here): made at begin, resolved by recover.
    func testSystemBookmarkRoundTrip() throws {
        let (_, jdir, ours, _) = try cutShort(access: .system)
        XCTAssertNotNil(try entries(jdir).first?.destinationBookmark)
        let rec = SetsExportJournal.recover(in: jdir)
        XCTAssertEqual(rec.first?.tempsRemoved, 1, rec.first?.recoveryRefused ?? "")
        XCTAssertFalse(fm.fileExists(atPath: ours.path))
    }

    func testDownloadNameIsOnePlainFileName() {
        XCTAssertEqual(SetsWindowController.safeDownloadName("lumina-golden.json"), "lumina-golden.json")
        XCTAssertEqual(SetsWindowController.safeDownloadName("../../Library/LaunchAgents/x.plist"), "x.plist")
        XCTAssertEqual(SetsWindowController.safeDownloadName(".zshrc"), "zshrc")
        XCTAssertEqual(SetsWindowController.safeDownloadName("a:b\u{0}c\n.json"), "abc.json")
        XCTAssertEqual(SetsWindowController.safeDownloadName("..."), "lumina-download")
        XCTAssertEqual(SetsWindowController.safeDownloadName(""), "lumina-download")
        XCTAssertEqual(SetsWindowController.safeDownloadName(String(repeating: "a", count: 300)).count, 128)
    }
}
