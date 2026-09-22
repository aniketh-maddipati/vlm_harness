import XCTest
@testable import Lumina

@MainActor
final class P0SidecarIntegrationTests: XCTestCase {

    private func makeShootFolder() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-p0-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func testD36_sessionEditCommitWritesSidecarBesideOriginal() async throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let relative = "\(assetID.uuidString).ARW"
        let rawURL = folder.appendingPathComponent(relative)
        try Data([0x01]).write(to: rawURL)

        let session = P0SessionModel()
        session.shoot = ShootRecord(
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
                        originalPath: rawURL.path,
                        relativePath: relative,
                        volumeID: "VOL",
                        availability: .available
                    ),
                    filename: relative
                ),
            ]
        )
        session.assets = session.shoot!.assets
        session.focusedAssetID = assetID
        session.inspectingAssetID = assetID

        session.applyEditMutation({ $0.exposure = 0.35 }, assetID: assetID)

        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: rawURL)
        try await waitForFile(xmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmp.path))
        let parsed = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp))
        XCTAssertEqual(parsed.exposure, 0.35, accuracy: 1e-6)
        XCTAssertTrue(ShootSidecarStore.assertNoLuminaPrivateStore(besideOriginal: rawURL))
    }

    func testD35_sidecarDriftDetectedWithoutMutatingSessionRecipe() async throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let relative = "\(assetID.uuidString).ARW"
        let rawURL = folder.appendingPathComponent(relative)
        try Data([0x01]).write(to: rawURL)

        let session = P0SessionModel()
        session.shoot = ShootRecord(
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
                        originalPath: rawURL.path,
                        relativePath: relative,
                        volumeID: "VOL",
                        availability: .available
                    ),
                    filename: relative
                ),
            ]
        )
        session.assets = session.shoot!.assets
        session.focusedAssetID = assetID
        session.inspectingAssetID = assetID

        session.applyEditMutation({ $0.exposure = 0.35 }, assetID: assetID)
        let sessionExposure = session.recipe(for: assetID).exposure

        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: rawURL)
        try await waitForFile(xmp)
        var text = try String(contentsOf: xmp, encoding: .utf8)
        text = text.replacingOccurrences(of: "Exposure2012=\"+0.35\"", with: "Exposure2012=\"+8.88\"")
        try text.write(to: xmp, atomically: true, encoding: .utf8)

        let outcome = session.reconcileSidecarDrift(for: assetID)
        guard case .externalDrift = outcome else {
            return XCTFail("expected external drift")
        }
        XCTAssertTrue(session.sidecarDriftAssetIDs.contains(assetID))
        XCTAssertEqual(session.recipe(for: assetID).exposure, sessionExposure, accuracy: 1e-9,
                       "D35: session recipe stays authoritative when sidecar drifts underneath")
    }

    func testEditMutatesMemoryWithoutWaitingForSidecarAndReportsFailure() async throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assetID = UUID()
        let blockedParent = folder.appendingPathComponent("not-a-directory")
        try Data([0x01]).write(to: blockedParent)
        let rawURL = blockedParent.appendingPathComponent("\(assetID.uuidString).ARW")

        let asset = AssetRecord(
            id: assetID,
            sourceKey: "k",
            source: SourceReference(
                originalPath: rawURL.path,
                relativePath: rawURL.lastPathComponent,
                volumeID: "VOL",
                availability: .available
            ),
            filename: rawURL.lastPathComponent
        )
        let session = P0SessionModel()
        session.shoot = ShootRecord(
            name: folder.lastPathComponent,
            rawFolder: SourceReference(
                originalPath: folder.path,
                relativePath: ".",
                volumeID: "VOL",
                availability: .available
            ),
            assets: [asset]
        )
        session.assets = [asset]
        session.focusedAssetID = assetID
        session.inspectingAssetID = assetID

        session.applyEditMutation({ $0.exposure = 0.7 }, assetID: assetID)

        XCTAssertEqual(session.recipe(for: assetID).exposure, 0.7, accuracy: 1e-9)
        XCTAssertNil(session.persistenceError, "the command returns before sidecar durability")
        for _ in 0..<100 where session.persistenceError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(session.persistenceError)
        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: folder)
        XCTAssertEqual(records.count, 1, "sidecar failure must not discard crash recovery")
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("file did not become durable: \(url.path)")
    }

    // MARK: - Checkpoint 01: camera profile / crop aspect / orientation / source round trip

    func testCameraProfileCropAspectAndSourceRoundTripThroughSidecar() throws {
        let folder = try makeShootFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rawURL = folder.appendingPathComponent("DSC0001.ARW")
        try Data([0x01]).write(to: rawURL)

        let written = EditRecipe(
            exposure: 0.2,
            crop: EditCrop(x: 0.1, y: 0.1, width: 0.5, height: 0.625),
            straightenDegrees: 91.5,
            cameraProfile: "Adobe Color",
            cropAspect: .fourByFive
        )
        _ = try ShootSidecarStore.writeCommittedEdit(written, source: .hand, besideOriginal: rawURL)

        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: rawURL)
        let readBack = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp))
        XCTAssertEqual(readBack.cameraProfile, "Adobe Color")
        XCTAssertEqual(readBack.cropAspect, .fourByFive)
        XCTAssertEqual(readBack.straightenDegrees, 91.5, accuracy: 1e-3)
        let readBackCrop = try XCTUnwrap(readBack.crop)
        XCTAssertEqual(readBackCrop.x, 0.1, accuracy: 1e-5)
        XCTAssertEqual(readBackCrop.width, 0.5, accuracy: 1e-5)

        let source = try ShootSidecarStore.readRecipeSource(at: xmp)
        XCTAssertEqual(source, .hand)

        let xml = try String(contentsOf: xmp, encoding: .utf8)
        XCTAssertTrue(xml.contains("crs:Orientation=\"90\""), "91.5° decomposes to a 90° quarter turn + fine remainder")
        XCTAssertTrue(xml.contains("crs:StraightenAngle=\"1.5"), "fine remainder after the quarter turn is 1.5°")
    }

    func testOldRecipeAndAssetJSONWithoutNewFieldsDecodeWithDefaults() throws {
        // Shaped like JSON written before cameraProfile/cropAspect/recipeSource/handRecipe existed.
        let oldRecipeJSON = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","schemaVersion":2,"exposure":0.3,
         "temperature":6500,"tint":0,"contrast":0,"highlights":0,"shadows":0,"whites":0,
         "blacks":0,"texture":0,"clarity":0,"dehaze":0,"vibrance":0,"saturation":0,
         "sharpness":0,"luminanceNR":0,"straightenDegrees":0,"retouch":[],
         "sourceNeighbors":[],"confidence":1}
        """
        let decodedRecipe = try EditRecipe.decode(Data(oldRecipeJSON.utf8))
        XCTAssertEqual(decodedRecipe.cameraProfile, EditRecipe.defaultCameraProfile)
        XCTAssertEqual(decodedRecipe.cropAspect, .original)
        XCTAssertEqual(decodedRecipe.exposure, 0.3, accuracy: 1e-9)

        let assetID = UUID()
        let oldAssetJSON = """
        {"id":"\(assetID.uuidString)","sourceKey":"k","source":{"id":"\(UUID().uuidString)",
         "originalPath":"/x.ARW","relativePath":"x.ARW","availability":"available"},
         "filename":"x.ARW","cull":"undecided","previewOrigin":"unknown","previewLongEdge":0,
         "sharpness":0,"exposureHealth":0.5,"faceQuality":0,"aesthetic":0.5,"compositeQuality":0,
         "faceDetected":false,"cullScore":0,"cullConfidence":0,"editConfidence":1,"tasteMatch":0.5,
         "isFlagged":false,"isBurstHero":true,"isClusterHero":true,"uncertaintyKind":"none"}
        """
        let decodedAsset = try JSONDecoder().decode(AssetRecord.self, from: Data(oldAssetJSON.utf8))
        XCTAssertEqual(decodedAsset.recipeSource, .shot)
        XCTAssertNil(decodedAsset.handRecipe)
        XCTAssertEqual(decodedAsset.id, assetID)
    }
}
