import XCTest

/// Acceptance-criterion tests for the P0 UX-hardening changes (see
/// docs/P0_UI_AUTOMATION_POSTMORTEM.md §6). Each test pins the improved behavior.
final class UXHardeningTests: LuminaUITestCase {

    /// #1 — the contact sheet is keyboard-ready on open: arrows move focus without any prior click.
    func testGridIsKeyboardReadyOnOpen() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let before = lumina.requireProbe()
        XCTAssertNotNil(before.focusedAssetID, "a default focus exists on open")

        // No click — press the arrow directly.
        sheet.focusNext()
        let after = lumina.waitForProbe { $0.focusedAssetID != before.focusedAssetID }
        XCTAssertNotEqual(after.focusedAssetID, before.focusedAssetID,
                          "arrow keys should move focus immediately on open, with no click needed")
        Invariants.assert(after, app: app)
    }

    /// #3 — density controls have comfortable hit targets (were ~6pt wide).
    func testDensityControlsHaveComfortableHitTargets() {
        launch(LaunchConfig(fixture: .mixed60, windowSize: CGSize(width: 1280, height: 800)))
        let sheet = lumina.openShoot.open(.mixed60)
        for id in [P0AXID.densityDecrease, P0AXID.densityIncrease] {
            let control = sheet.element(id)
            XCTAssertTrue(control.waitForExistence(timeout: 8), "\(id) exists")
            XCTAssertGreaterThanOrEqual(control.frame.width, 24, "\(id) hit target width >= 24pt")
            XCTAssertGreaterThanOrEqual(control.frame.height, 24, "\(id) hit target height >= 24pt")
        }
    }
}
