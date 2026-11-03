import XCTest
@testable import Lumina

/// Export ▸ Save to (`SkimExport`): the page's suggested name becomes one plain .fcpxml or .txt name, a save never
/// replaces a file (a taken name gets " 2", " 3"), what was written reads back, and the kept folder can be forgotten.
/// Foundation only.
final class SkimExportTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testOnlyPlainFinalCutAndTextNamesAreSaved() {
        XCTAssertEqual(SkimExport.safeName("Trip day 2.fcpxml"), "Trip day 2.fcpxml")
        XCTAssertEqual(SkimExport.safeName("../../Library/x.fcpxml"), "x.fcpxml", "no folders")
        XCTAssertEqual(SkimExport.safeName("..hidden.txt"), "hidden.txt", "no leading dot")
        XCTAssertEqual(SkimExport.safeName("a:b\u{7}.TXT"), "ab.TXT")
        for bad in ["x.sh", "x", ".fcpxml", "", "x.fcpxml/"] { XCTAssertNil(SkimExport.safeName(bad), bad) }
        XCTAssertEqual(SkimExport.safeName(String(repeating: "a", count: 300) + ".fcpxml")?.count, 127)
    }

    func testASaveNeverReplacesAFile() throws {
        let one = SkimExport.save("<fcpxml/>", name: "Trip.fcpxml", into: tmp)
        XCTAssertTrue(one.ok); XCTAssertEqual((one.path as NSString).lastPathComponent, "Trip.fcpxml")
        let two = SkimExport.save("second", name: "Trip.fcpxml", into: tmp)
        XCTAssertTrue(two.ok); XCTAssertEqual((two.path as NSString).lastPathComponent, "Trip 2.fcpxml")
        XCTAssertEqual(try String(contentsOfFile: one.path, encoding: .utf8), "<fcpxml/>", "the first file is untouched")
        XCTAssertEqual(try String(contentsOfFile: two.path, encoding: .utf8), "second")
        XCTAssertEqual(two.json["folder"] as? String, tmp.path)
        let direct = SkimExport.write("again", to: URL(fileURLWithPath: one.path))
        XCTAssertFalse(direct.ok, "writing over a file the panel handed back fails rather than replacing it")
    }

    func testAMissingFolderOrABadNameSaysWhy() {
        XCTAssertFalse(SkimExport.save("x", name: "a.fcpxml", into: tmp.appendingPathComponent("gone")).ok)
        XCTAssertFalse(SkimExport.save("x", name: "a.exe", into: tmp).ok)
        let big = SkimExport.save(String(repeating: "x", count: SkimExport.maxBytes + 1), name: "a.txt", into: tmp)
        XCTAssertFalse(big.ok); XCTAssertFalse(big.why.isEmpty)
    }

    func testTheFolderIsKeptAndForgotten() {
        let store = SkimExport(file: tmp.appendingPathComponent("skim/export.json"))
        XCTAssertNil(store.place())
        XCTAssertTrue(store.set(.init(bookmark: Data([1, 2, 3]), path: "/Volumes/T7/Exports")))
        XCTAssertEqual(store.place()?.path, "/Volumes/T7/Exports")
        XCTAssertTrue(store.set(nil))
        XCTAssertNil(store.place())
    }

    func testTheCheckFindsTheClipFilesAndOnlyLooksInsideTheOpenedFolder() throws {
        let dump = tmp.appendingPathComponent("my dump", isDirectory: true)
        try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
        try Data(count: 10).write(to: dump.appendingPathComponent("C0001.MP4"))
        let here = dump.appendingPathComponent("C0001.MP4").path, gone = dump.appendingPathComponent("C0002.MP4").path
        let text = """
        <asset id="a1"><media-rep kind="original-media" src="file://\(here.replacingOccurrences(of: " ", with: "%20"))"/></asset>
        <asset id="a2"><media-rep kind="original-media" src="file://\(gone.replacingOccurrences(of: " ", with: "%20"))"/></asset>
        <asset id="a3"><media-rep kind="original-media" src="file:///Volumes/Elsewhere/C0003.MP4"/></asset>
        <asset id="a4"><media-rep kind="original-media" src="file://\(here.replacingOccurrences(of: " ", with: "%20"))"/></asset>
        """
        let paths = SkimExport.mediaPaths(text)
        XCTAssertEqual(paths, [here, gone, "/Volumes/Elsewhere/C0003.MP4"], "each file once, decoded")
        let m = SkimExport.missing(paths, inside: dump)
        XCTAssertEqual(m.missing, [gone]); XCTAssertEqual(m.unchecked, 1, "outside the opened folder: not looked for, not called missing")
        XCTAssertEqual(SkimExport.missing(paths, inside: nil).unchecked, 3)
        XCTAssertNil(SkimExport.dtd(in: tmp, version: "1.10"), "no Final Cut here")
        XCTAssertNil(SkimExport.dtd(in: tmp, version: "../x"))
    }

    // Looks: one cube per clip in Final Cut's Custom LUTs folder, at the place the .fcpxml names (measured on Final Cut 12.4:
    // its Custom LUT effect reads only from that folder).
    func testACubeGoesUnderLuminaSkimInFinalCutsFolderAndIsNeverReplaced() throws {
        let root = tmp.appendingPathComponent("Custom LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cube = "TITLE \"C0001 a1b2c3\"\nLUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
        let one = SkimExport.installLUT(cube, rel: "Lumina Skim/Day 1/C0001 a1b2c3.cube", into: root)
        XCTAssertTrue(one.ok, one.why)
        XCTAssertEqual(one.path, root.appendingPathComponent("Lumina Skim/Day 1/C0001 a1b2c3.cube").path)
        XCTAssertEqual(try String(contentsOfFile: one.path, encoding: .utf8), cube)
        XCTAssertTrue(SkimExport.installLUT(cube, rel: "Lumina Skim/Day 1/C0001 a1b2c3.cube", into: root).ok, "the same cube again: already there")
        let other = SkimExport.installLUT(cube + "\n", rel: "Lumina Skim/Day 1/C0001 a1b2c3.cube", into: root)
        XCTAssertFalse(other.ok, "a different file of that name stays")
        XCTAssertEqual(try String(contentsOfFile: one.path, encoding: .utf8), cube)
        XCTAssertEqual(SkimExport.safeName("C0001 a1b2c3.cube"), "C0001 a1b2c3.cube", "a cube is saved beside the .fcpxml too")
    }

    func testOnlyLuminaSkimPlacesAndCubeTextAreWritten() {
        let root = tmp.appendingPathComponent("Custom LUTs", isDirectory: true), cube = "LUT_3D_SIZE 2\n"
        for rel in ["x.cube", "Other/Day/x.cube", "Lumina Skim/x.cube", "Lumina Skim/../x.cube", "Lumina Skim/Day/../x.cube", "Lumina Skim/.hid/x.cube",
                    "Lumina Skim/Day/x.txt", "Lumina Skim/Day/a:b.cube", "Lumina Skim/Day/sub/x.cube", "/Lumina Skim/Day/x.cube", "Lumina Skim//x.cube"] {
            XCTAssertNil(SkimExport.lutPlace(rel), rel)
            XCTAssertFalse(SkimExport.installLUT(cube, rel: rel, into: root).ok, rel)
        }
        XCTAssertFalse(SkimExport.installLUT("<fcpxml/>", rel: "Lumina Skim/Day/x.cube", into: root).ok, "not a cube")
        XCTAssertNotNil(SkimExport.lutPlace("Lumina Skim/Café · 夕方/C0007 a1b2c3.cube"))
        XCTAssertEqual(SkimExport.finalCutLUTs(home: URL(fileURLWithPath: "/Users/me")).path, "/Users/me/Library/Application Support/ProApps/Custom LUTs")
    }
}
