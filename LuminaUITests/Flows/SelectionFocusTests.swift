import XCTest

/// Flow 4 — focus and selection are independent; culling never disturbs selection.
final class SelectionFocusTests: LuminaUITestCase {

    func testFocusAndSelectionAreIndependent() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let ids = sheet.visibleIDs()

        // Build a selection through the product's keyboard grammar so the blocking plan depends
        // only on probe state and key routing, not contact-sheet accessibility geometry.
        sheet.focus(assetID: ids[2])
        sheet.toggleSelection()
        sheet.focus(assetID: ids[5])
        sheet.toggleSelection()
        let twoSelected = lumina.waitForProbe { $0.selectionCount == 2 }
        XCTAssertEqual(twoSelected.selectionCount, 2, "space toggles the focused asset into the selection")

        sheet.focus(assetID: ids[8])
        let separated = lumina.waitForProbe {
            $0.focusedAssetID == ids[8] && $0.selectionCount == 2 && !$0.selectedAssetIDs.contains(ids[8])
        }
        XCTAssertEqual(separated.focusedAssetID, ids[8], "focus can move off the selected set")
        XCTAssertEqual(separated.selectionCount, 2, "selection survives independent focus travel")
        XCTAssertTrue(separated.focusedVisible)

        // Cull the focused asset — selection must be untouched.
        let selectionBefore = separated.selectedAssetIDs
        sheet.pressKeep()
        let afterCull = lumina.waitForProbe { $0.culls[ids[8]] != separated.culls[ids[8]] }
        XCTAssertEqual(afterCull.selectedAssetIDs, selectionBefore, "cull leaves the selection unchanged")
        Invariants.assert(afterCull, app: app)
    }
}
