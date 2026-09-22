import XCTest

/// Flow 2 — cull toggle grammar at contact-sheet scale, and independence from selection/recipe.
final class CullGrammarTests: LuminaUITestCase {

    func testKeepRejectToggleGrammar() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        guard let target = sheet.firstVisibleID(cull: "undecided") else {
            return XCTFail("fixture should contain an unreviewed asset")
        }
        sheet.focus(assetID: target)

        XCTContext.runActivity(named: "P keeps, P again clears") { _ in
            sheet.pressKeep()
            assertCull(target, is: "keep")
            sheet.pressKeep()
            assertCull(target, is: "undecided")
        }

        XCTContext.runActivity(named: "X rejects, X again clears") { _ in
            sheet.pressReject()
            assertCull(target, is: "reject")
            sheet.pressReject()
            assertCull(target, is: "undecided")
        }

        XCTContext.runActivity(named: "Keep→Reject and Reject→Keep switch directly") { _ in
            sheet.pressKeep()
            assertCull(target, is: "keep")
            sheet.pressReject()
            assertCull(target, is: "reject")
            sheet.pressKeep()
            assertCull(target, is: "keep")
        }
        Invariants.assert(lumina.requireProbe(), app: app)
    }

    func testCullDoesNotDisturbSelectionOrEditMarkers() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        let ids = sheet.visibleIDs()
        sheet.focus(assetID: ids[1])
        let before = lumina.waitForProbe { $0.focusedAssetID == ids[1] }
        XCTAssertTrue(before.selectedAssetIDs.isEmpty, "pointer travel is not selection")

        let focused = before.focusedAssetID
        let cullBefore = focused.flatMap { before.culls[$0] }
        let editedBefore = before.editedIDs

        // Cull the focused photograph via the keyboard (focus is independent of selection).
        sheet.pressKeep()
        let after = lumina.waitForProbe { $0.culls[focused ?? ""] != cullBefore }

        XCTAssertEqual(after.selectedAssetIDs, before.selectedAssetIDs,
                       "cull must not change the selection set")
        XCTAssertEqual(after.editedIDs, editedBefore,
                       "cull must not change edit (recipe) markers")
        Invariants.assert(after, app: app)
    }

    private func assertCull(_ id: String, is expected: String, file: StaticString = #file, line: UInt = #line) {
        let snapshot = lumina.waitForProbe { $0.culls[id] == expected }
        XCTAssertEqual(snapshot.culls[id], expected, "asset \(id) should be \(expected)", file: file, line: line)
        Invariants.assert(snapshot, app: app, file: file, line: line)
    }
}
