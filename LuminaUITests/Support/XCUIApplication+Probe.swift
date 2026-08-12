import Foundation
import XCTest

extension XCUIApplication {
    /// The hidden structured-state probe element (present whenever the harness is active and the
    /// app's window/accessibility tree has mounted).
    func stateProbeElement() -> XCUIElement {
        descendants(matching: .any).matching(identifier: P0AXID.stateProbe).firstMatch
    }

    /// Current decoded session snapshot, or nil when unavailable (e.g. tree not mounted yet).
    func probe() -> ProbeSnapshot? {
        let element = stateProbeElement()
        guard element.exists, let value = element.value as? String else { return nil }
        return ProbeSnapshot.decode(value)
    }

    /// Poll the probe (observable state — not a fixed sleep) until `predicate` holds or `timeout`.
    ///
    /// Returns the snapshot **only when the predicate matched**; returns nil on timeout — even if
    /// non-matching snapshots were seen. Callers must treat nil as failure. (An earlier version
    /// returned the last snapshot seen on timeout, which made `!= nil` look like success while the
    /// app was in the wrong state — the enabler of the Recent-row dead-poll cascade.)
    @discardableResult
    func waitForProbe(
        timeout: TimeInterval = UITestWait.transition,
        where predicate: (ProbeSnapshot) -> Bool
    ) -> ProbeSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var nextActivation = Date()
        return ProbePolling.waitUntil(
            deadline: deadline,
            pollInterval: 0.05,
            snapshot: { [weak self] in
                guard let self else { return nil }
                if self.state != .runningForeground, Date() >= nextActivation {
                    self.activate()
                    nextActivation = Date().addingTimeInterval(3)
                }
                return self.probe()
            },
            where: predicate
        )
    }
}
