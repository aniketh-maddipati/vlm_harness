import XCTest

/// Flow 5 — grid → photograph → grid, restoring focus and approximate scroll.
final class GridPhotoRestoreTests: LuminaUITestCase {

    func testOpenPhotographNavigateAndReturnRestoresState() {
        launch(LaunchConfig(fixture: .mixed200))
        let sheet = lumina.openShoot.open(.mixed200)
        let ids = sheet.visibleIDs()

        sheet.focus(assetID: ids[3])
        let selected = lumina.waitForProbe { $0.focusedAssetID == ids[3] }
        XCTAssertTrue(selected.selectedAssetIDs.isEmpty, "pointer focus is not a hidden selection")
        let selectionBefore = selected.selectedAssetIDs

        // Scroll well into the sheet.
        sheet.scroll(dy: -600, times: 5)
        let scrolled = lumina.waitForProbe(timeout: UITestWait.transition) { $0.scrollAnchor > 0.03 }
        XCTAssertGreaterThan(scrolled.scrollAnchor, 0.03, "scrolled into the contact sheet")
        let anchorBefore = scrolled.scrollAnchor

        // Open the focused photograph.
        let single = XCTContext.runActivity(named: "Open photograph") { _ -> SinglePhotoRobot in
            let s = sheet.openFocused()
            XCTAssertTrue(s.hasFilmstripItems(), "filmstrip should be present at single-photo scale")
            XCTAssertTrue(lumina.requireProbe().chapterTableMounted, "inspect must keep the chapter table mounted")
            return s
        }

        // Navigate + cull + undo at single-photo scale.
        single.navigateNext()
        _ = lumina.waitForProbe(timeout: UITestWait.transition) { $0.route == "singlePhoto" }
        let cullFocus = lumina.requireProbe().focusedAssetID
        let cullWas = cullFocus.flatMap { lumina.requireProbe().culls[$0] }
        single.pressReject()
        _ = lumina.waitForProbe { $0.culls[cullFocus ?? ""] != cullWas }
        single.undo()
        _ = lumina.waitForProbe { $0.culls[cullFocus ?? ""] == cullWas }

        // Return to grid with Escape.
        single.returnToGrid()
        let back = lumina.waitForProbe { $0.route == "contactSheet" }
        XCTAssertEqual(back.route, "contactSheet")
        XCTAssertEqual(back.selectedAssetIDs, selectionBefore, "pointer travel must not invent selection across inspect")
        XCTAssertEqual(back.scrollAnchor, anchorBefore, accuracy: 0.2, "approximate scroll position restored")
        Invariants.assert(back, app: app)
    }
}
