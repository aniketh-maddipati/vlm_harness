import XCTest

/// Flow 1 — open a prepared shoot and navigate the contact sheet.
final class OpenNavigationTests: LuminaUITestCase {

    /// The real Open surface renders and is accessible (autoOpen off so the app stays on Open).
    func testOpenSurfaceIsReachable() {
        launch(LaunchConfig(fixture: .mixed60, autoOpen: false))
        lumina.openShoot.assertVisible()
        let chooseFolder = app.descendants(matching: .any)
            .matching(identifier: P0AXID.openChooseFolder).firstMatch
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 10), "Choose-a-folder control is reachable")
        let recent = app.descendants(matching: .any)
            .matching(identifier: P0AXID.recentShoot(Fixture.mixed60.rawValue)).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "prepared shoot is listed in Recent")
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
        let snapshot = app.waitForProbe(timeout: 5) { $0.focusedAssetID != nil } ?? app.probe()!
        XCTAssertNotNil(snapshot.focusedAssetID, "expected a focused asset", file: file, line: line)
        return snapshot
    }
}
