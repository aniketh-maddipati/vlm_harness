import Foundation
import XCTest

/// Drives the Open surface. Two strictly separated contracts:
///
/// 1. **Deterministic navigation** (`open`) — used by cull/undo/persistence/explorer flows.
///    Relies exclusively on the DEBUG auto-open path (`--ui-test-autoopen`), which routes through
///    the real `openExisting` product behavior. One bounded probe wait; on failure it reports
///    diagnostics and stops. It never looks up or clicks a Recent-row accessibility element —
///    a fallback that did so used to dead-poll `p0.open.recent.<name>` for 40+ s against an app
///    that was on the contact sheet (or already terminated), stacking nested timeouts past 120 s.
///
/// 2. **Recent-list UX** (`openViaRecentRow`) — the one dedicated test of the real Recent-row
///    interaction. Bounded row wait, a single click, bounded transition wait, rich diagnostics.
struct OpenShootRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    @discardableResult
    func assertVisible(timeout: TimeInterval = UITestWait.transition) -> OpenShootRobot {
        // The Open ZStack isn't itself an accessibility element; anchor on the probe route (always
        // present under the harness).
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "open" }
        if snapshot == nil {
            failWithDiagnostics("Open surface never reported route=open within \(Int(timeout))s")
        }
        return self
    }

    /// Deterministic navigation: wait for the auto-opened fixture to reach the contact sheet via
    /// the real `openExisting` path. Requires the launch to have used `autoOpen` (the default).
    @discardableResult
    func open(_ fixture: Fixture, timeout: TimeInterval = UITestWait.autoOpenNavigation) -> ContactSheetRobot {
        if let config = (test as? LuminaUITestCase)?.activeConfig, !config.autoOpen {
            XCTFail("open(_:) requires autoOpen; use openViaRecentRow(_:) for the Recent-list UX test")
            return ContactSheetRobot(app: app, test: test)
        }
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "contactSheet" && $0.assetCount > 0 }
        if snapshot == nil {
            failWithDiagnostics("auto-open of \(fixture.rawValue) never reached the contact sheet within \(Int(timeout))s")
        }
        return ContactSheetRobot(app: app, test: test)
    }

    /// Recent-list UX: prove the row is accessible on the Open surface and that a **single** click
    /// navigates to the contact sheet. Requires a launch with `autoOpen: false`.
    @discardableResult
    func openViaRecentRow(_ fixture: Fixture) -> ContactSheetRobot {
        assertVisible()
        let row = app.descendants(matching: .any)
            .matching(identifier: P0AXID.recentShoot(fixture.rawValue))
            .firstMatch
        // Two bounded halves of the same `recentRow` budget with a re-activation between them:
        // if the interactive user fronts another app mid-test, the collapsed accessibility tree
        // hides the row even though the Open surface is rendered. Not a retry loop — the total
        // wait never exceeds `UITestWait.recentRow`.
        if app.state != .runningForeground { app.activate() }
        if !row.waitForExistence(timeout: UITestWait.recentRow / 2) {
            app.activate()
            if !row.waitForExistence(timeout: UITestWait.recentRow / 2) {
                failWithDiagnostics("Recent row \(P0AXID.recentShoot(fixture.rawValue)) did not appear within \(Int(UITestWait.recentRow))s of route=open")
                return ContactSheetRobot(app: app, test: test)
            }
        }
        // One semantic click on the row itself; the dedicated Recent-list UX test owns this
        // identifier-coupled surface check, not the blocking plan.
        row.click()
        let snapshot = app.waitForProbe(timeout: UITestWait.transition) { $0.route == "contactSheet" }
        if snapshot == nil {
            failWithDiagnostics("one click on the Recent row did not reach route=contactSheet within \(Int(UITestWait.transition))s")
        }
        return ContactSheetRobot(app: app, test: test)
    }

    // MARK: - Diagnostics

    /// Fail with everything needed to triage without re-running: probe route, app activation
    /// state, state root, the shoots actually seeded on disk, and a concise accessibility excerpt.
    private func failWithDiagnostics(_ reason: String, file: StaticString = #filePath, line: UInt = #line) {
        var lines: [String] = [reason]
        lines.append("probe route: \(app.probe()?.route ?? "<no probe>")")
        lines.append("app state: \(app.state.rawValue) (4 = runningForeground)")
        if let config = (test as? LuminaUITestCase)?.activeConfig {
            lines.append("state root: \(config.stateDirectory.path)")
            lines.append("seeded shoots: \(Self.seededShoots(in: config.stateDirectory))")
        }
        lines.append("accessibility excerpt:\n\(String(app.debugDescription.prefix(1_500)))")
        XCTFail(lines.joined(separator: "\n"), file: file, line: line)
    }

    /// Shoot directories present in the isolated ShootStore state root (ground truth for whether
    /// fixture seeding/persistence worked, independent of the app's accessibility tree).
    static func seededShoots(in stateDirectory: URL) -> [String] {
        let projects = stateDirectory
            .appendingPathComponent("Lumina", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return names.sorted()
    }
}
