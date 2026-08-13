import XCTest
@testable import Lumina

@MainActor
final class P0JournalIntegrationTests: XCTestCase {

    private func makeShootFolder() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-p0-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeAsset(id: UUID, folder: URL) -> AssetRecord {
        let relative = "\(id.uuidString).ARW"
        return AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: folder.appendingPathComponent(relative).path,
                relativePath: relative,
                volumeID: "VOL",
                availability: .available
            ),
            filename: relative,
            cull: .undecided
        )
    }

    private func attachShoot(to session: P0SessionModel, folder: URL, assets: [AssetRecord]) {
        session.shoot = ShootRecord(
            name: folder.lastPathComponent,
            rawFolder: SourceReference(
                originalPath: folder.path,
                relativePath: ".",
                volumeID: "VOL",
                availability: .available
            ),
            assets: assets
        )
        session.assets = assets
    }

    // MARK: - D35 — session commits append beside shoot

    func testD35_sessionCullCommitAppendsJournal() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let session = P0SessionModel()
        attachShoot(to: session, folder: folder, assets: [makeAsset(id: assetID, folder: folder)])
        session.focusedAssetID = assetID

        session.pressKeep()

        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .cullCommit)
        XCTAssertEqual(records[0].cullAfter, .keep)
    }

    // MARK: - D13 — staging is NOT journaled until commit

    func testD13_editGestureStagingNotJournaledUntilCommit() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let session = P0SessionModel()
        attachShoot(to: session, folder: folder, assets: [makeAsset(id: assetID, folder: folder)])
        session.focusedAssetID = assetID
        session.inspectingAssetID = assetID

        session.beginEditGesture(for: assetID)
        session.scrubEdit { $0.exposure = 0.6 }

        let journalURL = ShootDecisionJournal.journalURL(besideShootFolder: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path),
                       "D13: staging must not reach journal before commit")

        session.endEditGesture()

        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .editCommit)
    }
}
