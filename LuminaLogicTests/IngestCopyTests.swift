import XCTest
@testable import Lumina

/// Lumina Ingest's copy into the library (`IngestCopy`, `IngestLibrary`): verified, never moved, never written to
/// the source, a photo travels with its companions, and the library answers "already here".
final class IngestCopyTests: XCTestCase {
    private var dir: URL!, card: URL!, lib: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-copy-\(UUID().uuidString)", isDirectory: true)
        card = dir.appendingPathComponent("SONY", isDirectory: true)
        lib = dir.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: card.appendingPathComponent("DCIM/100MSDCF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func put(_ rel: String, _ text: String) throws -> URL {
        let u = card.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
        return u
    }

    private func snapshot(_ root: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let u as URL in e where !u.hasDirectoryPath { out[u.path] = try? Data(contentsOf: u) }
        return out
    }

    private func store() -> IngestLibrary { IngestLibrary(url: dir.appendingPathComponent("container/ingest/library.json")) }

    func testCopiesAPairWithItsSidecarsAndLeavesTheSourceAsItWas() throws {
        let raw = try put("DCIM/100MSDCF/DSC01234.ARW", "raw bytes")
        _ = try put("DCIM/100MSDCF/DSC01234.JPG", "jpeg bytes")
        _ = try put("DCIM/100MSDCF/DSC01234.xmp", "<x/>")
        _ = try put("DCIM/100MSDCF/DSC01235.ARW", "another photo")
        let before = snapshot(card)
        let s = store()
        let r = IngestCopy.copy(.init(key: "k1", source: raw, root: card, folder: "2026-10-28"), into: lib, store: s)
        XCTAssertTrue(r.ok, r.why ?? "")
        XCTAssertEqual(r.files, 3)
        XCTAssertFalse(r.already)
        let day = lib.appendingPathComponent("2026-10-28")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.ARW"), encoding: .utf8), "raw bytes")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.JPG"), encoding: .utf8), "jpeg bytes")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.xmp"), encoding: .utf8), "<x/>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: day.appendingPathComponent("DSC01235.ARW").path))
        XCTAssertEqual(snapshot(card), before, "the source is never written")
        XCTAssertEqual(s.entry("k1")?.rel, "2026-10-28/DSC01234.ARW")
        XCTAssertEqual(s.entry("k1")?.sha, SetsFileOps.sha256(Data("raw bytes".utf8)))
    }

    func testSonyClipTakesItsXMLAndAgainIsAlreadyHere() throws {
        let clip = try put("PRIVATE/M4ROOT/CLIP/C0001.MP4", "clip")
        _ = try put("PRIVATE/M4ROOT/CLIP/C0001M01.XML", "<meta/>")
        _ = try put("PRIVATE/M4ROOT/CLIP/C0010.MP4", "not its companion")
        let s = store()
        let r = IngestCopy.copy(.init(key: "c1", source: clip, root: card, folder: "2026-10-28"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.files, 2)
        let again = IngestCopy.copy(.init(key: "c1", source: clip, root: card, folder: "2026-10-29"), into: lib, store: s)
        XCTAssertTrue(again.ok); XCTAssertTrue(again.already)
        XCTAssertEqual(again.rel, "2026-10-28/C0001.MP4", "already here: checked against the copy kept, not copied again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.appendingPathComponent("2026-10-29").path))
    }

    func testANameClashWithOtherBytesNumbersTheFileAndItsCompanions() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let b = try put("B/DSC00001.ARW", "photo b")
        _ = try put("B/DSC00001.JPG", "jpeg b")
        let s = store()
        XCTAssertTrue(IngestCopy.copy(.init(key: "a", source: a, root: card, folder: "d"), into: lib, store: s).ok)
        let r = IngestCopy.copy(.init(key: "b", source: b, root: card, folder: "d"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.rel, "d/DSC00001-2.ARW")
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent("d/DSC00001-2.JPG"), encoding: .utf8), "jpeg b")
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent("d/DSC00001.ARW"), encoding: .utf8), "photo a")
    }

    func testAKeyThatMatchedByChanceIsStillCopied() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let b = try put("B/DSC00002.ARW", "photo b")
        let s = store()
        XCTAssertTrue(IngestCopy.copy(.init(key: "same", source: a, root: card, folder: "d"), into: lib, store: s).ok)
        let r = IngestCopy.copy(.init(key: "same", source: b, root: card, folder: "d"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertFalse(r.already)
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent(r.rel!), encoding: .utf8), "photo b")
    }

    func testRefusesALibraryInsideTheSourceAndUnsafeFolders() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let before = snapshot(card)
        let inside = IngestCopy.copy(.init(key: "a", source: a, root: card, folder: "d"), into: card.appendingPathComponent("lib"), store: store())
        XCTAssertFalse(inside.ok); XCTAssertEqual(inside.why, "library inside the source")
        let up = IngestCopy.copy(.init(key: "a", source: a, root: card, folder: "../escape"), into: lib, store: store())
        XCTAssertFalse(up.ok); XCTAssertEqual(up.why, "refused")
        let gone = IngestCopy.copy(.init(key: "a", source: card.appendingPathComponent("nope.ARW"), root: card, folder: "d"), into: lib, store: store())
        XCTAssertFalse(gone.ok); XCTAssertEqual(gone.why, "missing")
        XCTAssertEqual(snapshot(card), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape").path))
    }

    func testResolveStaysInsideWhatWasChosen() throws {
        let a = try put("DCIM/100MSDCF/DSC00001.ARW", "photo a")
        let loose = try put("loose.JPG", "j")
        XCTAssertEqual(IngestCopy.resolve("SONY/DCIM/100MSDCF/DSC00001.ARW", roots: [card])?.file.path, a.path)
        XCTAssertNil(IngestCopy.resolve("SONY/../Library/x", roots: [card]))
        XCTAssertNil(IngestCopy.resolve("/etc/hosts", roots: [card]))
        XCTAssertNil(IngestCopy.resolve("OTHER/DCIM/100MSDCF/DSC00001.ARW", roots: [card]))
        XCTAssertEqual(IngestCopy.resolve("loose.JPG", roots: [loose])?.file.path, loose.path)
        XCTAssertNil(IngestCopy.resolve("loose.JPG", roots: [card]), "a bare name only matches a file chosen on its own")
    }

    func testLibraryPersistsAndForgets() throws {
        let s = store()
        s.setFolder("/x/Library", bookmark: nil)
        s.record("k", .init(rel: "d/a.ARW", sha: "00", size: 3))
        try s.save()
        let t = store()
        XCTAssertEqual(t.path, "/x/Library"); XCTAssertEqual(t.has(["k", "z"]), ["k"])
        t.setFolder("/x/Library", bookmark: nil); XCTAssertEqual(t.count, 1, "the same folder keeps its identities")
        t.setFolder("/y/Other", bookmark: nil); XCTAssertEqual(t.count, 0, "another folder starts empty")
        t.record("k", .init(rel: "r", sha: "s", size: 1)); t.forget(); XCTAssertEqual(t.count, 0)
    }
}
