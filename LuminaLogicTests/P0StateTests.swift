import XCTest
@testable import Lumina

@MainActor
final class P0StateTests: XCTestCase {

    func testRecipeSerializationStability() throws {
        let recipe = EditRecipe(
            exposure: 0.4,
            temperature: 5200,
            crop: EditCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            straightenDegrees: 1.5,
            retouch: [RetouchSpot(id: UUID(), x: 0.5, y: 0.5, radius: 0.02, sourceDX: 0.1, sourceDY: 0)]
        )
        let d1 = try EditRecipe.encodeStable(recipe)
        let d2 = try EditRecipe.encodeStable(recipe)
        XCTAssertEqual(d1, d2)
        let decoded = try EditRecipe.decode(d1)
        XCTAssertEqual(decoded.exposure, 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(decoded.crop?.width), 0.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.retouch.count, 1)
        XCTAssertEqual(decoded.valueFingerprint, recipe.valueFingerprint)
    }

    func testLegacyDevelopRecipeJSONMigratesIntoEditRecipe() throws {
        let legacy = """
        {"exposure":0.25,"temperature":6000,"tint":2,"contrast":5,"highlights":-10,"shadows":15,"whites":0,"blacks":0,"texture":0,"clarity":0,"dehaze":0,"vibrance":8,"saturation":0,"sharpness":40,"luminanceNR":10,"retouch":[],"sourceNeighbors":["a.xmp"],"confidence":0.9}
        """.data(using: .utf8)!
        let migrated = try EditRecipe.decode(legacy)
        XCTAssertEqual(migrated.exposure, 0.25, accuracy: 1e-9)
        XCTAssertNil(migrated.crop)
        XCTAssertEqual(migrated.straightenDegrees, 0, accuracy: 1e-9)
    }

    func testCullNeverMutatesEditRecipe() {
        var asset = AssetRecord(
            id: UUID(),
            sourceKey: "k",
            source: SourceReference(
                originalPath: "/x",
                relativePath: "x",
                volumeID: nil,
                availability: .available
            ),
            filename: "x.ARW",
            cull: .keep,
            recipe: EditRecipe(exposure: 0.5, crop: EditCrop(x: 0, y: 0, width: 0.5, height: 0.5), straightenDegrees: 2)
        )
        let recipeBefore = asset.recipe
        asset.cull = .reject
        XCTAssertEqual(asset.recipe, recipeBefore)
        asset.recipe = EditRecipe(exposure: 1.0)
        XCTAssertEqual(asset.cull, .reject)
    }

    func testBatchEditCommandStripsGeometryByDefault() throws {
        let recipient = UUID()
        let before = EditRecipe(exposure: 0.1, crop: EditCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5), straightenDegrees: 3)
        let leader = EditRecipe(exposure: 0.8, crop: EditCrop(x: 0, y: 0, width: 0.4, height: 0.4), straightenDegrees: 5)
        let cmd = BatchEditCommand.make(
            leaderAssetID: recipient,
            leaderRecipe: leader,
            recipientIDs: [recipient],
            priorRecipes: [recipient: before],
            includeGeometry: false
        )
        let data = try JSONEncoder().encode(cmd)
        let round = try JSONDecoder().decode(BatchEditCommand.self, from: data)
        XCTAssertEqual(try XCTUnwrap(round.recipients[0].before?.exposure), 0.1, accuracy: 1e-9)
        XCTAssertEqual(round.recipients[0].after.exposure, 0.8, accuracy: 1e-9)
        XCTAssertNil(round.recipients[0].after.crop)
        XCTAssertFalse(round.includeGeometry)
    }

    func testMissingOriginalShootPersistence() throws {
        let id = UUID()
        let shoot = ShootRecord(
            name: "t7-shoot",
            assets: [
                AssetRecord(
                    id: id,
                    sourceKey: "k",
                    source: SourceReference(
                        originalPath: "/Volumes/T7/gone.ARW",
                        bookmarkData: Data([1, 2, 3]),
                        relativePath: "gone.ARW",
                        volumeID: "T7",
                        availability: .missing
                    ),
                    filename: "gone.ARW",
                    cull: .keep,
                    recipe: EditRecipe(exposure: 0.3)
                )
            ],
            finalSetOrder: FinalSetOrder(assetIDs: [id]),
            workspace: WorkspaceRestoreState(
                focusedAssetID: id,
                filter: .all,
                scale: .singlePhoto
            )
        )
        let data = try JSONEncoder().encode(shoot)
        let loaded = try JSONDecoder().decode(ShootRecord.self, from: data)
        XCTAssertEqual(loaded.assets.count, 1)
        XCTAssertEqual(loaded.assets[0].source.availability, .missing)
        XCTAssertEqual(loaded.assets[0].cull, .keep)
        XCTAssertEqual(try XCTUnwrap(loaded.assets[0].recipe?.exposure), 0.3, accuracy: 1e-9)
        XCTAssertEqual(loaded.workspace.scale, .singlePhoto)
    }

    func testAtomicSaveLeavesFinalAndGoodCopy() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-p0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let finalURL = tmp.appendingPathComponent("shoot.json")
        let goodURL = tmp.appendingPathComponent("shoot.json.good")
        let tempURL = tmp.appendingPathComponent("shoot.json.tmp")
        let shoot = ShootRecord(
            name: "atomic",
            workspace: WorkspaceRestoreState(scale: .contactSheet)
        )
        let data = try JSONEncoder().encode(shoot)
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        try data.write(to: goodURL, options: .atomic)

        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: goodURL.path))

        try Data("{}".utf8).write(to: finalURL)
        let recovered = try JSONDecoder().decode(ShootRecord.self, from: Data(contentsOf: goodURL))
        XCTAssertEqual(recovered.name, "atomic")
    }
}
