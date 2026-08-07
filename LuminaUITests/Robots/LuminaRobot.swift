import Foundation
import XCTest

/// Top-level façade. Owns the app handle and vends surface-specific robots so tests read as user
/// intent rather than raw queries.
struct LuminaRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    var openShoot: OpenShootRobot { OpenShootRobot(app: app, test: test) }
    var contactSheet: ContactSheetRobot { ContactSheetRobot(app: app, test: test) }
    var singlePhoto: SinglePhotoRobot { SinglePhotoRobot(app: app, test: test) }

    var window: XCUIElement { app.windows.firstMatch }

    // MARK: - Structured state

    func probe() -> ProbeSnapshot? { app.probe() }

    @discardableResult
    func waitForProbe(timeout: TimeInterval = 12, where predicate: (ProbeSnapshot) -> Bool) -> ProbeSnapshot {
        guard let snapshot = app.waitForProbe(timeout: timeout, where: predicate) else {
            XCTFail("state probe never satisfied predicate within \(timeout)s", file: #file, line: #line)
            return ProbeSnapshot(
                route: "unknown", shootName: nil, fixture: nil, seed: "0",
                assetCount: 0, visibleCount: 0, selectionCount: 0, keptCount: 0,
                rejectedCount: 0, unreviewedCount: 0, editedCount: 0, densityColumns: 0,
                filter: "", canUndo: false, focusedAssetID: nil, focusedVisible: false,
                focusedAvailability: nil, focusedCull: nil, inspectingAssetID: nil,
                selectedAssetIDs: [], missingOriginalCount: 0, previewReadyCount: 0,
                phaseDetail: "", scrollAnchor: 0, culls: [:], editedIDs: [], visibleAssetIDs: [],
                missingAssetIDs: []
            )
        }
        return snapshot
    }

    /// Require a snapshot right now (fails if unavailable).
    func requireProbe(_ message: String = "expected an open shoot", file: StaticString = #file, line: UInt = #line) -> ProbeSnapshot {
        guard let snapshot = app.probe() else {
            XCTFail(message, file: file, line: line)
            return waitForProbe { _ in true }
        }
        return snapshot
    }

    // MARK: - Window control

    /// Resize the main window by dragging its bottom-right corner by the needed delta.
    /// (Used for the "larger desktop" layout case; the pinned size comes from the launch arg.)
    func resizeWindow(to size: CGSize) {
        let window = app.windows.firstMatch
        guard window.exists else { return }
        let frame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        let target = corner.withOffset(CGVector(dx: size.width - frame.width, dy: size.height - frame.height))
        corner.press(forDuration: 0.2, thenDragTo: target)
    }
}

/// Shared pointer helpers.
enum Pointer {
    /// Atomic modifier-click (Command-click, Shift-click) via held global modifiers.
    static func click(_ element: XCUIElement, modifiers: XCUIElement.KeyModifierFlags) {
        if modifiers.isEmpty {
            element.click()
        } else {
            XCUIElement.perform(withKeyModifiers: modifiers) {
                element.click()
            }
        }
    }
}
