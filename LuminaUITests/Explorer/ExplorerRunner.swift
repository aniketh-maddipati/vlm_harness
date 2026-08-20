import Foundation
import XCTest

/// Seeded, model-based UI explorer. Not blind clicking: it reads the visible state from the probe,
/// enumerates only *legal* actions for that state, and picks one with a deterministic RNG so any
/// run is exactly replayable from its seed. Every action is followed by an invariant sweep.
final class ExplorerRunner {
    private let test: LuminaUITestCase
    /// Always read the live robot from the test case — the app handle is swapped on relaunch.
    private var lumina: LuminaRobot { test.lumina }
    private let fixture: Fixture
    private let seed: UInt64
    private var rng: SeededRNG

    /// Stack of cull maps captured immediately before each still-un-undone cull, so the undo
    /// invariant can assert an exact restore.
    private var undoExpectations: [[String: String]] = []

    private(set) var report: ExplorerReport

    init(test: LuminaUITestCase, fixture: Fixture, seed: UInt64, steps: Int) {
        self.test = test
        self.fixture = fixture
        self.seed = seed
        self.rng = SeededRNG(seed: seed)
        self.report = ExplorerReport(
            seed: seed, fixture: fixture.rawValue, requestedSteps: steps,
            completedSteps: 0, lastSuccessfulAction: nil, failedAction: nil,
            failedViolations: [], steps: []
        )
    }

    /// Run up to `steps` legal actions, checking invariants after each. Fails the test (with full
    /// evidence attached) on the first invariant violation, and always attaches the report.
    func run(steps: Int) {
        var app = test.app!
        var carried: ProbeSnapshot? = app.probe()   // reuse the prior step's post-state as this step's pre-state
        for index in 0..<steps {
            let before = carried ?? app.probe()
            let state = ExplorerState(route: before?.route ?? "open")
            let legal = legalActions(state: state, snapshot: before)
            guard !legal.isEmpty else { break }
            let action = rng.pick(legal)

            test.record("step \(index): \(state.rawValue) -> \(action.rawValue)")
            let cullBefore = before?.culls

            apply(action)
            app = test.app! // relaunch swaps the app handle

            // Read post-action state and sweep invariants.
            guard let after = app.waitForProbe(timeout: UITestWait.transition, where: { _ in true }) else {
                test.record("step \(index): probe missing after \(action.rawValue)")
                XCTFail("state probe unavailable after step \(index) (\(action.rawValue))")
                attachReport()
                return
            }
            carried = after
            var violations: [String] = []
            violations += Invariants.stateless(after, app: app)
            if action == .keep || action == .reject, let b = before, let cb = cullBefore {
                violations += Invariants.editMarkersUnchanged(before: b, after: after)
                violations += Invariants.catalogPreserved(before: b, after: after)
                if after.culls != cb { undoExpectations.append(cb) }
            }
            if action == .undo, let expected = undoExpectations.popLast() {
                if after.culls != expected {
                    violations.append("undo did not restore prior cull state")
                }
            }

            report.steps.append(ExplorerStep(
                index: index,
                action: action.rawValue,
                stateBefore: state.rawValue,
                stateAfter: ExplorerState(route: after.route).rawValue,
                routeBefore: before?.route ?? "open",
                routeAfter: after.route,
                keptBefore: before?.keptCount ?? 0,
                keptAfter: after.keptCount,
                selectionAfter: after.selectionCount,
                violations: violations
            ))
            report.completedSteps = index + 1

            if violations.isEmpty {
                report.lastSuccessfulAction = action.rawValue
            } else {
                report.failedAction = action.rawValue
                report.failedViolations = violations
                attachReport()
                XCTFail(
                    "explorer invariant violation at step \(index) after \(action.rawValue) "
                    + "(seed \(seed), fixture \(fixture.rawValue)):\n- "
                    + violations.joined(separator: "\n- ")
                )
                return
            }
        }
        attachReport()
    }

    // MARK: - Legality

