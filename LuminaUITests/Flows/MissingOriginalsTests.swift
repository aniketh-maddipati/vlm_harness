import XCTest

/// Flow 7 — missing originals keep cached previews and never delete the catalog.
final class MissingOriginalsTests: LuminaUITestCase {

    func testMissingOriginalsPreserveCatalogAndPreviews() {
        launch(LaunchConfig(fixture: .missingOriginals))
        let sheet = lumina.openShoot.open(.missingOriginals)

        let probe = lumina.waitForProbe { $0.assetCount > 0 }
        XCTAssertGreaterThan(probe.missingOriginalCount, 0, "fixture should have some unavailable originals")
        XCTAssertGreaterThan(probe.previewReadyCount, 0, "cached previews remain visible")
        let assetCount = probe.assetCount

        guard let missing = probe.missingAssetIDs.first(where: { probe.visibleAssetIDs.contains($0) }) else {
            return XCTFail("expected a visible asset with a missing original")
        }

        // Open the unavailable asset; the cached preview still shows, and the probe reports the
        // factual unavailable-original state.
        sheet.focus(assetID: missing)
        let single = sheet.openFocused()
        let inPhoto = lumina.waitForProbe { $0.route == "singlePhoto" }
        XCTAssertEqual(inPhoto.focusedAvailability, "missing", "structured state reports the original as unavailable")
        XCTAssertTrue(single.image.waitForExistence(timeout: 8), "cached preview remains visible for a missing original")
        // #6 — an in-place affordance surfaces the unavailable original (not just a global hint).
        let offline = app.descendants(matching: .any)
            .matching(identifier: P0AXID.singlePhotoOriginalOffline).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 8), "single-photo shows an Original-offline affordance")

        // Catalog is intact; return to grid cleanly.
        single.returnToGrid()
        let back = lumina.waitForProbe { $0.route == "contactSheet" }
        XCTAssertEqual(back.assetCount, assetCount, "missing originals must not delete assets")
        Invariants.assert(back, app: app)
    }
}
