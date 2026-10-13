import XCTest
@testable import Lumina

/// Export ▸ Workshop (`SkimPlaces`): the kept folders list, the folders inside one (no files, nothing hidden, no packages
/// or links), what counts as inside a folder Skim was let into, and a new folder that never replaces one. Foundation only.
final class SkimPlacesTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-places-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testKeptFoldersNewestFirstOncePerPath() {
        let s = SkimPlaces(file: tmp.appendingPathComponent("skim/places.json"))
        XCTAssertEqual(s.all(), [])
        XCTAssertTrue(s.add(.init(bookmark: Data([1]), path: "/a")))
        XCTAssertTrue(s.add(.init(bookmark: Data([2]), path: "/b")))
        XCTAssertTrue(s.add(.init(bookmark: Data([3]), path: "/a")))
        XCTAssertEqual(s.all().map(\.path), ["/a", "/b"])
        XCTAssertEqual(s.all().first?.bookmark, Data([3]), "the newer bookmark replaces the older")
        for i in 0..<30 { s.add(.init(bookmark: Data(), path: "/p\(i)")) }
        XCTAssertEqual(s.all().count, 24)
        XCTAssertTrue(s.remove(path: "/p29"))
        XCTAssertFalse(s.all().contains { $0.path == "/p29" })
    }

    func testInsideNeverMatchesASiblingWithTheSamePrefix() {
        let root = URL(fileURLWithPath: "/Volumes/T7/Exports")
        XCTAssertTrue(SkimPlaces.inside("/Volumes/T7/Exports", root: root))
        XCTAssertTrue(SkimPlaces.inside("/Volumes/T7/Exports/Tuesday", root: root))
        XCTAssertFalse(SkimPlaces.inside("/Volumes/T7/Exports 2", root: root))
        XCTAssertFalse(SkimPlaces.inside("/Volumes/T7/Exports/../Other", root: root), "no way out through ..")
        XCTAssertFalse(SkimPlaces.inside("/Volumes/T7", root: root))
    }

    func testFoldersListsFoldersOnlyByName() throws {
        let fm = FileManager.default
        for d in ["b", "A", "c/inner", ".hidden", "Lib.app"] { try fm.createDirectory(at: tmp.appendingPathComponent(d), withIntermediateDirectories: true) }
        try Data("x".utf8).write(to: tmp.appendingPathComponent("file.txt"))
        try fm.createSymbolicLink(at: tmp.appendingPathComponent("link"), withDestinationURL: tmp.appendingPathComponent("b"))
        let got = try XCTUnwrap(SkimPlaces.folders(in: tmp))
        #if os(macOS)
        XCTAssertEqual(got.map(\.name), ["A", "b", "c"], "no files, nothing hidden, no packages or links")
        #else
        XCTAssertEqual(got.map(\.name).filter { $0 != "Lib.app" }, ["A", "b", "c"], "no files, nothing hidden, no links")
        #endif
        XCTAssertEqual(got.first { $0.name == "c" }?.dirs, true)
        XCTAssertEqual(got.first { $0.name == "b" }?.dirs, false)
        XCTAssertNil(SkimPlaces.folders(in: tmp.appendingPathComponent("gone")))
    }

    func testEntriesListFoldersThenFilesWithSizes() throws {
        let fm = FileManager.default
        for d in ["Z", "a/inner", ".hidden"] { try fm.createDirectory(at: tmp.appendingPathComponent(d), withIntermediateDirectories: true) }
        try Data(count: 1234).write(to: tmp.appendingPathComponent("C0002.MP4"))
        try Data(count: 10).write(to: tmp.appendingPathComponent("C0001M01.XML"))
        try Data().write(to: tmp.appendingPathComponent(".DS_Store"))
        try fm.createSymbolicLink(at: tmp.appendingPathComponent("link"), withDestinationURL: tmp.appendingPathComponent("Z"))
        let got = try XCTUnwrap(SkimPlaces.entries(in: tmp))
        XCTAssertEqual(got.map(\.name), ["a", "Z", "C0001M01.XML", "C0002.MP4"], "folders first, then files, by name; nothing hidden, no links")
        XCTAssertEqual(got.first { $0.name == "C0002.MP4" }?.bytes, 1234)
        XCTAssertEqual(got.first { $0.name == "a" }?.dirs, true)
        XCTAssertEqual(got.first { $0.name == "Z" }?.dirs, false)
        XCTAssertNil(SkimPlaces.entries(in: tmp.appendingPathComponent("gone")))
    }

    func testANewFolderHasAPlainNameAndNeverReplacesOne() throws {
        XCTAssertEqual(SkimPlaces.folderName("  Tuesday / export: ok "), "Tuesday  export ok")
        XCTAssertEqual(SkimPlaces.folderName("...dots"), "dots")
        XCTAssertNil(SkimPlaces.folderName(" / : "))
        XCTAssertEqual(SkimPlaces.folderName(String(repeating: "a", count: 300))?.count, 120)
        let one = SkimPlaces.make("Tuesday", in: tmp)
        XCTAssertTrue(one.ok); XCTAssertEqual(one.path, tmp.appendingPathComponent("Tuesday", isDirectory: true).path)
        try Data("keep".utf8).write(to: tmp.appendingPathComponent("Tuesday/a.txt"))
        let two = SkimPlaces.make("Tuesday", in: tmp)
        XCTAssertFalse(two.ok); XCTAssertTrue(two.why.contains("already there"))
        XCTAssertEqual(try String(contentsOf: tmp.appendingPathComponent("Tuesday/a.txt"), encoding: .utf8), "keep", "the folder there is untouched")
        XCTAssertFalse(SkimPlaces.make("x", in: tmp.appendingPathComponent("gone")).ok)
        XCTAssertFalse(SkimPlaces.make("../escape", in: tmp).path.contains(".."))
    }

    func testHasInsideStopsAtTheFirstMatchAndSkipsHiddenOnes() throws {
        let fm = FileManager.default, a = tmp.appendingPathComponent("a"), b = tmp.appendingPathComponent("b"), c = tmp.appendingPathComponent("c")
        for d in [a, b, c] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data().write(to: a.appendingPathComponent(".DS_Store"))
        XCTAssertFalse(SkimPlaces.hasInside(a, folders: false), "only hidden files: nothing inside")
        for i in 0..<20 { try Data().write(to: b.appendingPathComponent("C\(i).MP4")) }
        XCTAssertTrue(SkimPlaces.hasInside(b, folders: false))
        XCTAssertFalse(SkimPlaces.hasInside(b, folders: true), "files, no folder")
        try fm.createDirectory(at: c.appendingPathComponent("CLIP"), withIntermediateDirectories: true)
        XCTAssertTrue(SkimPlaces.hasInside(c, folders: true))
        XCTAssertEqual(SkimPlaces.entries(in: tmp)?.map { [$0.name, String($0.dirs)] }, [["a", "false"], ["b", "true"], ["c", "true"]])
    }

    func testDrivesListTheMacsOwnFirstThenByName() {
        let d = { (n: String, p: String) in SkimPlacesRead.Drive(name: n, path: p, card: false, readOnly: false, ejectable: p != "/", granted: false, total: nil, free: nil) }
        XCTAssertEqual(SkimPlacesRead.sorted([d("T7", "/Volumes/T7"), d("Macintosh HD", "/"), d("card 2", "/Volumes/c2"), d("Card 10", "/Volumes/c10")]).map(\.name),
                       ["Macintosh HD", "card 2", "Card 10", "T7"])
        XCTAssertNil(d("x", "/x").json["free"], "no figure, no key")
    }

    func testFindLooksThroughEveryLevelForEveryWordAndRanksPrefixesAndShallowFirst() throws {
        let fm = FileManager.default
        for d in ["Shoots/2026 Café wedding/CLIP", "Shoots/Wedding B-roll", "Archive/old/deep/wedding day", ".hidden/wedding", "Clips.fcpbundle/wedding"] {
            try fm.createDirectory(at: tmp.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try Data().write(to: tmp.appendingPathComponent("Shoots/wedding.mp4"))
        let r = SkimPlaces.find("wedding", in: [tmp])
        XCTAssertEqual(r.found.map(\.name), ["Wedding B-roll", "wedding day", "2026 Café wedding"], "prefix first, then shallower; no file, nothing hidden, no package")
        XCTAssertFalse(r.partial)
        XCTAssertEqual(r.found.first?.root, tmp.standardizedFileURL.path)
        XCTAssertEqual(SkimPlaces.find("cafe WEDDING", in: [tmp]).found.map(\.name), ["2026 Café wedding"], "every word, any case, accents off")
        XCTAssertEqual(SkimPlaces.find("  ", in: [tmp]).found, [])
        XCTAssertTrue(SkimPlaces.find("wedding", in: [tmp], limit: 1).partial, "stopped at the limit")
        XCTAssertTrue(SkimPlaces.find("wedding", in: [tmp], cancelled: { true }).partial)
        XCTAssertEqual(SkimPlaces.find("wedding", in: [tmp, tmp.appendingPathComponent("Shoots")]).found.count, 3, "a folder under two roots is found once")
    }
}
