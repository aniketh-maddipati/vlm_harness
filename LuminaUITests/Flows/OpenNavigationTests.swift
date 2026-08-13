import XCTest

/// Flow 1 — open a prepared shoot and navigate the contact sheet.
final class OpenNavigationTests: LuminaUITestCase {

    /// The one dedicated Recent-list UX test (autoOpen off so the app stays on Open). Proves the
    /// full real interaction: route=open, the fixture seeded in the isolated ShootStore, the
    /// Recent row accessible within a bounded window, and a **single** click reaching the contact
    /// sheet. Deterministic flows never depend on this row (they auto-open via `openExisting`).
    func testRecentRowOpensPreparedShoot() {
        let config = LaunchConfig(fixture: .mixed60, autoOpen: false)
        launch(config)
        lumina.openShoot.assertVisible()
        XCTAssertTrue(
            OpenShootRobot.seededShoots(in: config.stateDirectory).contains(Fixture.mixed60.rawValue),
            "mixed-60 must exist in the isolated seeded ShootStore state"
        )
        let chooseFolder = app.descendants(matching: .any)
            .matching(identifier: P0AXID.openChooseFolder).firstMatch
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: UITestWait.transition), "Choose-a-folder control is reachable")
        lumina.openShoot.openViaRecentRow(.mixed60)
        let probe = lumina.requireProbe()
        XCTAssertEqual(probe.route, "contactSheet")
        XCTAssertEqual(probe.assetCount, 60, "mixed-60 should expose 60 assets after the row click")
    }

    /// Opening the prepared shoot reaches the contact sheet with its full asset set (real
    /// open/command/persistence path via openExisting).
    func testOpenPreparedShootShowsContactSheet() {
        launch(LaunchConfig(fixture: .mixed60))
        lumina.openShoot.open(.mixed60)
        let probe = lumina.requireProbe()
        XCTAssertEqual(probe.route, "contactSheet")
        XCTAssertEqual(probe.assetCount, 60, "mixed-60 should expose 60 assets")
        Invariants.assert(probe, app: app)
    }

    func testArrowKeysMoveFocus() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)

        XCTContext.runActivity(named: "Focus a known cell, then arrow right") { _ in
            let before = sheet.focus(index: 2).requireFocus()
            let expectedNext = before.visibleID(at: 3)

            sheet.focusNext()
            let after = lumina.waitForProbe { $0.focusedAssetID != before.focusedAssetID }
            XCTAssertEqual(after.focusedAssetID, expectedNext, "right arrow should advance focus to the next visible asset")
            Invariants.assert(after, app: app)
        }
    }

    func testDensityControlsChangeColumnsAndStayResponsive() {
        launch(LaunchConfig(fixture: .mixed60))
        let sheet = lumina.openShoot.open(.mixed60)
        let start = lumina.requireProbe().densityColumns

        XCTContext.runActivity(named: "Increase then decrease density via toolbar controls") { _ in
            sheet.tapDensityMore()
            let more = lumina.waitForProbe { $0.densityColumns != start }
            XCTAssertGreaterThan(more.densityColumns, start, "more photographs = more columns")

            sheet.tapDensityFewer()
            let back = lumina.waitForProbe { $0.densityColumns == start }
            XCTAssertEqual(back.densityColumns, start, "app remains responsive to density controls")
            Invariants.assert(back, app: app)
        }
    }
}

extension ContactSheetRobot {
    /// Assert there is a focused asset and return the current snapshot.
    func requireFocus(file: StaticString = #file, line: UInt = #line) -> ProbeSnapshot {
        guard let snapshot = app.waitForProbe(timeout: UITestWait.transition, where: { $0.focusedAssetID != nil }) else {
            XCTFail("expected a focused asset within \(Int(UITestWait.transition))s", file: file, line: line)
            return ProbeSnapshot(
                route: "contactSheet", shootName: nil, fixture: nil, seed: "0",
                assetCount: 0, visibleCount: 0, selectionCount: 0, keptCount: 0,
                rejectedCount: 0, unreviewedCount: 0, editedCount: 0, densityColumns: 0,
                filter: "", canUndo: false, focusedAssetID: nil, focusedVisible: false,
                focusedAvailability: nil, focusedCull: nil, inspectingAssetID: nil,
                selectedAssetIDs: [], missingOriginalCount: 0, previewReadyCount: 0,
                phaseDetail: "", scrollAnchor: 0, culls: [:], editedIDs: [], visibleAssetIDs: [],
                missingAssetIDs: [], keyRoutingOwner: "P0KeyRoutingModifier"
            )
        }
        return snapshot
    }
}
