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

    private func key(_ u: URL) -> String { IngestCopy.pageKey(u)! }

    private func store() -> IngestLibrary { IngestLibrary(url: dir.appendingPathComponent("container/ingest/library.json")) }

    func testCopiesAPairWithItsSidecarsAndLeavesTheSourceAsItWas() throws {
        let raw = try put("DCIM/100MSDCF/DSC01234.ARW", "raw bytes")
        _ = try put("DCIM/100MSDCF/DSC01234.JPG", "jpeg bytes")
        _ = try put("DCIM/100MSDCF/DSC01234.xmp", "<x/>")
        _ = try put("DCIM/100MSDCF/DSC01235.ARW", "another photo")
        let before = snapshot(card)
        let s = store()
        let r = IngestCopy.copy(.init(key: key(raw), source: raw, root: card, folder: "2026-10-28"), into: lib, store: s)
        XCTAssertTrue(r.ok, r.why ?? "")
        XCTAssertEqual(r.files, 3)
        XCTAssertFalse(r.already)
        let day = lib.appendingPathComponent("2026-10-28")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.ARW"), encoding: .utf8), "raw bytes")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.JPG"), encoding: .utf8), "jpeg bytes")
        XCTAssertEqual(try String(contentsOf: day.appendingPathComponent("DSC01234.xmp"), encoding: .utf8), "<x/>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: day.appendingPathComponent("DSC01235.ARW").path))
        XCTAssertEqual(snapshot(card), before, "the source is never written")
        XCTAssertEqual(r.sources.count, 3, "the photo and both companions are accounted for")
        XCTAssertEqual(s.entry(key(raw))?.rel, "2026-10-28/DSC01234.ARW")
        XCTAssertEqual(s.entry(key(raw))?.sha, SetsFileOps.sha256(Data("raw bytes".utf8)))
    }

    func testSonyClipTakesItsXMLAndAgainIsAlreadyHere() throws {
        let clip = try put("PRIVATE/M4ROOT/CLIP/C0001.MP4", "clip")
        _ = try put("PRIVATE/M4ROOT/CLIP/C0001M01.XML", "<meta/>")
        _ = try put("PRIVATE/M4ROOT/CLIP/C0010.MP4", "not its companion")
        let s = store()
        let r = IngestCopy.copy(.init(key: key(clip), source: clip, root: card, folder: "2026-10-28"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.files, 2)
        let again = IngestCopy.copy(.init(key: key(clip), source: clip, root: card, folder: "2026-10-29"), into: lib, store: s)
        XCTAssertTrue(again.ok); XCTAssertTrue(again.already)
        XCTAssertEqual(again.rel, "2026-10-28/C0001.MP4", "already here: checked against the copy kept, not copied again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.appendingPathComponent("2026-10-29").path))
    }

    func testANameClashWithOtherBytesNumbersTheFileAndItsCompanions() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let b = try put("B/DSC00001.ARW", "photo b")
        _ = try put("B/DSC00001.JPG", "jpeg b")
        let s = store()
        XCTAssertTrue(IngestCopy.copy(.init(key: key(a), source: a, root: card, folder: "d"), into: lib, store: s).ok)
        let r = IngestCopy.copy(.init(key: key(b), source: b, root: card, folder: "d"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.rel, "d/DSC00001-2.ARW")
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent("d/DSC00001-2.JPG"), encoding: .utf8), "jpeg b")
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent("d/DSC00001.ARW"), encoding: .utf8), "photo a")
    }

    func testIdenticalBytesUnderAnotherNameLeaveTheCompanionItsOwnName() throws {
        let a = try put("A/DSC00200.ARW", "same raw")
        let b = try put("B/DSC00300.ARW", "same raw")
        _ = try put("B/DSC00300.JPG", "jpeg of 300")
        let s = store()
        XCTAssertEqual(key(a), key(b), "the same bytes are one identity")
        XCTAssertTrue(IngestCopy.copy(.init(key: key(a), source: a, root: card, folder: "d"), into: lib, store: s).ok)
        let r = IngestCopy.copy(.init(key: key(b), source: b, root: card, folder: "d"), into: lib, store: s)
        XCTAssertTrue(r.ok, r.why ?? ""); XCTAssertTrue(r.already == false || r.files == 2)
        XCTAssertEqual(try String(contentsOf: lib.appendingPathComponent("d/DSC00300.JPG"), encoding: .utf8), "jpeg of 300")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.appendingPathComponent("d/DSC00200.JPG").path))
    }

    func testAKeyThatMatchedByChanceIsStillCopied() throws {
        // Same size, same first and last 64 KB, other bytes between: the page's key can't tell them apart.
        let edge = Data(repeating: 7, count: 65536)
        let a = card.appendingPathComponent("A/DSC00001.ARW"), b = card.appendingPathComponent("B/DSC00002.ARW")
        for (u, mid) in [(a, UInt8(1)), (b, UInt8(2))] {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (edge + Data(repeating: mid, count: 1000) + edge).write(to: u)
        }
        XCTAssertEqual(key(a), key(b))
        let s = store()
        XCTAssertTrue(IngestCopy.copy(.init(key: key(a), source: a, root: card, folder: "d"), into: lib, store: s).ok)
        let r = IngestCopy.copy(.init(key: key(b), source: b, root: card, folder: "d"), into: lib, store: s)
        XCTAssertTrue(r.ok); XCTAssertFalse(r.already)
        XCTAssertEqual(try Data(contentsOf: lib.appendingPathComponent(r.rel!)), try Data(contentsOf: b))
    }

    func testTheFileReadIsTheFileCopied() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let r = IngestCopy.copy(.init(key: key(a), source: try put("B/DSC00001.ARW", "photo b"), root: card, folder: "d"), into: lib, store: store())
        XCTAssertFalse(r.ok); XCTAssertEqual(r.why, "not the file that was read")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.appendingPathComponent("d").path))
    }

    func testPageKeyIsThePages() throws {
        XCTAssertEqual(IngestCopy.crc32(Data("123456789".utf8)), 0xCBF43926)
        let small = try put("x.JPG", "abc")
        XCTAssertEqual(IngestCopy.pageKey(small), "3-" + String(0x352441C2 as UInt32, radix: 36) + "-0", "128 KB or less: no tail")
        let big = card.appendingPathComponent("big.ARW")
        let head = Data(repeating: 1, count: 65536), mid = Data(repeating: 2, count: 10), tail = Data(repeating: 3, count: 65536)
        try (head + mid + tail).write(to: big)
        XCTAssertEqual(IngestCopy.pageKey(big), String(131082, radix: 36) + "-" + String(IngestCopy.crc32(head), radix: 36) + "-" + String(IngestCopy.crc32(tail), radix: 36))
    }

    func testAGoneLibraryStopsAtOnceAndFoldersAndLinksAreNamed() throws {
        let a = try put("A/DSC00001.ARW", "photo a")
        let gone = IngestCopy.copy(.init(key: key(a), source: a, root: card, folder: "d"), into: dir.appendingPathComponent("unplugged"), store: store())
        XCTAssertFalse(gone.ok); XCTAssertEqual(gone.why, IngestCopy.destinationGone)
        let notAFolder = try put("A/library", "a file where the library was")
        XCTAssertEqual(IngestCopy.copy(.init(key: key(a), source: a, root: card.appendingPathComponent("DCIM"), folder: "d"), into: notAFolder, store: store()).why, IngestCopy.destinationGone)
        let bundle = card.appendingPathComponent("C0002.fcpbundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertTrue(IngestCopy.copy(.init(key: "", source: bundle, root: card, folder: "d"), into: lib, store: store()).ok, "a folder is copied whole (testAPackageIsCopiedWhole)")
        let link = card.appendingPathComponent("C4815.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("elsewhere.mp4"))
        XCTAssertEqual(IngestCopy.copy(.init(key: "", source: link, root: card, folder: "d"), into: lib, store: store()).why, "a link, not copied")
    }

    func testTheCardSaysWhatIsStillOnlyOnIt() throws {
        let raw = try put("DCIM/100MSDCF/DSC01234.ARW", "raw")
        _ = try put("DCIM/100MSDCF/DSC01234.JPG", "jpeg")
        let orphan = try put("PRIVATE/M4ROOT/CLIP/C0009M01.XML", "<meta/>")
        _ = try put(".Spotlight-V100/store.db", "x"); _ = try put("DCIM/.DS_Store", "x"); _ = try put("DCIM/Thumbs.db", "x")
        let s = store()
        var copied = Set(IngestCopy.copy(.init(key: key(raw), source: raw, root: card, folder: "d"), into: lib, store: s).sources)
        XCTAssertEqual(IngestCopy.unaccounted(under: card, copied: copied), ["PRIVATE/M4ROOT/CLIP/C0009M01.XML"], "the sidecar with no clip is still only on the card; system files don't count")
        copied.formUnion(IngestCopy.copy(.init(key: "", source: orphan, root: card, folder: "Other"), into: lib, store: s).sources)
        XCTAssertEqual(IngestCopy.unaccounted(under: card, copied: copied), [])
    }

    func testTwoChosenFoldersOfOneNameBothAnswer() throws {
        let one = dir.appendingPathComponent("one/100MSDCF"), two = dir.appendingPathComponent("two/100MSDCF")
        for (d, t) in [(one, "first"), (two, "second")] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try Data(t.utf8).write(to: d.appendingPathComponent("DSC00001.ARW"))
        }
        let all = IngestCopy.resolveAll("100MSDCF/DSC00001.ARW", roots: [one, two])
        XCTAssertEqual(all.map { $0.file.path }, [two, one].map { $0.appendingPathComponent("DSC00001.ARW").path }, "newest choice first, both listed")
        let wanted = key(one.appendingPathComponent("DSC00001.ARW"))
        XCTAssertEqual(all.first { IngestCopy.pageKey($0.file) == wanted }?.file.deletingLastPathComponent().path, one.path)
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

    func testUsualFoldersAreRememberedNewestFirstAndForgotten() throws {
        let s = store()
        s.setFolder("/x/Library", bookmark: nil)
        s.record("k", .init(rel: "d/a.ARW", sha: "00", size: 3))
        for i in 0..<10 { s.remember(.init(path: "/trips/\(i)", name: "\(i)", bookmark: Data([UInt8(i)]), volume: nil)) }
        s.remember(.init(path: "/trips/7", name: "7", bookmark: Data([70]), volume: nil))
        XCTAssertEqual(s.places.count, IngestLibrary.maxPlaces)
        XCTAssertEqual(s.places.first?.bookmark, Data([70]), "chosen again: moved to the front, once")
        XCTAssertEqual(s.places.filter { $0.path == "/trips/7" }.count, 1)
        s.remember(.init(path: "/Volumes/Untitled", name: "Untitled", bookmark: Data([1]), volume: "UUID-A"))
        s.remember(.init(path: "/Volumes/Untitled 1", name: "Untitled", bookmark: Data([2]), volume: "UUID-A"))
        XCTAssertEqual(s.places.filter { $0.volume == "UUID-A" }.map(\.bookmark), [Data([2])], "one grant per card, by volume")
        try s.save()
        let t = store()
        XCTAssertEqual(t.places, s.places); XCTAssertEqual(t.count, 1, "the identities are untouched")
        t.forgetFolders()
        XCTAssertEqual(t.places.map(\.volume), ["UUID-A"], "folders forgotten, the card's grant kept")
        XCTAssertEqual(t.count, 1)
    }

    func testTheFolderPatternIsKeptAndItsFoldersAreSafe() throws {
        let s = store()
        s.setFolder("/x/Library", bookmark: nil)
        s.setPattern("  {year}/{start} {shoot}/{kind} ")
        try s.save()
        let t = store()
        XCTAssertEqual(t.pattern, "{year}/{start} {shoot}/{kind}")
        t.setFolder("/y/Other", bookmark: nil); XCTAssertEqual(t.pattern, "{year}/{start} {shoot}/{kind}", "another library keeps the owner's pattern")
        t.setPattern(String(repeating: "x", count: 500)); XCTAssertEqual(t.pattern?.count, IngestLibrary.maxPattern)
        t.setPattern(" "); XCTAssertNil(t.pattern, "cleared: plain dated folders")
        // what the page makes of a pattern (lumina-ingest-shoots.test.mjs) is taken as it is; anything else is refused
        for f in ["2026/2026-10-28 Death Valley/Photos", "2026/10/2026-10-29/ILCE-7M3", "Oct 28 – 30, 2026/Clips"] { XCTAssertEqual(IngestCopy.safeFolder(f), f) }
        for f in ["../x", "a/../b", ".hidden/x", "a/.b", "", "/"] { XCTAssertNil(IngestCopy.safeFolder(f), f) }
        let a = try put("A/DSC00001.ARW", "photo a")
        let r = IngestCopy.copy(.init(key: key(a), source: a, root: card, folder: "2026/2026-10-28 Death Valley/Photos"), into: lib, store: s)
        XCTAssertTrue(r.ok, r.why ?? ""); XCTAssertEqual(r.rel, "2026/2026-10-28 Death Valley/Photos/DSC00001.ARW")
    }

    func testAPackageIsCopiedWhole() throws {
        _ = try put("CLIP/Lib.fcpbundle/Day 1/CurrentVersion.fcpevent", "event")
        _ = try put("CLIP/Lib.fcpbundle/Settings.plist", "plist")
        _ = try put("CLIP/Lib.fcpbundle/.lock", "hidden, and the package's own")
        let pkg = card.appendingPathComponent("CLIP/Lib.fcpbundle")
        let fm = FileManager.default
        try fm.createDirectory(at: pkg.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        try fm.createDirectory(at: pkg.appendingPathComponent("Original Media"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: pkg.appendingPathComponent("Original Media/C4815.mp4").path, withDestinationPath: "/nowhere/C4815.mp4")
        let before = snapshot(card)
        let s = store()
        let r = IngestCopy.copy(.init(key: "", source: pkg, root: card, folder: "Other/SONY/CLIP"), into: lib, store: s)
        XCTAssertTrue(r.ok, r.why ?? ""); XCTAssertEqual(r.files, 3); XCTAssertFalse(r.already)
        XCTAssertEqual(r.rel, "Other/SONY/CLIP/Lib.fcpbundle"); XCTAssertEqual(r.sources, [pkg.standardizedFileURL.path])
        let out = lib.appendingPathComponent("Other/SONY/CLIP/Lib.fcpbundle")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("Day 1/CurrentVersion.fcpevent"), encoding: .utf8), "event")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent(".lock"), encoding: .utf8), "hidden, and the package's own")
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("Empty").path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: out.appendingPathComponent("Original Media/C4815.mp4").path), "/nowhere/C4815.mp4", "a link stays a link")
        XCTAssertEqual(snapshot(card), before, "the source is never written")
        XCTAssertTrue(IngestCopy.copy(.init(key: "", source: pkg, root: card, folder: "Other/SONY/CLIP"), into: lib, store: s).already, "again: already here")
        // the card's own count: everything inside the package is accounted for, the broken link included
        _ = try put("CLIP/C0001.MP4", "a clip beside it")
        XCTAssertEqual(IngestCopy.unaccounted(under: card, copied: Set(r.sources)), ["CLIP/C0001.MP4"])
        // another package of that name is never mixed into
        _ = try put("B/Lib.fcpbundle/Settings.plist", "another library")
        let other = IngestCopy.copy(.init(key: "", source: card.appendingPathComponent("B/Lib.fcpbundle"), root: card, folder: "Other/SONY/CLIP"), into: lib, store: s)
        XCTAssertTrue(other.ok, other.why ?? ""); XCTAssertEqual(other.rel, "Other/SONY/CLIP/Lib-2.fcpbundle")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("Settings.plist"), encoding: .utf8), "plist", "the first is as it was")
        // a package dropped as it is: the page names it by its own name
        let found = IngestCopy.resolveAll("Lib.fcpbundle", roots: [pkg])
        XCTAssertEqual(found.map { $0.file.path }, [pkg.path]); XCTAssertEqual(found.first?.root.path, pkg.path)
        XCTAssertTrue(IngestCopy.resolveAll("Other.fcpbundle", roots: [pkg]).isEmpty)
    }

    func testOnlyAVolumesRootIsAWholeCard() throws {
        XCTAssertTrue(IngestCopy.isVolumeRoot(URL(fileURLWithPath: "/")))
        XCTAssertFalse(IngestCopy.isVolumeRoot(card), "a folder is never the whole card")
        XCTAssertFalse(IngestCopy.isVolumeRoot(card.appendingPathComponent("DCIM")))
    }
}
