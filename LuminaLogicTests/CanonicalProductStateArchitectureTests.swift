import XCTest
@testable import Lumina

final class CanonicalProductStateArchitectureTests: XCTestCase {
    func testCurrentCullStatePersistsThroughShootRecord() throws {
        try withIsolatedStore { shoot in
            var changed = shoot
            changed.assets[0].cull = .keep

            try ShootStore.saveShoot(changed)
            let reopened = try ShootStore.loadShoot(id: changed.name)

            XCTAssertEqual(reopened.assets[0].cull, .keep)
        }
    }

    func testCurrentEditStatePersistsThroughAssetRecord() throws {
        try withIsolatedStore { shoot in
            var changed = shoot
            changed.assets[0].recipe = EditRecipe(
                exposure: 0.75,
                crop: EditCrop(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                straightenDegrees: 1.25
            )

            try ShootStore.saveShoot(changed)
            let reopened = try ShootStore.loadShoot(id: changed.name)
            let recipe = try XCTUnwrap(reopened.assets[0].recipe)

            XCTAssertEqual(recipe.exposure, 0.75, accuracy: 0.000_001)
            XCTAssertEqual(recipe.straightenDegrees, 1.25, accuracy: 0.000_001)
            XCTAssertEqual(try XCTUnwrap(recipe.crop?.width), 0.7, accuracy: 0.000_001)
        }
    }

    func testOpeningCurrentShootDecodesShootRecordDirectly() throws {
        try withIsolatedStore { shoot in
            let url = try ShootStore.shootJSONURL(for: shoot.name)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(shoot).write(to: url, options: .atomic)

            let reopened = try ShootStore.loadShoot(id: shoot.name)

            XCTAssertEqual(reopened.id, shoot.id)
            XCTAssertEqual(reopened.assets.map(\.id), shoot.assets.map(\.id))
        }
    }

    func testSavingCurrentShootWritesOnlyCanonicalCatalog() throws {
        try withIsolatedStore { shoot in
            try ShootStore.saveShoot(shoot)

            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: try ShootStore.shootJSONURL(for: shoot.name).path
                )
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: try ShootStore.legacyProjectJSONURL(for: shoot.name).path
                )
            )
        }
    }

    func testCurrentProductSourcesDoNotReferenceLegacyProductState() throws {
        let root = repoRoot()
        var paths = [
            "Lumina/LuminaApp.swift",
            "Lumina/ViewModels/P0SessionModel.swift",
            "Lumina/Services/ContactSheetPreparation.swift",
            "Lumina/Services/ShootStore.swift",
            "Lumina/Services/P0AuthoritativeExportService.swift",
        ]
        let p0Views = root.appendingPathComponent("Lumina/Views/P0", isDirectory: true)
        paths += try FileManager.default.contentsOfDirectory(
            at: p0Views,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .map { "Lumina/Views/P0/\($0.lastPathComponent)" }

        let forbidden = ["LuminaProject", "PhotoRecord", "ProjectStore"]
        for path in paths {
            let source = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            for symbol in forbidden {
                XCTAssertFalse(source.contains(symbol), "\(path) references \(symbol)")
            }
        }
    }

    private func withIsolatedStore(_ body: (ShootRecord) throws -> Void) throws {
        let priorRoot = UITestSupport.stateDirectoryOverride
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-canonical-state-\(UUID().uuidString)", isDirectory: true)
        UITestSupport.stateDirectoryOverride = root
        defer {
            UITestSupport.stateDirectoryOverride = priorRoot
            try? FileManager.default.removeItem(at: root)
        }

        let id = UUID()
        let shoot = ShootRecord(
            id: UUID(),
            name: "canonical-\(UUID().uuidString)",
            assets: [
                AssetRecord(
                    id: id,
                    sourceKey: "volume/frame.raw/1",
                    source: SourceReference(
                        originalPath: "/Volumes/Shoot/frame.raw",
                        relativePath: "frame.raw",
                        volumeID: "volume",
                        availability: .available
                    ),
                    filename: "frame.raw"
                )
            ],
            workspace: WorkspaceRestoreState(focusedAssetID: id)
        )
        try body(shoot)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
