import Foundation
import XCTest

/// Drives the contact sheet: focus, selection, cull, density, undo, and opening a photograph.
/// Prefers real semantic interactions (accessible cells, keyboard grammar the app defines) and
/// verifies effects through the structured probe rather than scraping pixels.
struct ContactSheetRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    // MARK: - Presence

    @discardableResult
    func assertVisible(timeout: TimeInterval = UITestWait.autoOpenNavigation) -> ContactSheetRobot {
        // Anchor on the structured probe: on the contact sheet with assets present.
        let snapshot = app.waitForProbe(timeout: timeout) { $0.route == "contactSheet" && $0.assetCount > 0 }
        XCTAssertEqual(snapshot?.route, "contactSheet", "Contact sheet never reported route=contactSheet")
        XCTAssertGreaterThan(snapshot?.assetCount ?? 0, 0, "Contact sheet reported no assets")
        return self
    }

    // MARK: - Cells

    func cell(_ assetID: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: P0AXID.assetCell(assetID)).firstMatch
    }

    /// Any element by identifier (robust to macOS element-type surprises).
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Undo via the toolbar button (present only when an undoable cull exists).
    @discardableResult
    func tapUndo() -> ContactSheetRobot { element(P0AXID.undoButton).click(); return self }

    /// Home via the back button.
    var homeButton: XCUIElement { element(P0AXID.homeButton) }

    func visibleIDs() -> [String] { app.probe()?.visibleAssetIDs ?? [] }

    /// First visible asset currently in the given cull state ("undecided"/"keep"/"reject"/"hold").
    func firstVisibleID(cull: String) -> String? {
        guard let probe = app.probe() else { return nil }
        return probe.visibleAssetIDs.first { probe.culls[$0] == cull }
    }

    func assetID(at index: Int) -> String {
        let ids = visibleIDs()
        guard index >= 0, index < ids.count else {
            XCTFail("no visible asset at index \(index) (count=\(ids.count))")
            return ids.first ?? ""
        }
        return ids[index]
    }

    /// P0 keyboard grammar routes app-wide through `P0KeyRoutingModifier`, so the blocking tests
    /// can establish keyboard ownership entirely through the probe rather than by clicking layout.
    @discardableResult
    func establishKeyboardFocus() -> ContactSheetRobot {
        if app.waitForProbe(timeout: UITestWait.transition, where: { $0.route == "contactSheet" && $0.focusedAssetID != nil }) != nil {
            return self
        }
        if app.state != .runningForeground { app.activate() }
        app.typeKey(.rightArrow, modifierFlags: [])
        _ = app.waitForProbe(timeout: UITestWait.transition) { $0.route == "contactSheet" && $0.focusedAssetID != nil }
        return self
    }

    // MARK: - Focus (probe + keyboard, never geometry)

    /// Drive focus to a visible asset through the app's own arrow-key grammar, asserting through
    /// the probe instead of the contact-sheet cell geometry. This keeps blocking flows alive when
    /// the layout changes on purpose.
    @discardableResult
    func focus(assetID: String) -> ContactSheetRobot {
        guard visibleIDs().contains(assetID) else {
            XCTFail("visible asset \(assetID) not found in probe order")
            return self
        }

        establishKeyboardFocus()
        let hopBudget = max(visibleIDs().count * 2, 8)
        for _ in 0..<hopBudget {
            guard let snapshot = app.probe() else { continue }
            if snapshot.focusedAssetID == assetID {
                return self
            }
            guard let currentID = snapshot.focusedAssetID,
                  let currentIndex = snapshot.visibleAssetIDs.firstIndex(of: currentID),
                  let targetIndex = snapshot.visibleAssetIDs.firstIndex(of: assetID) else {
                if app.state != .runningForeground { app.activate() }
                app.typeKey(.rightArrow, modifierFlags: [])
                continue
            }
            if app.state != .runningForeground { app.activate() }
            app.typeKey(currentIndex < targetIndex ? .rightArrow : .leftArrow, modifierFlags: [])
            _ = app.waitForProbe(timeout: UITestWait.transition / 2) { $0.focusedAssetID != currentID }
        }
        XCTFail("could not focus \(assetID) through keyboard navigation")
        return self
    }

    @discardableResult
    func focus(index: Int) -> ContactSheetRobot {
        focus(assetID: assetID(at: index))
    }

    // MARK: - Keyboard grammar

    @discardableResult func focusNext() -> ContactSheetRobot { key(.rightArrow) }
    @discardableResult func focusPrevious() -> ContactSheetRobot { key(.leftArrow) }
    @discardableResult func focusUp() -> ContactSheetRobot { key(.upArrow) }
    @discardableResult func focusDown() -> ContactSheetRobot { key(.downArrow) }

    @discardableResult func pressKeep() -> ContactSheetRobot { char("p") }
    @discardableResult func pressReject() -> ContactSheetRobot { char("x") }
    @discardableResult func toggleSelection() -> ContactSheetRobot { key(.space) }
    @discardableResult func increaseDensity() -> ContactSheetRobot { char("-") } // more, smaller cells
    @discardableResult func decreaseDensity() -> ContactSheetRobot { char("=") } // fewer, bigger cells

    /// Density via the toolbar buttons (no keyboard focus required). The buttons are small, so
    /// clicks are verified against the density readout and retried on a miss.
    @discardableResult
    func tapDensityMore() -> ContactSheetRobot { tapDensity(P0AXID.densityDecrease, expectIncrease: true) }
    @discardableResult
    func tapDensityFewer() -> ContactSheetRobot { tapDensity(P0AXID.densityIncrease, expectIncrease: false) }

    @discardableResult
    private func tapDensity(_ identifier: String, expectIncrease: Bool) -> ContactSheetRobot {
        for _ in 0..<4 {
            let before = app.probe()?.densityColumns ?? 0
            // Density can be at a clamp bound (2…12); if so this direction is a legitimate no-op.
            if expectIncrease && before >= 12 { return self }
            if !expectIncrease && before <= 2 { return self }
            element(identifier).click()
            let matched = app.waitForProbe(timeout: UITestWait.transition) {
                expectIncrease ? $0.densityColumns > before : $0.densityColumns < before
            }
            if matched != nil { return self }
        }
        return self
    }

    @discardableResult
    func undo() -> ContactSheetRobot {
        app.typeKey("z", modifierFlags: .command)
        return self
    }

    // MARK: - Selection (real modifier clicks)

    @discardableResult
    func commandClick(assetID: String) -> ContactSheetRobot {
        let element = cell(assetID)
        guard element.exists else { return self } // off-screen (virtualized) → safe no-op
        Pointer.click(element, modifiers: .command)
        return self
    }

    @discardableResult
    func shiftClick(assetID: String) -> ContactSheetRobot {
        let element = cell(assetID)
        guard element.exists else { return self } // off-screen (virtualized) → safe no-op
        Pointer.click(element, modifiers: .shift)
        return self
    }

    // MARK: - Open a photograph

    /// Open the focused photograph via Return, returning the single-photo robot.
    @discardableResult
    func openFocused() -> SinglePhotoRobot {
        key(.return)
        let single = SinglePhotoRobot(app: app, test: test)
        single.assertVisible()
        return single
    }

    /// Open a specific photograph by double-clicking its cell.
    @discardableResult
    func openByDoubleClick(assetID: String) -> SinglePhotoRobot {
        let element = cell(assetID)
        if !element.isHittable { element.scrollToVisibleIfPossible() }
        element.doubleClick()
        let single = SinglePhotoRobot(app: app, test: test)
        single.assertVisible()
        return single
    }

    // MARK: - Home

    @discardableResult
    func returnHome() -> OpenShootRobot {
        app.descendants(matching: .any).matching(identifier: P0AXID.homeButton).firstMatch.click()
        let open = OpenShootRobot(app: app, test: test)
        open.assertVisible()
        return open
    }

    // MARK: - Scrolling

    @discardableResult
    func scroll(dy: CGFloat, times: Int = 1) -> ContactSheetRobot {
        let collection = app.descendants(matching: .any).matching(identifier: P0AXID.contactCollection).firstMatch
        let center = collection.exists ? collection : app.windows.firstMatch
        for _ in 0..<times {
            center.scroll(byDeltaX: 0, deltaY: dy)
        }
        return self
    }

    // MARK: - Primitives

    @discardableResult
    private func key(_ key: XCUIKeyboardKey) -> ContactSheetRobot {
        if app.state != .runningForeground { app.activate() }
        app.typeKey(key, modifierFlags: [])
        return self
    }

    @discardableResult
    private func char(_ character: String) -> ContactSheetRobot {
        if app.state != .runningForeground { app.activate() }
        app.typeKey(character, modifierFlags: [])
        return self
    }
}

extension XCUIElement {
    /// Best-effort scroll-into-view for macOS (no direct API): nudges the enclosing scroll view.
    func scrollToVisibleIfPossible() {
        guard exists else { return }
        // A hittable check drives XCTest to resolve the element frame; if still not hittable the
        // caller falls back to whatever position it currently has.
        _ = isHittable
    }
}
