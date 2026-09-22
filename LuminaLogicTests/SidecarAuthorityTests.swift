import XCTest
@testable import Lumina

@MainActor
final class SidecarAuthorityTests: XCTestCase {

    func testCase1_cleanShutdownXMPAndShootCacheAgree() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            let after = EditRecipe(exposure: 0.35, contrast: 8)
            var live = shoot
            live.assets[0].recipe = after
            let result = await ShootStore.shared.commitEdit(
                EditMutationCommand(assetID: assetID, before: .neutral, after: after),
                shoot: live,
                besideShootFolder: folder,
                originalURL: raw,
                commandStartedAt: Date()
            )
            XCTAssertNil(result.error)

            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            let beforeBytes = try Data(contentsOf: xmp)
            let catalog = try ShootStore.loadShoot(id: live.name)
            let recovered = try await ShootStore.shared.recoverShoot(catalog, besideShootFolder: folder)

            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.35, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp)?.exposure), 0.35, accuracy: 1e-6)
            XCTAssertEqual(try Data(contentsOf: xmp), beforeBytes, "clean shutdown must not rewrite XMP on recover")
            let outcome = ShootSidecarStore.reconcileOnOpen(
                existingRecipe: recovered.assets[0].recipe,
                lastJournalEditAt: try lastJournalEdit(at: folder)?.recordedAt,
                xmpURL: xmp
            )
            XCTAssertEqual(outcome.winner, .agreed)
        }
    }

    func testCase2_journalNewerThanSidecarWinsCrashWindow() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.10), besideOriginal: raw)
            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -180)],
                ofItemAtPath: xmp.path
            )
            let aged = try FileManager.default.attributesOfItem(atPath: xmp.path)[.modificationDate] as? Date
            XCTAssertLessThan(try XCTUnwrap(aged), Date().addingTimeInterval(-60))
            let journalRecipe = EditRecipe(exposure: 0.55, contrast: 12)
            try ShootDecisionJournal.append(
                ShootDecisionJournal.editRecord(
                    EditMutationCommand(assetID: assetID, before: .neutral, after: journalRecipe),
                    sequence: 1
                ),
                besideShootFolder: folder
            )

            var stale = shoot
            stale.assets[0].recipe = EditRecipe(exposure: 0.10)
            let xmpBefore = try Data(contentsOf: xmp)
            let recovered = try await ShootStore.shared.recoverShoot(stale, besideShootFolder: folder)

            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.55, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp)?.exposure), 0.10, accuracy: 1e-6)
            XCTAssertEqual(try Data(contentsOf: xmp), xmpBefore)
        }
    }

    func testCase3_sidecarNewerThanShootCacheWins() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            var past = ShootDecisionJournal.editRecord(
                EditMutationCommand(assetID: assetID, before: .neutral, after: EditRecipe(exposure: 0.10)),
                sequence: 1
            )
            past.recordedAt = Date(timeIntervalSinceNow: -180)
            try ShootDecisionJournal.append(past, besideShootFolder: folder)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.80), besideOriginal: raw)
            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            let xmpBefore = try Data(contentsOf: xmp)

            var stale = shoot
            stale.assets[0].recipe = EditRecipe(exposure: 0.10)
            try await ShootStore.shared.saveShoot(stale)
            let recovered = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: stale.name),
                besideShootFolder: folder
            )

            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.80, accuracy: 1e-6)
            XCTAssertEqual(try Data(contentsOf: xmp), xmpBefore, "stale cache must not overwrite newer sidecar")
        }
    }

    func testCase4_externalXMPChangeDetectedNotOverwritten() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            let written = EditRecipe(exposure: 0.35)
            var live = shoot
            live.assets[0].recipe = written
            let commit = await ShootStore.shared.commitEdit(
                EditMutationCommand(assetID: assetID, before: .neutral, after: written),
                shoot: live,
                besideShootFolder: folder,
                originalURL: raw,
                commandStartedAt: Date()
            )
            XCTAssertNil(commit.error)

            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            try mutateExposure(in: xmp, from: "Exposure2012=\"+0.35\"", to: "Exposure2012=\"+8.88\"")
            let externalBytes = try Data(contentsOf: xmp)

            let recovered = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: live.name),
                besideShootFolder: folder
            )
            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 8.88, accuracy: 1e-6)
            XCTAssertEqual(try Data(contentsOf: xmp), externalBytes, "external XMP must not be silently overwritten")

            let session = P0SessionModel()
            session.shoot = recovered
            session.assets = recovered.assets
            session.adoptSidecarManagedHashes(from: recovered.assets)
            try mutateExposure(in: xmp, from: "Exposure2012=\"+8.88\"", to: "Exposure2012=\"+1.11\"")
            let outcome = session.reconcileSidecarDrift(for: assetID)
            guard case .externalDrift = outcome else {
                return XCTFail("expected in-session drift after relaunch hash adopt")
            }
            XCTAssertEqual(session.recipe(for: assetID).exposure, 8.88, accuracy: 1e-6)
            XCTAssertTrue(try String(contentsOf: xmp, encoding: .utf8).contains("1.11"))
        }
    }

    func testCase5_shootCacheWithoutSidecarKeepsRecipe() async throws {
        try await withIsolatedSupport { _, folder, _, shoot in
            var cached = shoot
            cached.assets[0].recipe = EditRecipe(exposure: 0.40, contrast: 6)
            try await ShootStore.shared.saveShoot(cached)
            let raw = URL(fileURLWithPath: cached.assets[0].source.originalPath)
            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))

            let recovered = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: cached.name),
                besideShootFolder: folder
            )
            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.40, accuracy: 1e-6)
            XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path), "recover must not create a sidecar")
        }
    }

    func testCase6_deletedApplicationSupportReconstructsFromXMP() async throws {
        try await withIsolatedSupport { support, folder, _, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.75, shadows: 12), besideOriginal: raw)
            try FileManager.default.removeItem(at: support)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

            let opened = try await firstOpened(
                from: ContactSheetPreparation.openFolder(folder, shootName: folder.lastPathComponent, visibleWindowHint: 0)
            )
            XCTAssertEqual(try XCTUnwrap(opened.assets.first?.recipe?.exposure), 0.75, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(opened.assets.first?.recipe?.shadows), 12, accuracy: 1e-6)
        }
    }

    func testCase7_sourceDriveReturnReconcilesSidecar() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            try FileManager.default.removeItem(at: raw)
            var offline = shoot
            offline.assets[0].recipe = EditRecipe(exposure: 0.10)
            offline.assets[0].source.availability = .missing
            try await ShootStore.shared.saveShoot(offline)

            let whileMissing = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: offline.name),
                besideShootFolder: folder
            )
            XCTAssertEqual(try XCTUnwrap(whileMissing.assets[0].recipe?.exposure), 0.10, accuracy: 1e-6)

            try Data([0x01]).write(to: raw)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.90), besideOriginal: raw)
            var returned = try ShootStore.loadShoot(id: offline.name)
            returned.assets[0].source.originalPath = raw.path
            returned.assets[0].source.availability = .available
            let recovered = try await ShootStore.shared.recoverShoot(returned, besideShootFolder: folder)
            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.90, accuracy: 1e-6)
            XCTAssertEqual(assetID, recovered.assets[0].id)
        }
    }

    func testEditThenXMPThenRestart() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            let session = P0SessionModel()
            session.shoot = shoot
            session.assets = shoot.assets
            session.focusedAssetID = assetID
            session.inspectingAssetID = assetID
            session.applyEditMutation({ $0.exposure = 0.42 }, assetID: assetID)

            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            try await waitForFile(xmp)
            XCTAssertEqual(try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp)?.exposure), 0.42, accuracy: 1e-6)

            let recovered = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: shoot.name),
                besideShootFolder: folder
            )
            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.42, accuracy: 1e-6)
        }
    }

    func testEditCrashWindowJournalReplayThenRestart() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.20), besideOriginal: raw)
            let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -120)],
                ofItemAtPath: xmp.path
            )
            let aged = try FileManager.default.attributesOfItem(atPath: xmp.path)[.modificationDate] as? Date
            XCTAssertLessThan(try XCTUnwrap(aged), Date().addingTimeInterval(-30))
            var live = shoot
            live.assets[0].recipe = EditRecipe(exposure: 0.66)
            let result = await ShootStore.shared.commitEdit(
                EditMutationCommand(assetID: assetID, before: EditRecipe(exposure: 0.20), after: EditRecipe(exposure: 0.66)),
                shoot: live,
                besideShootFolder: folder,
                originalURL: nil,
                commandStartedAt: Date()
            )
            XCTAssertNil(result.error)
            var rewind = try ShootStore.loadShoot(id: live.name)
            rewind.assets[0].recipe = EditRecipe(exposure: 0.20)
            try await ShootStore.shared.saveShoot(rewind)

            let recovered = try await ShootStore.shared.recoverShoot(
                try ShootStore.loadShoot(id: live.name),
                besideShootFolder: folder
            )
            XCTAssertEqual(try XCTUnwrap(recovered.assets[0].recipe?.exposure), 0.66, accuracy: 1e-6)
            XCTAssertEqual(
                try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: ShootSidecarStore.sidecarURL(besideOriginal: raw))?.exposure),
                0.20,
                accuracy: 1e-6
            )
        }
    }

    func testStaleShootCacheCannotOverrideNewerSidecarOnFolderReopen() async throws {
        try await withIsolatedSupport { _, folder, assetID, shoot in
            let raw = URL(fileURLWithPath: shoot.assets[0].source.originalPath)
            var stale = shoot
            stale.assets[0].recipe = EditRecipe(exposure: 0.11)
            try await ShootStore.shared.saveShoot(stale)
            _ = try ShootSidecarStore.writeCommittedEdit(EditRecipe(exposure: 0.99), besideOriginal: raw)
            let xmpBefore = try Data(contentsOf: ShootSidecarStore.sidecarURL(besideOriginal: raw))

            let opened = try await firstOpened(
                from: ContactSheetPreparation.openFolder(folder, shootName: stale.name, visibleWindowHint: 0)
            )
            let asset = try XCTUnwrap(opened.assets.first(where: { $0.id == assetID }) ?? opened.assets.first)
            XCTAssertEqual(try XCTUnwrap(asset.recipe?.exposure), 0.99, accuracy: 1e-6)
            XCTAssertEqual(try Data(contentsOf: ShootSidecarStore.sidecarURL(besideOriginal: raw)), xmpBefore)
        }
    }

    func testPersistenceRemainsSerializedThroughShootStore() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let contact = try String(
            contentsOf: root.appendingPathComponent("Lumina/Services/ContactSheetPreparation.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: root.appendingPathComponent("Lumina/Services/ShootStore.swift"),
            encoding: .utf8
        )
        let session = try String(
            contentsOf: root.appendingPathComponent("Lumina/ViewModels/P0SessionModel.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(contact.contains("readMappedRecipe"), "discovery sidecar seed is pruned; recoverShoot is the restore owner")
        XCTAssertFalse(contact.contains("writeCommittedEdit"))
        XCTAssertTrue(contact.contains("recoverAndCatchUpCatalog"))
        XCTAssertTrue(store.contains("applyOpenReconciliation"))
        XCTAssertTrue(store.contains("ShootSidecarStore.writeCommittedEdit"))
        XCTAssertTrue(session.contains("ShootStore.shared.commitEdit"))
        XCTAssertFalse(session.contains("ShootSidecarStore.writeCommittedEdit"))
    }

    // MARK: - Fixtures

    private func withIsolatedSupport(
        _ body: (URL, URL, UUID, ShootRecord) async throws -> Void
    ) async throws {
        let prior = UITestSupport.stateDirectoryOverride
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-authority-support-\(UUID().uuidString)", isDirectory: true)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-authority-shoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        UITestSupport.stateDirectoryOverride = support
        defer {
            UITestSupport.stateDirectoryOverride = prior
            try? FileManager.default.removeItem(at: support)
            try? FileManager.default.removeItem(at: folder)
        }

        let assetID = UUID()
        let relative = "\(assetID.uuidString).ARW"
        let raw = folder.appendingPathComponent(relative)
        try Data([0x01]).write(to: raw)
        let shoot = ShootRecord(
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
                    sourceKey: "k-\(assetID.uuidString)",
                    source: SourceReference(
                        originalPath: raw.path,
                        relativePath: relative,
                        volumeID: "VOL",
                        availability: .available
                    ),
                    filename: relative
                ),
            ]
        )
        try await body(support, folder, assetID, shoot)
    }

    private func firstOpened(from stream: AsyncStream<ContactSheetEvent>) async throws -> ShootRecord {
        for await event in stream {
            switch event {
            case .opened(let shoot, _):
                return shoot
            case .failed(let message):
                XCTFail(message)
            default:
                continue
            }
        }
        struct OpenedMissing: Error {}
        throw OpenedMissing()
    }

    private func lastJournalEdit(at folder: URL) throws -> ShootJournalRecord? {
        try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
            .last(where: { $0.kind == .editCommit })
    }

    private func mutateExposure(in xmp: URL, from: String, to: String) throws {
        var text = try String(contentsOf: xmp, encoding: .utf8)
        text = text.replacingOccurrences(of: from, with: to)
        try text.write(to: xmp, atomically: true, encoding: .utf8)
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("file did not become durable: \(url.path)")
    }
}
