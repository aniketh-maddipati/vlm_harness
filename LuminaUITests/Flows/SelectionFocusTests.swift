import XCTest

/// Flow 4 — focus and selection are independent; culling never disturbs selection.
final class SelectionFocusTests: LuminaUITestCase {

    func testFocusAndSelectionAreIndependent() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let ids = sheet.visibleIDs()

        // Focus one, command-click another, then shift-select a range.
        sheet.focus(assetID: ids[2])
        sheet.commandClick(assetID: ids[5])
        let twoSelected = lumina.waitForProbe { $0.selectionCount == 2 }
        XCTAssertEqual(twoSelected.selectionCount, 2, "command-click adds to selection")

        sheet.shiftClick(assetID: ids[8])
        let ranged = lumina.waitForProbe { $0.selectionCount >= 3 }
        XCTAssertEqual(ranged.focusedAssetID, ids[8], "shift-click moves focus to the clicked cell")
        XCTAssertGreaterThanOrEqual(ranged.selectionCount, 3, "shift extends the selection to a range")
        // Independence: the focused asset is a single item; the selection is a distinct set.
        XCTAssertNotEqual(ranged.selectionCount, 1, "selection is not collapsed to just the focus")
        XCTAssertTrue(ranged.focusedVisible)

        // Cull the focused asset — selection must be untouched.
        let selectionBefore = ranged.selectedAssetIDs
        sheet.pressKeep()
        let afterCull = lumina.waitForProbe { $0.culls[ids[8]] != ranged.culls[ids[8]] }
        XCTAssertEqual(afterCull.selectedAssetIDs, selectionBefore, "cull leaves the selection unchanged")
        Invariants.assert(afterCull, app: app)
    }
}