    private func legalActions(state: ExplorerState, snapshot: ProbeSnapshot?) -> [ExplorerAction] {
        switch state {
        case .openShoot:
            return [.openShoot]
        case .contactSheet:
            var actions: [ExplorerAction] = [
                .focusNext, .focusPrevious, .focusUp, .focusDown,
                .keep, .reject, .increaseDensity, .decreaseDensity,
                .toggleSelection, .extendSelection, .resizeWindow,
            ]
            if snapshot?.focusedAssetID != nil { actions.append(.openFocused) }
            if snapshot?.canUndo == true { actions.append(.undo) }
            // Relaunch is legal but rare — include a single token so it stays deterministic.
            actions.append(.relaunch)
            return actions
        case .singlePhoto:
            var actions: [ExplorerAction] = [.focusNext, .focusPrevious, .keep, .reject, .closePhoto]
            if snapshot?.canUndo == true { actions.append(.undo) }
            return actions
        }
    }

    // MARK: - Apply

    private func apply(_ action: ExplorerAction) {
        let sheet = lumina.contactSheet
        let single = lumina.singlePhoto
        switch action {
        case .openShoot:
            lumina.openShoot.open(fixture)
            lumina.contactSheet.establishKeyboardFocus() // so arrows/P/X route to the sheet
        case .focusNext: sheet.focusNext()
        case .focusPrevious: sheet.focusPrevious()
        case .focusUp: sheet.focusUp()
        case .focusDown: sheet.focusDown()
        case .keep:
            if ExplorerState(route: lumina.probe()?.route ?? "") == .singlePhoto { single.pressKeep() }
            else { sheet.pressKeep() }
        case .reject:
            if ExplorerState(route: lumina.probe()?.route ?? "") == .singlePhoto { single.pressReject() }
            else { sheet.pressReject() }
        case .undo:
            if ExplorerState(route: lumina.probe()?.route ?? "") == .singlePhoto { single.undo() }
            else { sheet.undo() }
        case .toggleSelection:
            if let id = randomVisibleID() { sheet.commandClick(assetID: id) }
        case .extendSelection:
            if let id = randomVisibleID() { sheet.shiftClick(assetID: id) }
        case .openFocused:
            // Tolerant open: ensure keyboard focus, press Return, wait for the transition. The
            // post-action invariant sweep validates whatever state results (no hard assert here).
            sheet.establishKeyboardFocus()
            test.app.typeKey(.return, modifierFlags: [])
            _ = test.app.waitForProbe(timeout: UITestWait.transition) { $0.route == "singlePhoto" }
        case .closePhoto:
            test.app.typeKey(.escape, modifierFlags: [])
            _ = test.app.waitForProbe(timeout: UITestWait.transition) { $0.route == "contactSheet" }
        case .increaseDensity: sheet.increaseDensity()
        case .decreaseDensity: sheet.decreaseDensity()
        case .relaunch:
            test.relaunch()
            lumina.openShoot.open(fixture)
            lumina.contactSheet.establishKeyboardFocus()
            undoExpectations.removeAll() // undo stack does not survive relaunch
        case .resizeWindow:
            let size = rng.pick([CGSize(width: 1280, height: 800), CGSize(width: 1100, height: 720)])
            lumina.resizeWindow(to: size)
        }
    }

    /// Pick a target near the (auto-scrolled, on-screen) focused asset so selection clicks land on
    /// rendered cells rather than virtualized off-screen ones.
    private func randomVisibleID() -> String? {
        guard let probe = lumina.probe() else { return nil }
        let ids = probe.visibleAssetIDs
        guard !ids.isEmpty else { return nil }
        if let focused = probe.focusedAssetID, let idx = ids.firstIndex(of: focused) {
            let lo = max(0, idx - 10)
            let hi = min(ids.count, idx + 11)
            let window = Array(ids[lo..<hi])
            return window[rng.int(below: window.count)]
        }
        return ids[rng.int(below: min(ids.count, 24))]
    }

    private func attachReport() {
        let attachment = XCTAttachment(string: report.json())
        attachment.name = "explorer-report-seed-\(seed)"
        attachment.lifetime = .keepAlways
        test.add(attachment)
        test.record("explorer report: seed=\(seed) steps=\(report.completedSteps) lastOK=\(report.lastSuccessfulAction ?? "none")")
    }
}
