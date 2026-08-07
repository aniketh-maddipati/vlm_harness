import Foundation
import XCTest

/// Drives the Open surface — reopening the prepared fixture shoot through the real recent-shoots UI.
struct OpenShootRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    @discardableResult
    func assertVisible(timeout: TimeInterval = 30) -> OpenShootRobot {
        // The Open ZStack isn't itself an accessibility element; anchor on the probe route (always
        // present under the harness) and the concrete "Choose a folder" control.
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "open" }
        XCTAssertEqual(snapshot?.route, "open", "Open surface never reported route=open")
        return self
    }

    /// Open the named fixture shoot and wait for the contact sheet.
    /// When the launch used auto-open, the app is already navigating via the real openRecent path;
    /// otherwise we click the Recent row. Uses a generous timeout because the first launch is cold.
    @discardableResult
    func open(_ fixture: Fixture, timeout: TimeInterval = 40) -> ContactSheetRobot {
        let sheet = ContactSheetRobot(app: app, test: test)
        // Auto-open (default) navigates without a click — detect it and finish fast.
        if app.waitForProbe(timeout: 8, where: { $0.route == "contactSheet" && $0.assetCount > 0 }) != nil {
            sheet.assertVisible(timeout: timeout)
            return sheet
        }
        // Manual click-through fallback.
        _ = app.waitForProbe(timeout: timeout) { $0.route == "open" }
        let recent = app.descendants(matching: .any)
            .matching(identifier: P0AXID.recentShoot(fixture.rawValue))
            .firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: timeout), "Recent shoot \(fixture.rawValue) not listed")
        // Retry the click (coordinate-center, re-resolved each attempt): cold-start layout/reflow can
        // move the row out from under a click, leaving the app on the Open surface.
        for _ in 0..<5 {
            let row = app.descendants(matching: .any)
                .matching(identifier: P0AXID.recentShoot(fixture.rawValue)).firstMatch
            if row.exists {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            if app.waitForProbe(timeout: 10, where: { $0.route == "contactSheet" }) != nil { break }
        }

        sheet.assertVisible(timeout: timeout)
        return sheet
    }
}
