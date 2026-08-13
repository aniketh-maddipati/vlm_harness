import XCTest

/// Narrow structured-state coverage for the single-photo editing probe contract
/// (`focusedRecipeFingerprint`). Asserts through the state probe only — never screenshots or text —
/// and proves the recipe/cull independence invariant that `Scripts/p0_edit_test.swift` already
/// covers deterministically, this time end-to-end through the real UI control and undo stack.
/// Persistence, crop, and full recipe-field coverage remain the deterministic script's job; this
/// flow only proves the wiring from a real gesture to the probe.
final class EditingProbeTests: LuminaUITestCase {

    func testExposureGestureUpdatesFingerprintAndUndoRestoresIt() {
        // 1 — auto-open the deterministic fixture through the real openExisting path.
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        // 2 — open the focused photograph.
        let single = sheet.openFocused()

        // 3 — the single-photo surface is up.
        let opened = lumina.waitForProbe(timeout: UITestWait.transition) { $0.route == "singlePhoto" }
        XCTAssertEqual(opened.route, "singlePhoto")

        // 4 — capture the initial recipe fingerprint and cull state.
        let initialFingerprint = opened.focusedRecipeFingerprint
        let initialCull = opened.focusedCull
        XCTAssertNotNil(initialFingerprint, "a focused asset must publish a recipe fingerprint")

        // 5 — change Exposure through the real slider control.
        XCTAssertTrue(single.exposureSlider.waitForExistence(timeout: UITestWait.transition), "Exposure control exists")
        single.adjustExposure(awayFrom: initialFingerprint)

        // 6 — the fingerprint changes.
        let edited = lumina.waitForProbe(timeout: UITestWait.transition) {
            $0.focusedRecipeFingerprint != nil && $0.focusedRecipeFingerprint != initialFingerprint
        }
        XCTAssertNotEqual(edited.focusedRecipeFingerprint, initialFingerprint, "Exposure gesture must change the recipe fingerprint")

        // 7 — cull state is untouched by the edit.
        XCTAssertEqual(edited.focusedCull, initialCull, "an edit gesture must never change cull state")

        // 8 — undo once; the original fingerprint returns.
        single.undo()
        let undone = lumina.waitForProbe(timeout: UITestWait.transition) {
            $0.focusedRecipeFingerprint == initialFingerprint
        }
        XCTAssertEqual(undone.focusedRecipeFingerprint, initialFingerprint, "undo must restore the exact prior recipe fingerprint")

        // 9 — toggling cull leaves the (now-reverted) fingerprint unchanged. P toggles relative to
        // the current decision (an already-kept photo clears to unreviewed), so assert the cull
        // moved rather than pinning a literal value the fixture may already hold.
        let cullBeforeToggle = undone.focusedCull
        single.pressKeep()
        let culled = lumina.waitForProbe(timeout: UITestWait.transition) { $0.focusedCull != cullBeforeToggle }
        XCTAssertNotEqual(culled.focusedCull, cullBeforeToggle, "P must change the cull decision")
        XCTAssertEqual(culled.focusedRecipeFingerprint, initialFingerprint, "cull must never change the recipe fingerprint")

        Invariants.assert(culled, app: app)
    }
}
