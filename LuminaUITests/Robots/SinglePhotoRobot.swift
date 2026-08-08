import Foundation
import XCTest

/// Drives the single-photo surface: filmstrip navigation, cull at photo scale, undo, and return.
struct SinglePhotoRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    @discardableResult
    func assertVisible(timeout: TimeInterval = 15) -> SinglePhotoRobot {
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "singlePhoto" }
        XCTAssertEqual(snapshot?.route, "singlePhoto", "Single-photo surface never reported route=singlePhoto")
        return self
    }

    /// The filmstrip is detected via its items (its container carries no identifier — see the
    /// container-propagation rule in P0AccessibilityID).
    func hasFilmstripItems() -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", P0AXID.filmstripItemPrefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch.waitForExistence(timeout: 8)
    }

    func filmstripItem(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: P0AXID.filmstripItem(id)).firstMatch
    }

    var image: XCUIElement {
        app.descendants(matching: .any).matching(identifier: P0AXID.singlePhotoImage).firstMatch
    }

    var unavailableNote: XCUIElement {
        app.descendants(matching: .any).matching(identifier: P0AXID.singlePhotoUnavailable).firstMatch
    }

    /// The one representative adjustment control the editing-probe flow drives — leaf element only,
    /// never a container (see `P0AccessibilityID` leaf-only rule).
    var exposureSlider: XCUIElement {
        app.descendants(matching: .any).matching(identifier: P0AXID.singlePhotoExposureSlider).firstMatch
    }

    /// Change Exposure with a real press-and-drag along the slider's track, verifying through the
    /// state probe that the recipe actually moved and retrying on a miss.
    ///
    /// Two macOS specifics make the retry necessary rather than decorative:
    /// - There is no generic AX-increment API (`adjustToNormalizedSliderPosition:` only targets
    ///   `NSSlider`/`UISlider`; this is a custom `DragGesture` control), and a zero-travel click
    ///   does not drive the gesture — so it must be a real drag.
    /// - If the app is not frontmost, macOS consumes the first mouse-down as a window-activation
    ///   click and never delivers it to the control. Re-fronting before each attempt is the same
    ///   defence `ContactSheetRobot.focus(assetID:)` uses.
    ///
    /// The drag runs in the lower portion of the combined element, clear of the title/value row.
    /// It **presses down already off-neutral** (0.80 of the track ≈ +1.8 EV; neutral 0 EV sits at
    /// the midpoint) and travels only a little further. That matters: the slider commits
    /// `draft ?? value` on gesture end, and `commitRecipeMutation` drops a no-op whose fingerprint
    /// is unchanged — so a drag that began at the midpoint would commit neutral and change nothing
    /// if SwiftUI coalesced the move events. Pressing off-neutral makes the committed value correct
    /// no matter how many `onChanged` callbacks are delivered.
    ///
    /// Bounded: at most 3 attempts × `transition`/4 verify.
    @discardableResult
    func adjustExposure(awayFrom fingerprint: String?) -> SinglePhotoRobot {
        for _ in 0..<3 {
            if app.state != .runningForeground { app.activate() }
            let start = exposureSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.85))
            let end = exposureSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.85))
            start.press(forDuration: 0.25, thenDragTo: end)
            let moved = app.waitForProbe(timeout: UITestWait.transition / 4) {
                $0.focusedRecipeFingerprint != nil && $0.focusedRecipeFingerprint != fingerprint
            }
            if moved != nil { return self }
        }
        return self
    }

    @discardableResult func navigateNext() -> SinglePhotoRobot { app.typeKey(.rightArrow, modifierFlags: []); return self }
    @discardableResult func navigatePrevious() -> SinglePhotoRobot { app.typeKey(.leftArrow, modifierFlags: []); return self }
    @discardableResult func pressKeep() -> SinglePhotoRobot { app.typeKey("p", modifierFlags: []); return self }
    @discardableResult func pressReject() -> SinglePhotoRobot { app.typeKey("x", modifierFlags: []); return self }
    @discardableResult func undo() -> SinglePhotoRobot { app.typeKey("z", modifierFlags: .command); return self }

    /// Return to the contact sheet with Escape.
    @discardableResult
    func returnToGrid() -> ContactSheetRobot {
        app.typeKey(.escape, modifierFlags: [])
        let sheet = ContactSheetRobot(app: app, test: test)
        _ = app.waitForProbe(timeout: 8) { $0.route == "contactSheet" }
        return sheet
    }

    /// Return to the contact sheet by clicking the Grid button.
    @discardableResult
    func returnToGridByButton() -> ContactSheetRobot {
        app.descendants(matching: .any).matching(identifier: P0AXID.gridReturn).firstMatch.click()
        let sheet = ContactSheetRobot(app: app, test: test)
        _ = app.waitForProbe(timeout: 8) { $0.route == "contactSheet" }
        return sheet
    }
}
