import Foundation
import XCTest

/// Drives the single-photo surface: filmstrip navigation, cull at photo scale, undo, and return.
struct SinglePhotoRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    @discardableResult
    func assertVisible(timeout: TimeInterval = UITestWait.transition) -> SinglePhotoRobot {
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "singlePhoto" }
        XCTAssertEqual(snapshot?.route, "singlePhoto", "Single-photo surface never reported route=singlePhoto")
        return self
    }

    /// The filmstrip is detected via its items (its container carries no identifier — see the
    /// container-propagation rule in P0AccessibilityID).
    func hasFilmstripItems() -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", P0AXID.filmstripItemPrefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
            .waitForExistence(timeout: UITestWait.elementExistence)
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
        _ = app.waitForProbe(timeout: UITestWait.transition) { $0.route == "contactSheet" }
        return sheet
    }

    /// Return to the contact sheet by clicking the Grid button.
    @discardableResult
    func returnToGridByButton() -> ContactSheetRobot {
        app.descendants(matching: .any).matching(identifier: P0AXID.gridReturn).firstMatch.click()
        let sheet = ContactSheetRobot(app: app, test: test)
        _ = app.waitForProbe(timeout: UITestWait.transition) { $0.route == "contactSheet" }
        return sheet
    }
}
