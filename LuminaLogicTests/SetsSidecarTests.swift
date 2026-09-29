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
}
