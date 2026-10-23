import XCTest
@testable import Lumina

/// Move cut to Trash (`SkimTrash`, STORAGE.md item 3): only files inside the opened folder move, with their Sony
/// sidecars, through the Trash (here a stand-in folder), never on a card or a read-only drive; each move is noted
/// so Put back returns it while it is still in the Trash, and the sums are what moved. Foundation only.
final class SkimTrashTests: XCTestCase {
    private var tmp: URL!, root: URL!, bin: URL!, log: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-trash-\(UUID().uuidString)", isDirectory: true)
        root = tmp.appendingPathComponent("friend_dump", isDirectory: true); bin = tmp.appendingPathComponent("Trash", isDirectory: true); log = tmp.appendingPathComponent("skim/trash.json")
        for d in [root!, bin!, root.appendingPathComponent("CLIP")] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data(count: 10_000).write(to: root.appendingPathComponent("CLIP/C0001.MP4"))
        try Data(count: 300).write(to: root.appendingPathComponent("CLIP/C0001M01.XML"))
        try Data(count: 20_000).write(to: root.appendingPathComponent("CLIP/C0002.MP4"))
        try Data(count: 5).write(to: tmp.appendingPathComponent("outside.MP4"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// The Trash, stood in for by a folder: what FileManager.trashItem does, a move that answers where it went.
    private func trash() -> SkimTrash {
        let bin = bin!
        return SkimTrash(log: log, trash: { u in let to = bin.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent); try FileManager.default.moveItem(at: u, to: to); return to })
    }

    func testOnlyFilesInsideTheOpenedFolderResolve() throws {
        XCTAssertEqual(SkimTrash.resolve(root: root, rel: "friend_dump/CLIP/C0001.MP4")?.lastPathComponent, "C0001.MP4", "the page's path starts with the folder's own name")
        XCTAssertEqual(SkimTrash.resolve(root: root, rel: "CLIP/C0002.MP4")?.lastPathComponent, "C0002.MP4")
        for bad in ["../outside.MP4", "friend_dump/../outside.MP4", "/etc/hosts", "CLIP", "CLIP/missing.MP4", "", "CLIP/./C0001.MP4"] { XCTAssertNil(SkimTrash.resolve(root: root, rel: bad), bad) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("CLIP/link.MP4"), withDestinationURL: tmp.appendingPathComponent("outside.MP4"))
        XCTAssertNil(SkimTrash.resolve(root: root, rel: "CLIP/link.MP4"), "a link out of the folder is not followed")
    }

    func testTheOpenedFolderIsTheFolderPickedOrTheOneTheClipsShare() {
        let clip = root.appendingPathComponent("CLIP")
        XCTAssertEqual(SkimTrash.folder(of: [root])?.path, root.standardizedFileURL.path, "a folder picked alone is itself")
        XCTAssertEqual(SkimTrash.folder(of: [clip.appendingPathComponent("C0001.MP4"), clip.appendingPathComponent("C0002.MP4")])?.path, clip.standardizedFileURL.path, "clips: their folder")
        XCTAssertEqual(SkimTrash.folder(of: [clip.appendingPathComponent("C0001.MP4"), tmp.appendingPathComponent("outside.MP4")])?.path, tmp.standardizedFileURL.path, "the folder they share")
        XCTAssertEqual(SkimTrash.folder(of: [clip.appendingPathComponent("C0001.MP4")])?.path, clip.standardizedFileURL.path, "one clip: its folder")
        XCTAssertNil(SkimTrash.folder(of: []))
    }

    func testTheSidecarTravelsWithItsClip() {
        XCTAssertEqual(SkimTrash.companions(of: root.appendingPathComponent("CLIP/C0001.MP4")).map(\.lastPathComponent), ["C0001M01.XML"])
        XCTAssertEqual(SkimTrash.companions(of: root.appendingPathComponent("CLIP/C0002.MP4")), [])
    }

    func testAMoveGoesToTheTrashAndPutBackReturnsIt() {
        let t = trash()
        let out = t.move(root: root, rels: ["friend_dump/CLIP/C0001.MP4", "CLIP/C0002.MP4", "../outside.MP4"], shoot: "s", refusal: nil)
        XCTAssertEqual(out.map(\.ok), [true, true, false])
        XCTAssertEqual(out[0].bytes, 10_300, "the clip and its sidecar"); XCTAssertEqual(out[1].bytes, 20_000)
        XCTAssertEqual(out[2].why, "not in the opened folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("CLIP/C0001.MP4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("CLIP/C0001M01.XML").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("outside.MP4").path))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: bin.path))?.count, 3, "moved, not deleted")
        XCTAssertEqual(t.listed(shoot: "s").map(\.bytes), [20_000, 10_300])
        XCTAssertEqual(t.listed(shoot: "other"), [])
        let back = t.putBack(shoot: "s")
        XCTAssertEqual(back.map(\.ok), [true, true]); XCTAssertEqual(back.map(\.bytes).reduce(0, +), 30_300)
        for f in ["CLIP/C0001.MP4", "CLIP/C0001M01.XML", "CLIP/C0002.MP4"] { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(f).path), f) }
        XCTAssertEqual(t.listed(shoot: "s"), [], "nothing left noted")
    }

    func testMovesThatOverlapAreAllNoted() throws {
        for i in 0..<24 { try Data(count: 100).write(to: root.appendingPathComponent("CLIP/D\(i).MP4")) }
        let t = trash(), root = root!
        DispatchQueue.concurrentPerform(iterations: 24) { i in _ = t.move(root: root, rels: ["CLIP/D\(i).MP4"], shoot: "s", refusal: nil) }
        XCTAssertEqual(t.all().count, 24, "no move's note is lost to another saved at the same time")
    }

    func testARefusalMovesNothing() {
        let out = trash().move(root: root, rels: ["CLIP/C0001.MP4"], shoot: "s", refusal: "This drive is read only. Skim can't move anything off it.")
        XCTAssertEqual(out, [SkimTrash.Answer(rel: "CLIP/C0001.MP4", ok: false, bytes: 0, why: "This drive is read only. Skim can't move anything off it.")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("CLIP/C0001.MP4").path))
    }

    func testACardLayoutIsRefusedEvenWhenTheDriveIsNot() throws {
        let card = root.appendingPathComponent("PRIVATE/M4ROOT/CLIP"); try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data(count: 10).write(to: card.appendingPathComponent("C0009.MP4"))
        let out = trash().move(root: root, rels: ["PRIVATE/M4ROOT/CLIP/C0009.MP4"], shoot: "s", refusal: nil)
        XCTAssertEqual(out.first?.ok, false); XCTAssertEqual(out.first?.why.hasPrefix("These clips are on a camera card."), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: card.appendingPathComponent("C0009.MP4").path))
    }

    func testPutBackNeverOverwritesAndSaysWhatIsGone() throws {
        let t = trash()
        _ = t.move(root: root, rels: ["CLIP/C0001.MP4", "CLIP/C0002.MP4"], shoot: "s", refusal: nil)
        try Data(count: 1).write(to: root.appendingPathComponent("CLIP/C0002.MP4"))            // a new file where it was
        for n in try FileManager.default.contentsOfDirectory(atPath: bin.path) where n.hasSuffix("C0001M01.XML") { try FileManager.default.removeItem(at: bin.appendingPathComponent(n)) }   // emptied
        let back = Dictionary(uniqueKeysWithValues: t.putBack(shoot: "s").map { ($0.rel, $0) })
        XCTAssertEqual(back["CLIP/C0002.MP4"]?.ok, false); XCTAssertEqual(back["CLIP/C0002.MP4"]?.why, "a file is already where it was")
        XCTAssertEqual(back["CLIP/C0001.MP4"]?.ok, false); XCTAssertEqual(back["CLIP/C0001.MP4"]?.why, "not in the Trash any more")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("CLIP/C0002.MP4")).count, 1, "never overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("CLIP/C0001.MP4").path), "the clip itself came back")
    }
}
