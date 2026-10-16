import XCTest
@testable import Lumina

/// Handoff's file view on the Mac (`PickFiles`, Prompt 27): which drives Lumina may look inside, listings that open no
/// sub-folder, the search a page at a time, copies (RAW and sidecar, read back, never over a file), renames, the Saved
/// files check, sidecars into a Save to folder, and the note of what Handoff wrote. Foundation only.
final class PickFilesTests: XCTestCase {
    private let fm = FileManager.default
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("pick-files-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    private func dir(_ rel: String) throws -> URL {
        let u = tmp.appendingPathComponent(rel, isDirectory: true)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func file(_ rel: String, _ text: String = "x") throws -> URL {
        let u = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
        return u
    }

    func testADriveWithAFolderLetInReadsAsSome() throws {
        let drive = try dir("Volumes/T7"), shoots = try dir("Volumes/T7/Shoots"), inner = try dir("Volumes/T7/Shoots/Tuesday"), other = try dir("Volumes/Other")
        XCTAssertEqual(PickFiles.access(drive: drive.path, roots: [drive]), .all)
        XCTAssertEqual(PickFiles.access(drive: drive.path, roots: [shoots, inner]), .some)
        XCTAssertEqual(PickFiles.access(drive: drive.path, roots: [other]), .none)
        XCTAssertEqual(PickFiles.Access.some.json as? String, "some")
        XCTAssertEqual(PickFiles.rootsOn(drive: drive.path, roots: [inner, shoots, other]).map(\.path), [shoots.path], "a folder inside another one let in is reached through it")
        XCTAssertEqual(PickFiles.listSome([shoots]).first?["dirs"] as? Bool, true)
    }

    func testListingOpensNoSubfolder() throws {
        let d = try dir("shoot")
        _ = try dir("shoot/b"); _ = try dir("shoot/A"); _ = try dir("shoot/.hidden"); _ = try dir("shoot/empty")
        _ = try file("shoot/DSC0002.ARW", "12345"); _ = try file("shoot/DSC0001.ARW", "1")
        let l = try XCTUnwrap(PickFiles.list(d)).map(\.json)
        XCTAssertEqual(l.map { $0["name"] as? String }, ["A", "b", "empty", "DSC0001.ARW", "DSC0002.ARW"], "folders first, then files, by name, nothing hidden")
        XCTAssertEqual(l[2]["dirs"] as? Bool, true, "a folder is not opened to see whether it is empty")
        XCTAssertEqual(l[4]["file"] as? Bool, true)
        XCTAssertEqual(l[4]["bytes"] as? Int64, 5)
        XCTAssertNil(PickFiles.list(tmp.appendingPathComponent("nope")))
    }

    func testSearchAnswersAPageAtATimeShallowFirst() throws {
        let root = try dir("root")
        for i in 0..<5 { _ = try dir("root/Wedding \(i)") }
        _ = try dir("root/deep/deeper/wedding-late"); _ = try dir("root/.hidden/wedding"); _ = try dir("root/Library.app/wedding")
        let s = PickFiles.Search("WEDDING", roots: [root])
        let p1 = s.next(limit: 3, budget: 5)
        XCTAssertEqual(p1.hits.count, 3)
        XCTAssertFalse(p1.done)
        var all = p1.hits
        var done = false
        for _ in 0..<10 where !done { let p = s.next(limit: 3, budget: 5); all += p.hits; done = p.done }
        XCTAssertTrue(done)
        XCTAssertEqual(all.compactMap { $0["name"] }, ["Wedding 0", "Wedding 1", "Wedding 2", "Wedding 3", "Wedding 4", "wedding-late"], "breadth first, no hidden folder or package")
        XCTAssertEqual(PickFiles.Search("  ", roots: [root]).next(limit: 10, budget: 1).hits.count, 0)
    }

    func testCopyTakesTheSidecarAndNeverWritesOverAFile() throws {
        let raw = try file("shoot/DSC0001.ARW", "raw-bytes"), _ = try file("shoot/DSC0001.xmp", "<xmp/>")
        let dest = try dir("dest")
        let a = PickFiles.copy(raw: raw, into: dest)
        XCTAssertEqual(a.to, dest.appendingPathComponent("DSC0001.ARW").path)
        XCTAssertEqual(a.made.count, 2)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("DSC0001.xmp"), encoding: .utf8), "<xmp/>")
        let b = PickFiles.copy(raw: raw, into: dest)
        XCTAssertEqual(b.to, dest.appendingPathComponent("DSC0001 2.ARW").path, "a name already there gets “ 2”")
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("DSC0001 2.xmp").path), "the sidecar follows the RAW's new name")
        XCTAssertEqual(try String(contentsOf: raw, encoding: .utf8), "raw-bytes", "the original is untouched")
        XCTAssertNil(PickFiles.copy(raw: raw, into: raw.deletingLastPathComponent()).to, "never into its own folder")
        XCTAssertNil(PickFiles.copy(raw: tmp.appendingPathComponent("gone.ARW"), into: dest).to)
    }

    func testCopyOfAPhotoWithoutASidecarLeavesNone() throws {
        let raw = try file("shoot/DSC0009.ARW"), dest = try dir("dest")
        _ = try file("dest/DSC0009.xmp", "someone else's")
        let r = PickFiles.copy(raw: raw, into: dest)
        XCTAssertEqual(r.made, [dest.appendingPathComponent("DSC0009.ARW").path])
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("DSC0009.xmp"), encoding: .utf8), "someone else's")
    }

    func testRenameStaysInPlaceAndRefusesRootsAndTheShoot() throws {
        let root = try dir("root"), a = try dir("root/a"), shoot = try dir("root/b/shoot"), _ = try dir("root/c")
        XCTAssertFalse(PickFiles.rename(a.path, to: "c", roots: [root], shoot: shoot).ok, "never over a folder")
        let r = PickFiles.rename(a.path, to: "Tuesday", roots: [root], shoot: shoot)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.path, root.appendingPathComponent("Tuesday").path)
        XCTAssertTrue(PickFiles.rename(r.path, to: "TUESDAY", roots: [root], shoot: shoot).ok, "a change of case only")
        XCTAssertFalse(PickFiles.rename(root.path, to: "x", roots: [root], shoot: nil).ok, "a folder Lumina was let into")
        XCTAssertFalse(PickFiles.rename(root.appendingPathComponent("b").path, to: "x", roots: [root], shoot: shoot).ok, "it holds the open shoot")
        XCTAssertEqual(PickFiles.rename(root.appendingPathComponent("c").path, to: "../y", roots: [root], shoot: nil).path, root.appendingPathComponent("y").path, "a name, never a path")
        XCTAssertFalse(PickFiles.rename(tmp.path, to: "x", roots: [root], shoot: nil).ok, "outside what Lumina may look inside")
    }

    func testSavedCheck() throws {
        let f = try file("out/DSC0001.xmp")
        let before = Date().timeIntervalSince1970 * 1000
        XCTAssertEqual(PickFiles.check([f.path], at: before), "ok")
        XCTAssertEqual(PickFiles.check([tmp.appendingPathComponent("nope").path], at: before), "missing")
        XCTAssertEqual(PickFiles.check([f.path], at: before - 60_000), "edited")
    }

    func testSidecarIntoASaveToFolderKeepsABackupAndStaysInside() throws {
        let to = try dir("saveto")
        _ = try file("saveto/sub/DSC0001.xmp", "old")
        let r = try PickFiles.writeSidecar(Data("new".utf8), rel: "sub/DSC0001.xmp", into: to)
        XCTAssertTrue(r.backedUp)
        XCTAssertEqual(try String(contentsOf: to.appendingPathComponent("sub/DSC0001.xmp"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: to.appendingPathComponent("sub/DSC0001.xmp.lumina-bak"), encoding: .utf8), "old")
        try PickFiles.writeSidecar(Data("x".utf8), rel: "new/DSC0002.xmp", into: to)
        XCTAssertTrue(fm.fileExists(atPath: to.appendingPathComponent("new/DSC0002.xmp").path), "the folders it names are made")
        for bad in ["../DSC0003.xmp", "/etc/DSC0003.xmp", "DSC0003.ARW", "a//b.xmp", "./b.xmp"] {
            XCTAssertThrowsError(try PickFiles.writeSidecar(Data("x".utf8), rel: bad, into: to), bad)
        }
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("DSC0003.xmp").path))
    }

    func testSidecarThroughALinkedFolderMakesNoFolderOutside() throws {
        let to = try dir("saveto2"), outside = try dir("elsewhere")
        try fm.createSymbolicLink(at: to.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try PickFiles.writeSidecar(Data("x".utf8), rel: "link/made/DSC0004.xmp", into: to))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("made").path), "refused before any folder is made")
    }

    func testTheNoteOfWrittenFilesAndSaveTo() throws {
        let w = PickFiles.Written(file: tmp.appendingPathComponent("pick/written.json"))
        XCTAssertEqual(w.all(), [])
        w.add(["/a", "/b"]); w.add(["/a"])
        XCTAssertEqual(w.all(), ["/a", "/b"])
        let s = PickFiles.SaveToStore(file: tmp.appendingPathComponent("pick/saveto.json"))
        XCTAssertEqual(s.get(), PickFiles.SaveTo())
        s.set(.init(ask: true)); XCTAssertTrue(s.get().ask)
        s.set(.init(ask: false, bookmark: Data([1]), path: "/x")); XCTAssertEqual(s.get().path, "/x")
    }
}
