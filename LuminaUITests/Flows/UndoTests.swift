import XCTest

/// Flow 3 — undo restores the exact prior state, and keeps working after navigation.
final class UndoTests: LuminaUITestCase {

    func testUndoRestoresExactPriorState() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        guard let target = sheet.firstVisibleID(cull: "undecided") else {
            return XCTFail("need an unreviewed asset")
        }
        sheet.focus(assetID: target)
        let before = lumina.requireProbe()

        sheet.pressKeep()
        let kept = lumina.waitForProbe { $0.culls[target] == "keep" }
        XCTAssertEqual(kept.culls[target], "keep")

        sheet.undo()
        let restored = lumina.waitForProbe { $0.culls[target] == "undecided" }
        XCTAssertEqual(restored.culls[target], "undecided", "undo restores the exact prior cull")
        XCTAssertEqual(restored.culls, before.culls, "whole cull map matches the pre-cull snapshot")
        Invariants.assert(restored, app: app)
    }

    func testUndoStillCorrectAfterNavigatingAwayAndBack() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        // Navigate into single-photo and back to move away from the sheet.
        sheet.focus(index: 3)
        sheet.openFocused().returnToGrid()

        guard let target = sheet.firstVisibleID(cull: "undecided") else {
            return XCTFail("need an unreviewed asset")
        }
        sheet.focus(assetID: target)
        let before = lumina.requireProbe().culls
        sheet.pressReject()
        _ = lumina.waitForProbe { $0.culls[target] == "reject" }
        sheet.undo()
        let restored = lumina.waitForProbe { $0.culls[target] == "undecided" }
        XCTAssertEqual(restored.culls, before, "undo remains correct after grid↔photo navigation")
        Invariants.assert(restored, app: app)
    }
}
