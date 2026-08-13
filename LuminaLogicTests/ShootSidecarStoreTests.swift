import XCTest
@testable import Lumina

final class ShootSidecarStoreTests: XCTestCase {

    private func makePairFolder() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-cp2-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func foreignFixtureXMP() -> String {
        let crs = LightroomHandoffService.crsNamespace
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe Lightroom Classic">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="\(crs)"
            xmlns:foreign="http://example.com/lr/1.0/"
            crs:Version="15.0"
            crs:ProcessVersion="11.0"
            crs:HasSettings="True"
            crs:Exposure2012="+0.75"
            crs:Contrast2012="+10"
            crs:Highlights2012="-15"
            crs:Shadows2012="+12"
            crs:Vibrance="+5"
            crs:Saturation="+0"
            crs:WhiteBalance="Custom"
            crs:Temperature="5800"
            crs:ColorTemperature="5800"
            crs:Tint="+3"
            foreign:CustomLook="Kodachrome"
            foreign:PresetName="Vintage Fade"/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    // MARK: - D36 — open XMP beside originals

    func testD36_writeOpenXMPBesideOriginal() throws {
        let folder = try makePairFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("frame.ARW")
        try Data([0x01]).write(to: raw)

        let recipe = EditRecipe(exposure: 0.4, contrast: 8)
        _ = try ShootSidecarStore.writeCommittedEdit(recipe, besideOriginal: raw)

        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
        XCTAssertTrue(xmp.path.hasPrefix(folder.path), "D36: sidecar lives beside the original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmp.path))
        let text = try String(contentsOf: xmp, encoding: .utf8)
        XCTAssertTrue(text.contains("crs:Exposure2012"))
        XCTAssertTrue(ShootSidecarStore.assertNoLuminaPrivateStore(besideOriginal: raw),
                      "D36: no Lumina-private receipt beside the photograph")
    }

    func testD36_readForeignXMPPreservesUnknownFields() throws {
        let folder = try makePairFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("frame.ARW")
        try Data([0x01]).write(to: raw)
        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)
        try foreignFixtureXMP().write(to: xmp, atomically: true, encoding: .utf8)

        let imported = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: xmp))
        XCTAssertEqual(imported.exposure, 0.75, accuracy: 1e-6)

        let merged = try ShootSidecarStore.writeCommittedEdit(
            imported.updating { $0.exposure = 1.0 },
            besideOriginal: raw
        )
        XCTAssertNotEqual(merged.mergeOutcome, .created)

        let after = try String(contentsOf: xmp, encoding: .utf8)
        XCTAssertTrue(after.contains("Kodachrome"), "D36: foreign property preserved through merge")
        XCTAssertTrue(after.contains("Vintage Fade"), "D36: foreign preset name preserved")
        XCTAssertTrue(after.contains("foreign:CustomLook"), "D36: foreign namespace untouched")
    }

    func testD36_lrRoundTripSurvivesReimport() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureDir = root.appendingPathComponent("Scripts/harness/fixtures/cp2/jpeg-sidecar-pair")
        let raw = fixtureDir.appendingPathComponent("DSC0001.ARW")
        let fixtureXMP = fixtureDir.appendingPathComponent("DSC0001.xmp")

        let work = try makePairFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let workRaw = work.appendingPathComponent("DSC0001.ARW")
        let workXMP = work.appendingPathComponent("DSC0001.xmp")
        try Data(contentsOf: raw).write(to: workRaw)
        try Data(contentsOf: fixtureXMP).write(to: workXMP)

        let imported = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: workXMP))
        XCTAssertEqual(imported.exposure, 0.75, accuracy: 1e-6)

        _ = try ShootSidecarStore.writeCommittedEdit(
            imported.updating { $0.exposure = 1.0 },
            besideOriginal: workRaw
        )

        let reimported = try XCTUnwrap(try ShootSidecarStore.readMappedRecipe(at: workXMP))
        XCTAssertEqual(reimported.exposure, 1.0, accuracy: 1e-6)

        let shootEntries = try FileManager.default.contentsOfDirectory(atPath: work.path).sorted()
        XCTAssertEqual(Set(shootEntries), ["DSC0001.ARW", "DSC0001.xmp"],
                       "D36 jpeg-sidecar-pair: open-XMP shoot has no Lumina-private store files")
        let merged = try String(contentsOf: workXMP, encoding: .utf8)
        XCTAssertTrue(merged.contains("Kodachrome"))
    }

    // MARK: - Reconciliation — journal truth in-session

    func testD35_reconciliationSessionWinsOnExternalDrift() throws {
        let folder = try makePairFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("frame.ARW")
        try Data([0x01]).write(to: raw)

        let sessionRecipe = EditRecipe(exposure: 0.5)
        let write = try ShootSidecarStore.writeCommittedEdit(sessionRecipe, besideOriginal: raw)
        let xmp = ShootSidecarStore.sidecarURL(besideOriginal: raw)

        var external = try String(contentsOf: xmp, encoding: .utf8)
        external = external.replacingOccurrences(of: "Exposure2012=\"+0.50\"", with: "Exposure2012=\"+9.99\"")
        external = external.replacingOccurrences(of: "Exposure2012=\"0.50\"", with: "Exposure2012=\"9.99\"")
        if !external.contains("Exposure2012=\"+9.99\"") {
            external = external.replacingOccurrences(
                of: "crs:Exposure2012=\"+0.50\"",
                with: "crs:Exposure2012=\"+9.99\""
            )
        }
        try external.write(to: xmp, atomically: true, encoding: .utf8)

        let outcome = try ShootSidecarStore.reconcileDuringSession(
            sessionRecipe: sessionRecipe,
            lastWrittenHash: write.managedFieldsHash,
            xmpURL: xmp
        )
        guard case .externalDrift = outcome else {
            return XCTFail("expected external drift when sidecar changes underneath session")
        }

        // Session authority: in-memory recipe unchanged; disk drift waits for cold reopen.
        XCTAssertEqual(sessionRecipe.exposure, 0.5, accuracy: 1e-6,
                       "D35: session recipe stays authoritative when sidecar drifts underneath")
    }
}
