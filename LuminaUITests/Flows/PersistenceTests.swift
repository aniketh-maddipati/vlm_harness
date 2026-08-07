import XCTest

/// Flow 6 — cull decisions survive terminate + relaunch against the same state directory.
final class PersistenceTests: LuminaUITestCase {

    func testCullDecisionsPersistAcrossRelaunch() {
        launch(LaunchConfig(fixture: .mixed60))
        var sheet = lumina.openShoot.open(.mixed60)
        let ids = sheet.visibleIDs()

        // Drive a few assets to a definite decision and record the ACTUAL resulting cull (the
        // toggle grammar depends on the starting state, so we read the outcome rather than assume).
        var expected: [String: String] = [:]
        func setKeep(_ id: String) {
            sheet.focus(assetID: id)
            if lumina.requireProbe().culls[id] != "keep" { sheet.pressKeep() }
            expected[id] = lumina.waitForProbe { $0.culls[id] == "keep" }.culls[id]
        }
        func setReject(_ id: String) {
            sheet.focus(assetID: id)
            if lumina.requireProbe().culls[id] != "reject" { sheet.pressReject() }
            expected[id] = lumina.waitForProbe { $0.culls[id] == "reject" }.culls[id]
        }
        setKeep(ids[0])
        setReject(ids[1])
        setKeep(ids[2])

        // Relaunch against the SAME state directory, then reopen the shoot.
        XCTContext.runActivity(named: "Terminate and relaunch same state") { _ in
            relaunch()
            sheet = lumina.openShoot.open(.mixed60)
        }

        let restored = lumina.waitForProbe { probe in expected.allSatisfy { probe.culls[$0.key] == $0.value } }
        for (id, want) in expected {
            XCTAssertEqual(restored.culls[id], want, "decision for \(id) should persist as \(want)")
        }
        XCTAssertEqual(restored.assetCount, 60, "no assets lost across relaunch")
        Invariants.assert(restored, app: app)
    }
}
