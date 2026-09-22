import XCTest

/// Flow 4 — pointer travel changes focus only; typed P/X decide on current focus.
final class SelectionFocusTests: LuminaUITestCase {

    func testFocusAndSelectionAreIndependent() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let ids = sheet.visibleIDs()

        sheet.focus(assetID: ids[2])
        let focused = lumina.waitForProbe { $0.focusedAssetID == ids[2] }
        XCTAssertEqual(focused.focusedAssetID, ids[2])
        XCTAssertTrue(focused.selectedAssetIDs.isEmpty, "pointer travel must not create hidden selection")
        XCTAssertEqual(focused.selectionCount, 0)

        sheet.focus(assetID: ids[5])
        let moved = lumina.waitForProbe { $0.focusedAssetID == ids[5] }
        XCTAssertEqual(moved.focusedAssetID, ids[5])
        XCTAssertTrue(moved.selectedAssetIDs.isEmpty, "repeat pointer travel must not grow selection")

        let cullBefore = moved.culls[ids[5]]
        sheet.pressKeep()
        let afterCull = lumina.waitForProbe { $0.culls[ids[5]] != cullBefore }
        XCTAssertEqual(afterCull.culls[ids[5]], "keep", "typed P applies to pointer focus")
        XCTAssertTrue(afterCull.selectedAssetIDs.isEmpty, "cull must not invent selection")
        Invariants.assert(afterCull, app: app)
    }
}
