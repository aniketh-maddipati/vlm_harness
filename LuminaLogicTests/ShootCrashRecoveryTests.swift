import XCTest
@testable import Lumina

final class ShootCrashRecoveryTests: XCTestCase {

    private func makeFolder() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeAsset(id: UUID, folder: URL, cull: CullDecision = .undecided) -> AssetRecord {
        let name = "\(id.uuidString).ARW"
        return AssetRecord(
            id: id,
            sourceKey: "k-\(id)",
            source: SourceReference(
                originalPath: folder.appendingPathComponent(name).path,
                relativePath: name,
                volumeID: "VOL",
                availability: .available
            ),
            filename: name,
            cull: cull
        )
    }

    // MARK: - D35 crash-only startup

    func testD35_crashOnlyStartupRestoresCommittedStateExactly() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = UUID(), b = UUID()
        try Data([0x01]).write(to: folder.appendingPathComponent("\(a.uuidString).ARW"))
        try Data([0x02]).write(to: folder.appendingPathComponent("\(b.uuidString).ARW"))

        var shoot = ShootRecord(
            name: "crash-test",
            rawFolder: SourceReference(
                originalPath: folder.path,
                relativePath: ".",
                volumeID: "VOL",
                availability: .available
            ),
            assets: [makeAsset(id: a, folder: folder), makeAsset(id: b, folder: folder)]
        )

        let cull = CullMutationCommand(
            assetID: a, before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: [a]
        )
        _ = try ShootDecisionJournal.appendCullCommit(cull, besideShootFolder: folder)

        let edit = EditMutationCommand(
            assetID: b,
            before: .neutral,
            after: EditRecipe(exposure: 0.55, contrast: 12)
        )
        _ = try ShootDecisionJournal.appendEditCommit(edit, besideShootFolder: folder)

        // Simulate stale catalog (crash before shoot.json caught up).
        shoot.assets[0].cull = .undecided
        shoot.assets[1].recipe = nil
        shoot.finalSetOrder = FinalSetOrder()

        let report = try ShootCrashRecovery.replayJournal(into: &shoot, besideShootFolder: folder)
        XCTAssertEqual(report.appliedRecords, 2)
        XCTAssertEqual(shoot.assets.first(where: { $0.id == a })?.cull, .keep)
        XCTAssertEqual(shoot.finalSetOrder.assetIDs, [a])
        XCTAssertEqual(
            try XCTUnwrap(shoot.assets.first(where: { $0.id == b })?.recipe?.exposure),
            0.55,
            accuracy: 1e-9
        )
    }

    func testD13_stagedScopeGoneAfterCrashRecovery() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let rel = "\(assetID.uuidString).ARW"
        try Data([0x01]).write(to: folder.appendingPathComponent(rel))

        var shoot = ShootRecord(
            name: folder.lastPathComponent,
            rawFolder: SourceReference(
                originalPath: folder.path,
                relativePath: ".",
                volumeID: "VOL",
                availability: .available
            ),
            assets: [
                AssetRecord(
                    id: assetID,
                    sourceKey: "k",
                    source: SourceReference(
                        originalPath: folder.appendingPathComponent(rel).path,
                        relativePath: rel,
                        volumeID: "VOL",
                        availability: .available
                    ),
                    filename: rel
                ),
            ]
        )

        _ = try ShootCrashRecovery.replayJournal(into: &shoot, besideShootFolder: folder)

        let relaunch = P0SessionModel()
        relaunch.shoot = shoot
        relaunch.assets = shoot.assets
        XCTAssertFalse(relaunch.isEditGestureActive, "D13: staging scope absent after crash-only relaunch")
        XCTAssertNil(relaunch.workingRecipe)
    }

    func testD36_xNeverTouchesFS_onCullJournalAppend() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let name = "\(assetID.uuidString).ARW"
        let raw = folder.appendingPathComponent(name)
        try Data([0xAA, 0xBB, 0xCC]).write(to: raw)

        let before = try ShootCrashRecovery.photographByteHashes(in: folder)
        let cmd = CullMutationCommand(
            assetID: assetID, before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: [assetID]
        )
        _ = try ShootDecisionJournal.appendCullCommit(cmd, besideShootFolder: folder)
        let after = try ShootCrashRecovery.photographByteHashes(in: folder)

        XCTAssertEqual(before, after, "D36 / R-M.1: X and journal must not mutate photograph bytes")
        let journal = ShootDecisionJournal.journalURL(besideShootFolder: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }
}
