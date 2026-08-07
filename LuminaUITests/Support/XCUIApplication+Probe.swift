import Foundation
import XCTest

extension XCUIApplication {
    /// The hidden structured-state probe element (present whenever a shoot is open).
    func stateProbeElement() -> XCUIElement {
        descendants(matching: .any).matching(identifier: P0AXID.stateProbe).firstMatch
    }

    /// Current decoded session snapshot, or nil when unavailable (e.g. Open surface).
    func probe() -> ProbeSnapshot? {
        let element = stateProbeElement()
        guard element.exists, let value = element.value as? String else { return nil }
        return ProbeSnapshot.decode(value)
    }

    /// Poll the probe (observable state — not a fixed sleep) until `predicate` holds or `timeout`.
    /// Returns the matching snapshot, or the last snapshot seen (or nil) on timeout.
    @discardableResult
    func waitForProbe(
        timeout: TimeInterval = 10,
        where predicate: (ProbeSnapshot) -> Bool
    ) -> ProbeSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: ProbeSnapshot?
        while Date() < deadline {
            if let snapshot = probe() {
                last = snapshot
                if predicate(snapshot) { return snapshot }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return last
    }
}
