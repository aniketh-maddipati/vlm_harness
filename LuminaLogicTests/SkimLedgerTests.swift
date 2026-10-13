import XCTest
@testable import Lumina

/// Export's note of the files it saved (`SkimLedger`): each file with the clips it holds, its state on disk (there, changed
/// since, gone, in the Trash, or where Lumina may not look), Forget that leaves the file alone, and Move to Trash only for a
/// file unchanged since it was saved, with Put back. Foundation only; the Trash is a folder here.
final class SkimLedgerTests: XCTestCase {
    private var tmp: URL!, out: URL!, bin: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-ledger-\(UUID().uuidString)", isDirectory: true)
        out = tmp.appendingPathComponent("Exports", isDirectory: true); bin = tmp.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private var ledger: SkimLedger {
        let bin = self.bin!
        return SkimLedger(file: tmp.appendingPathComponent("skim/exports.json")) { u in
            let to = bin.appendingPathComponent(u.lastPathComponent)
            try FileManager.default.moveItem(at: u, to: to)
            return to
        }
    }
    private func write(_ name: String, _ text: String = "<fcpxml/>") throws -> String {
        let u = out.appendingPathComponent(name); try Data(text.utf8).write(to: u); return u.path
    }

    func testASavedFileIsNotedWithItsClipsAndState() throws {
        let p = try write("Day 1.fcpxml")
        let e = try XCTUnwrap(ledger.record(path: p, kind: "fcpxml", shoot: "dump", clips: ["/v/C0001.MP4": "keep", "/v/C0002.MP4": "maybe", "/v/x": "bogus"], opts: ["maybes": true], bookmark: nil, now: 1000))
        XCTAssertEqual(e.clips, ["/v/C0001.MP4": "keep", "/v/C0002.MP4": "maybe"], "only marks the page writes")
        XCTAssertEqual(ledger.entries(shoot: "dump").map(\.id), [e.id])
        XCTAssertTrue(ledger.entries(shoot: "other").isEmpty)
        XCTAssertEqual(SkimLedger.state(e, at: URL(fileURLWithPath: p)), .here)
        XCTAssertEqual(SkimLedger.state(e, at: nil), .unknown)
        XCTAssertNil(ledger.record(path: p, kind: "zip", shoot: "dump", clips: [:], opts: [:], bookmark: nil), "only the kinds Export saves")
        XCTAssertNil(ledger.record(path: out.appendingPathComponent("none.fcpxml").path, kind: "fcpxml", shoot: "dump", clips: [:], opts: [:], bookmark: nil), "only a file that is there")

        try Data("<fcpxml>edited</fcpxml>".utf8).write(to: URL(fileURLWithPath: p))
        XCTAssertEqual(SkimLedger.state(e, at: URL(fileURLWithPath: p)), .changed)
        try FileManager.default.removeItem(atPath: p)
        XCTAssertEqual(SkimLedger.state(e, at: URL(fileURLWithPath: p)), .gone)
    }

    func testForgetLeavesTheFile() throws {
        let p = try write("Day 1.fcpxml")
        let e = try XCTUnwrap(ledger.record(path: p, kind: "fcpxml", shoot: "dump", clips: [:], opts: [:], bookmark: nil))
        XCTAssertTrue(ledger.forget(e.id))
        XCTAssertTrue(ledger.all().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
        XCTAssertFalse(ledger.forget(e.id))
    }

    func testTrashOnlyWhatIsUnchangedAndPutItBack() throws {
        let p = try write("Day 1 cut clips.txt", "2 cut clips")
        let e = try XCTUnwrap(ledger.record(path: p, kind: "cut", shoot: "dump", clips: ["/v/C0003.MP4": "cut"], opts: [:], bookmark: nil))
        let at = URL(fileURLWithPath: p)
        XCTAssertEqual(ledger.moveToTrash(e.id, at: nil).ok, false, "not where Lumina may not look")
        XCTAssertTrue(ledger.moveToTrash(e.id, at: at).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: p))
        let t = try XCTUnwrap(ledger.entry(e.id))
        XCTAssertEqual(SkimLedger.state(t, at: at), .trashed)
        XCTAssertFalse(ledger.moveToTrash(e.id, at: at).ok, "once")

        try Data("someone else".utf8).write(to: at)
        XCTAssertEqual(ledger.putBack(e.id).why, "A file is already where it was.")
        try FileManager.default.removeItem(at: at)
        XCTAssertTrue(ledger.putBack(e.id).ok)
        XCTAssertEqual(try String(contentsOfFile: p, encoding: .utf8), "2 cut clips")
        XCTAssertEqual(SkimLedger.state(try XCTUnwrap(ledger.entry(e.id)), at: at), .here)

        try Data("edited".utf8).write(to: at)
        XCTAssertEqual(ledger.moveToTrash(e.id, at: at).why, "It changed after Lumina saved it, so Lumina leaves it alone.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
    }

    func testAMovedFileIsFollowed() throws {
        let p = try write("Day 1.fcpxml")
        let e = try XCTUnwrap(ledger.record(path: p, kind: "fcpxml", shoot: "dump", clips: [:], opts: [:], bookmark: nil))
        let q = out.appendingPathComponent("Day 1 final.fcpxml").path
        try FileManager.default.moveItem(atPath: p, toPath: q)
        XCTAssertEqual(SkimLedger.state(e, at: URL(fileURLWithPath: q)), .here)
        ledger.moved(e.id, to: q)
        XCTAssertEqual(ledger.entry(e.id)?.path, q)
    }
}
