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
}
