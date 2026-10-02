import XCTest
@testable import Lumina

/// v5 Save (SAFETY.md 1): one .xmp per keeper, written INTO the shoot folder next to its RAW.
/// Atomic, `.lumina-bak` first, read back; only `.xmp` names inside the folder; never a RAW.
final class SetsSidecarTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: dir.appendingPathComponent("locked.xmp").path)
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesNextToTheRaw() throws {
        try Data("raw".utf8).write(to: dir.appendingPathComponent("sub/DSC00001.ARW"))
        let r = try SetsFileOps.writeSidecar(Data("<x/>".utf8), rel: "sub/DSC00001.xmp", root: dir)
        XCTAssertFalse(r.backedUp)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("sub/DSC00001.xmp"), encoding: .utf8), "<x/>")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("sub/DSC00001.ARW"), encoding: .utf8), "raw")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("sub").path)), ["DSC00001.ARW", "DSC00001.xmp"])
    }

    func testExistingSidecarKeptAsLuminaBak() throws {
        let url = dir.appendingPathComponent("DSC00002.xmp")
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00002.ARW"))
        try Data("lightroom edits".utf8).write(to: url)
        XCTAssertTrue(try SetsFileOps.writeSidecar(Data("rated".utf8), rel: "DSC00002.xmp", root: dir).backedUp)
        XCTAssertEqual(try String(contentsOf: url.appendingPathExtension("lumina-bak"), encoding: .utf8), "lightroom edits")
        // A second save keeps the first backup: it is the file as it was before Lumina.
        XCTAssertFalse(try SetsFileOps.writeSidecar(Data("rated again".utf8), rel: "DSC00002.xmp", root: dir).backedUp)
        XCTAssertEqual(try String(contentsOf: url.appendingPathExtension("lumina-bak"), encoding: .utf8), "lightroom edits")
    }

    func testOnlyXmpInsideTheFolder() {
        for rel in ["DSC00001.ARW", "../escape.xmp", "/tmp/abs.xmp", "sub/../../x.xmp", "a//b.xmp", "note.txt"] {
            XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("x".utf8), rel: rel, root: dir), rel) { e in
                XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, "refused", rel)
            }
        }
    }

    func testMissingSubfolderIsMissing() {
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("x".utf8), rel: "gone/DSC00001.xmp", root: dir)) { e in
            XCTAssertEqual(e as? SetsFileOps.SidecarError, SetsFileOps.SidecarError(name: "DSC00001", reason: "missing"))
        }
    }

    /// SAFETY.md 6: a keeper whose RAW was renamed, moved or deleted since the read gets no sidecar.
    func testNoSidecarWithoutItsRaw() throws {
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00003-renamed.ARW"))
        try Data("old".utf8).write(to: dir.appendingPathComponent("DSC00004.xmp"))
        for name in ["DSC00003", "DSC00004"] {
            XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("x".utf8), rel: name + ".xmp", root: dir), name) { e in
                XCTAssertEqual(e as? SetsFileOps.SidecarError, SetsFileOps.SidecarError(name: name, reason: "missing"))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("DSC00003.xmp").path))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("DSC00004.xmp"), encoding: .utf8), "old")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["sub", "DSC00003-renamed.ARW", "DSC00004.xmp"])
        // The extension's case doesn't matter; the name does.
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00005.arw"))
        XCTAssertNoThrow(try SetsFileOps.writeSidecar(Data("x".utf8), rel: "DSC00005.XMP", root: dir))
    }

    func testLinkedFolderCannotLeadOut() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("sets-sidecar-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("x".utf8), rel: "link/DSC00001.xmp", root: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testLockedSidecarIsLocked() throws {
        let url = dir.appendingPathComponent("locked.xmp")
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("new".utf8), rel: "locked.xmp", root: dir)) { e in
            XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, "locked")
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old")
    }

    func testListingNamesOtherFilesWithoutReadingThem() throws {
        for n in ["DSC00001.ARW", "DSC00001.JPG", "A.CR3", "clip.MP4", "DSC00001.xmp", "DSC00001.xmp.lumina-bak", ".hidden", "._DSC00001.ARW"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(n))
        }
        let l = SetsIngest.list(dir)
        let name = dir.lastPathComponent
        XCTAssertEqual(l.files.map(\.rel), [name + "/DSC00001.ARW"])
        XCTAssertEqual(l.xmp.map(\.rel), [name + "/DSC00001.xmp"])
        XCTAssertEqual(Set(l.others), [name + "/DSC00001.JPG", name + "/A.CR3", name + "/clip.MP4"])
        XCTAssertFalse(l.onCard)
    }

    // MARK: A sidecar another app wrote between the open and Save (threat model T4)

    /// The merge was based on the text read at open; Lightroom has saved newer settings since.
    /// Nothing is written: not the old text, not a backup, not a temp file.
    func testSidecarChangedSinceItsBaseIsLeftAlone() throws {
        let url = dir.appendingPathComponent("DSC00006.xmp")
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00006.ARW"))
        try Data("exposure +0.10".utf8).write(to: url)
        let atOpen = try SetsFileOps.readSidecar(rel: "DSC00006.xmp", root: dir)
        XCTAssertEqual(atOpen.text, "exposure +0.10")
        XCTAssertEqual(atOpen.base, SetsFileOps.sha256(Data("exposure +0.10".utf8)))
        try Data("exposure +1.50".utf8).write(to: url)                       // the other app
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("exposure +0.10 rated".utf8), rel: "DSC00006.xmp", root: dir, base: atOpen.base)) { e in
            XCTAssertEqual(e as? SetsFileOps.SidecarError, SetsFileOps.SidecarError(name: "DSC00006", reason: "changed on disk"))
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "exposure +1.50")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["sub", "DSC00006.ARW", "DSC00006.xmp"])
        // Read again, merged again: written, and the backup is the other app's newest file.
        let now = try SetsFileOps.readSidecar(rel: "DSC00006.xmp", root: dir)
        XCTAssertEqual(now.text, "exposure +1.50")
        XCTAssertTrue(try SetsFileOps.writeSidecar(Data("exposure +1.50 rated".utf8), rel: "DSC00006.xmp", root: dir, base: now.base).backedUp)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "exposure +1.50 rated")
        XCTAssertEqual(try String(contentsOf: url.appendingPathExtension("lumina-bak"), encoding: .utf8), "exposure +1.50")
    }

    /// The same when Lumina has written this sidecar before: the backup still holds the first
    /// version (it is never replaced), so a stale write would lose the newer settings for good.
    func testStaleWriteAfterAnEarlierSaveIsLeftAlone() throws {
        let url = dir.appendingPathComponent("DSC00007.xmp")
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00007.ARW"))
        try Data("v1".utf8).write(to: url)
        let v1 = try SetsFileOps.readSidecar(rel: "DSC00007.xmp", root: dir).base
        try SetsFileOps.writeSidecar(Data("v1 rated".utf8), rel: "DSC00007.xmp", root: dir, base: v1)
        let rated = try SetsFileOps.readSidecar(rel: "DSC00007.xmp", root: dir).base
        try Data("v2 from lightroom".utf8).write(to: url)
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("v1 rated 4".utf8), rel: "DSC00007.xmp", root: dir, base: rated)) { e in
            XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, SetsFileOps.sidecarChanged)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "v2 from lightroom")
        XCTAssertEqual(try String(contentsOf: url.appendingPathExtension("lumina-bak"), encoding: .utf8), "v1")
    }

    /// "There was no sidecar" is a base too: one that appeared since is not replaced by a fresh
    /// one, and one that was deleted since is not brought back from old text.
    func testNoSidecarIsABase() throws {
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00008.ARW"))
        let none = try SetsFileOps.readSidecar(rel: "DSC00008.xmp", root: dir)
        XCTAssertNil(none.text)
        XCTAssertEqual(none.base, SetsFileOps.noSidecar)
        let url = dir.appendingPathComponent("DSC00008.xmp")
        try Data("made by lightroom".utf8).write(to: url)
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("fresh".utf8), rel: "DSC00008.xmp", root: dir, base: none.base)) { e in
            XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, "changed on disk")
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "made by lightroom")
        let made = try SetsFileOps.readSidecar(rel: "DSC00008.xmp", root: dir).base
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try SetsFileOps.writeSidecar(Data("made by lightroom rated".utf8), rel: "DSC00008.xmp", root: dir, base: made)) { e in
            XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, "changed on disk")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNoThrow(try SetsFileOps.writeSidecar(Data("fresh".utf8), rel: "DSC00008.xmp", root: dir, base: SetsFileOps.noSidecar))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "fresh")
    }

    /// A file that already holds the bytes to write has nothing to lose: saving twice with nothing
    /// changed stays a no-op whatever base comes with it. Without a base nothing is compared.
    func testSameBytesAndNoBase() throws {
        let url = dir.appendingPathComponent("DSC00009.xmp")
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00009.ARW"))
        try Data("rated".utf8).write(to: url)
        XCTAssertFalse(try SetsFileOps.writeSidecar(Data("rated".utf8), rel: "DSC00009.xmp", root: dir, base: SetsFileOps.noSidecar).backedUp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("lumina-bak").path))
        XCTAssertTrue(try SetsFileOps.writeSidecar(Data("unchecked".utf8), rel: "DSC00009.xmp", root: dir).backedUp)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "unchecked")
    }

    /// The read at Save takes the same names the write does, and nothing else in the folder.
    func testReadSidecarOnlyXmpInsideTheFolder() throws {
        try Data("raw".utf8).write(to: dir.appendingPathComponent("DSC00001.ARW"))
        for rel in ["DSC00001.ARW", "../escape.xmp", "/tmp/abs.xmp", "sub/../../x.xmp", "note.txt"] {
            XCTAssertThrowsError(try SetsFileOps.readSidecar(rel: rel, root: dir), rel) { e in
                XCTAssertEqual((e as? SetsFileOps.SidecarError)?.reason, "refused", rel)
            }
        }
        // Not UTF-8: no text (the read at open skips it too), but still a base.
        try Data([0xff, 0xfe, 0x00]).write(to: dir.appendingPathComponent("sub/DSC00002.XMP"))
        let odd = try SetsFileOps.readSidecar(rel: "sub/DSC00002.XMP", root: dir)
        XCTAssertNil(odd.text)
        XCTAssertEqual(odd.base, SetsFileOps.sha256(Data([0xff, 0xfe, 0x00])))
    }
}
