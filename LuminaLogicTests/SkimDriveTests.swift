import XCTest
@testable import Lumina

/// The drive a Skim shoot is on (`SkimDrive`, STORAGE.md step 3): a card or a read-only volume is refused in plain
/// words, purgeable space is what Finder adds to plain free space, the Trash is the one macOS keeps for this user on
/// that volume, and its size is summed from the files, or nil when it can't be listed. Foundation only.
final class SkimDriveTests: XCTestCase {
    func testACardOrAReadOnlyDriveIsRefusedInPlainWords() {
        XCTAssertNil(SkimDrive.refusal(path: "/Users/me/Desktop/trip", readOnly: false, card: false))
        XCTAssertEqual(SkimDrive.refusal(path: "/Volumes/Untitled/PRIVATE/M4ROOT/CLIP", readOnly: false, card: false),
                       "These clips are on a camera card. Skim never moves or deletes anything on a card; copy them to a drive first.")
        XCTAssertEqual(SkimDrive.refusal(path: "/Volumes/T7/private/m4root/clip", readOnly: false, card: false)?.hasPrefix("These clips are on a camera card."), true)
        XCTAssertEqual(SkimDrive.refusal(path: "/Volumes/SD", readOnly: false, card: true)?.hasPrefix("These clips are on a camera card."), true)
        XCTAssertEqual(SkimDrive.refusal(path: "/Volumes/SD", readOnly: true, card: true)?.hasPrefix("These clips are on a camera card."), true, "a card says card first")
        XCTAssertEqual(SkimDrive.refusal(path: "/Volumes/Archive", readOnly: true, card: false), "This drive is read only. Skim can't move anything off it.")
    }

    func testPurgeableIsWhatFinderAddsToPlainFreeSpace() {
        XCTAssertEqual(SkimDrive.purgeable(free: 52_000_000_000, important: 60_000_000_000), 8_000_000_000)
        XCTAssertEqual(SkimDrive.purgeable(free: 52_000_000_000, important: 50_000_000_000), 0, "never negative")
        XCTAssertNil(SkimDrive.purgeable(free: nil, important: 1))
        XCTAssertNil(SkimDrive.purgeable(free: 1, important: 0), "unknown is not zero")
    }

    func testTheTrashIsTheOneMacOSKeepsForThisUserOnThatVolume() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        XCTAssertEqual(SkimDrive.trashFolder(volume: URL(fileURLWithPath: "/"), home: home, uid: 501).path, "/Users/me/.Trash")
        XCTAssertEqual(SkimDrive.trashFolder(volume: URL(fileURLWithPath: "/Volumes/T7"), home: home, uid: 501).path, "/Volumes/T7/.Trashes/501")
    }

    func testTheTrashsSizeIsSummedFromItsFilesOrUnknown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skim-trash-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(SkimDrive.bytes(under: dir), "a Trash that can't be listed is unknown, not empty")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("C0001 folder"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: dir.appendingPathComponent("C0001.MP4"))
        try Data(count: 5_000).write(to: dir.appendingPathComponent("C0001 folder/C0001M01.XML"))
        let b = try XCTUnwrap(SkimDrive.bytes(under: dir))
        XCTAssertGreaterThanOrEqual(b, 15_000); XCTAssertLessThan(b, 15_000 + 3 * 65_536, "allocated size, two files")
        XCTAssertEqual(SkimDrive.bytes(under: dir.appendingPathComponent("missing")), nil)
    }

    func testAReadingOfAFolderNamesItsDriveAndNeverGuesses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skim-drive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let r = SkimDrive.read(folder: dir, home: dir, uid: 501)
        XCTAssertFalse(r.readOnly)
        if let free = r.free, let total = r.total { XCTAssertLessThanOrEqual(free, total) }
        if r.trash == nil { XCTAssertNil(r.json["trash"], "trash only when it was read") }
        XCTAssertEqual(r.json["refusal"] == nil, r.refusal == nil)
    }
}
