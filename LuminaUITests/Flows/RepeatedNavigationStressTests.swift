import XCTest

/// Flow 9 — sustained navigation over mixed-200 never crashes, hangs, or blanks the surface.
final class RepeatedNavigationStressTests: LuminaUITestCase {

    func testSustainedNavigationRemainsHealthy() {
        launch(LaunchConfig(fixture: .mixed200))
        let sheet = lumina.openShoot.open(.mixed200)
        XCTAssertEqual(lumina.requireProbe().assetCount, 200)

        sheet.focus(index: 0)
        let clock = Date()
        let changes = 120

        XCTContext.runActivity(named: "Repeat arrow navigation \(changes)×, with photo open/close and P/X") { _ in
            for step in 0..<changes {
                sheet.focusNext()
                if step % 20 == 10 {
                    // Open and close single-photo mode.
                    sheet.openFocused().returnToGrid()
                }
                if step % 7 == 0 {
                    step % 14 == 0 ? sheet.pressKeep() : sheet.pressReject()
                }
                if step % 30 == 0 {
                    // Periodically confirm the surface is still healthy (not blank / not hung).
                    let probe = lumina.waitForProbe(timeout: 8) { $0.route != "open" && $0.assetCount == 200 }
                    Invariants.assert(probe, app: app)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(clock)
        record("repeated navigation elapsed: \(String(format: "%.1f", elapsed))s over \(changes) changes")
        let final = lumina.waitForProbe(timeout: 10) { $0.assetCount == 200 }
        XCTAssertEqual(final.assetCount, 200, "no assets lost")
        XCTAssertNotEqual(final.route, "open", "did not fall back to a blank/open state")
        Invariants.assert(final, app: app)
    }
}
