import XCTest
@testable import Lumina

final class ShootDecisionJournalTests: XCTestCase {

    private func makeShootFolder() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-cp2-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeShoot(folder: URL, assetID: UUID = UUID()) -> ShootRecord {
        let name = "\(assetID.uuidString).ARW"
        return ShootRecord(
            name: "serialized-\(UUID().uuidString)",
            rawFolder: SourceReference(
                originalPath: folder.path,
                relativePath: ".",
                volumeID: "VOL",
                availability: .available
            ),
            assets: [
                AssetRecord(
                    id: assetID,
                    sourceKey: "k-\(assetID)",
                    source: SourceReference(
                        originalPath: folder.appendingPathComponent(name).path,
                        relativePath: name,
                        volumeID: "VOL",
                        availability: .available
                    ),
                    filename: name
                )
            ]
        )
    }

    // MARK: - D35 — nothing the user did is ever lost (append-only committed history)

    func testD35_committedDecisionsAppendNeverRewriteHistory() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asset = UUID()

        let cull1 = CullMutationCommand(
            assetID: asset, before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: [asset]
        )
        let cull2 = CullMutationCommand(
            assetID: asset, before: .keep, after: .reject,
            finalOrderBefore: [asset], finalOrderAfter: []
        )
        try ShootDecisionJournal.append(
            ShootDecisionJournal.cullRecord(cull1, sequence: 1),
            besideShootFolder: folder
        )
        try ShootDecisionJournal.append(
            ShootDecisionJournal.cullRecord(cull2, sequence: 2),
            besideShootFolder: folder
        )

        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].cullAfter, .keep)
        XCTAssertEqual(records[1].cullAfter, .reject)
        XCTAssertEqual(records[0].sequence + 1, records[1].sequence)

        let edit = EditMutationCommand(
            assetID: asset,
            before: .neutral,
            after: EditRecipe(exposure: 0.4)
        )
        try ShootDecisionJournal.append(
            ShootDecisionJournal.editRecord(edit, sequence: 3),
            besideShootFolder: folder
        )
        let afterEdit = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(afterEdit.count, 3)
        XCTAssertEqual(afterEdit[0].cullAfter, .keep, "D35: prior entries unchanged")
    }

    func testD35_editCommitsAppendBesideShoot() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asset = UUID()
        let cmd = EditMutationCommand(
            assetID: asset,
            before: EditRecipe(exposure: 0.1),
            after: EditRecipe(exposure: 0.9, temperature: 5200)
        )
        let written = ShootDecisionJournal.editRecord(cmd, sequence: 1)
        try ShootDecisionJournal.append(written, besideShootFolder: folder)
        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .editCommit)
        XCTAssertEqual(records[0].editAfterFingerprint, written.editAfterFingerprint)
    }

    // MARK: - D13 — staging is NOT journaled (release never commits)

    func testD13_stagingSurfaceAbsentFromJournalAPI() {
        ShootDecisionJournal.assertStagingNeverJournaled()
        let stagingKinds = ["stage", "staging", "release", "propose"]
        for raw in ShootJournalRecordKind.allCases.map(\.rawValue) {
            XCTAssertFalse(stagingKinds.contains(where: { raw.contains($0) }),
                             "D13: journal kind must not encode staging — got \(raw)")
        }
    }

    // MARK: - D36 v5 prior — no catalog; per-shoot beside files

    func testD36_journalBesideShootNotCentralCatalog() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asset = UUID()
        let cmd = CullMutationCommand(
            assetID: asset, before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: [asset]
        )
        try ShootDecisionJournal.append(
            ShootDecisionJournal.cullRecord(cmd, sequence: 1),
            besideShootFolder: folder
        )

        let journalURL = ShootDecisionJournal.journalURL(besideShootFolder: folder)
        XCTAssertTrue(journalURL.path.hasPrefix(folder.path),
                      "D36: journal must live beside the shoot folder")
        XCTAssertFalse(journalURL.path.contains("Application Support"),
                       "D36: no central Application Support catalog path")
        XCTAssertTrue(journalURL.lastPathComponent.contains("decisions.journal"))
    }

    func testD36_journalDoesNotTouchPhotographFiles() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rawPhoto = folder.appendingPathComponent("DSC0001.ARW")
        try Data([0x01, 0x02, 0x03]).write(to: rawPhoto)
        let before = try Data(contentsOf: rawPhoto)

        let asset = UUID()
        let cmd = CullMutationCommand(
            assetID: asset, before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: [asset]
        )
        try ShootDecisionJournal.append(
            ShootDecisionJournal.cullRecord(cmd, sequence: 1),
            besideShootFolder: folder
        )

        let after = try Data(contentsOf: rawPhoto)
        XCTAssertEqual(before, after, "D36 / R-M.1: mark key X never writes — journal must not mutate RAW bytes")
        let journalOnly = try FileManager.default.contentsOfDirectory(
            at: folder.appendingPathComponent(".lumina", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(journalOnly.map(\.lastPathComponent), ["decisions.journal.jsonl"])
    }

    // MARK: - D35 — atomic append survives kill mid-write (simulated corrupt tail)

    func testD35_killMidWritePreservesCommittedPrefix() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asset = UUID()

        for i in 0..<5 {
            let cmd = CullMutationCommand(
                assetID: asset,
                before: i == 0 ? .undecided : .keep,
                after: .keep,
                finalOrderBefore: [], finalOrderAfter: [asset]
            )
            try ShootDecisionJournal.append(
                ShootDecisionJournal.cullRecord(cmd, sequence: UInt64(i + 1)),
                besideShootFolder: folder
            )
        }

        let url = ShootDecisionJournal.journalURL(besideShootFolder: folder)
        var data = try Data(contentsOf: url)
        data.append(contentsOf: "{\"seq\":99,\"partial".utf8)
        try data.write(to: url, options: .atomic)

        let recovered = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(recovered.count, 5, "D35: complete lines survive kill mid-write on trailing line")
        XCTAssertEqual(recovered.map(\.sequence), [1, 2, 3, 4, 5])
    }

    func testSerializedStoreAssignsOrderedSequenceWithoutQuadraticRereads() async throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        var shoot = makeShoot(folder: folder, assetID: assetID)
        let store = ShootStore()

        for index in 0..<1_000 {
            let before = shoot.assets[0].cull
            let after: CullDecision = index.isMultiple(of: 2) ? .keep : .reject
            shoot.assets[0].cull = after
            let command = CullMutationCommand(
                assetID: assetID,
                before: before,
                after: after,
                finalOrderBefore: before == .keep ? [assetID] : [],
                finalOrderAfter: after == .keep ? [assetID] : []
            )
            let error = await store.commitCulls(
                [command],
                shoot: shoot,
                besideShootFolder: folder,
                commandStartedAt: Date()
            )
            XCTAssertNil(error)
        }

        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.map(\.sequence), Array(1...1_000).map { UInt64($0) })
        #if DEBUG
        let initializationCount = await store.journalInitializationCount(besideShootFolder: folder)
        XCTAssertEqual(initializationCount, 1, "the journal is scanned once, not once per append")
        #endif
    }

    func testSerializedStoreResumesSequenceAfterRestart() async throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        var shoot = makeShoot(folder: folder, assetID: assetID)

        let first = CullMutationCommand(
            assetID: assetID,
            before: .undecided,
            after: .keep,
            finalOrderBefore: [],
            finalOrderAfter: [assetID]
        )
        shoot.assets[0].cull = .keep
        let firstError = await ShootStore().commitCulls(
            [first],
            shoot: shoot,
            besideShootFolder: folder,
            commandStartedAt: Date()
        )
        XCTAssertNil(firstError)

        let journalURL = ShootDecisionJournal.journalURL(besideShootFolder: folder)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"partial\":".utf8))
        try handle.close()

        let second = CullMutationCommand(
            assetID: assetID,
            before: .keep,
            after: .reject,
            finalOrderBefore: [assetID],
            finalOrderAfter: []
        )
        shoot.assets[0].cull = .reject
        let secondError = await ShootStore().commitCulls(
            [second],
            shoot: shoot,
            besideShootFolder: folder,
            commandStartedAt: Date()
        )
        XCTAssertNil(secondError)

        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.map(\.sequence), [1, 2])
    }
}

private extension ShootJournalRecordKind {
    static var allCases: [ShootJournalRecordKind] {
        [.cullCommit, .editCommit]
    }
}
