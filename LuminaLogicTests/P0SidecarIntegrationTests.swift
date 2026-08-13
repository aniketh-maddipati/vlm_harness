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

    func testD36_sessionEditCommitWritesSidecarBesideOriginal() throws {
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmp.path))
        let parsed = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp))
        XCTAssertEqual(parsed.exposure, 0.35, accuracy: 1e-6)
        XCTAssertTrue(ShootSidecarStore.assertNoLuminaPrivateStore(besideOriginal: rawURL))
    }

    func testD35_sidecarDriftDetectedWithoutMutatingSessionRecipe() throws {
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
}
