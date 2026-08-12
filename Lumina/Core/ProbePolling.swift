import Foundation

/// Pure probe polling — returns a snapshot **only when the predicate matched**.
///
/// On timeout returns nil even if non-matching snapshots were observed (F04.2 / postmortem §3.9
/// amplifier 3). Shared by UI tests and headless logic tests.
enum ProbePolling {
    typealias Now = () -> Date
    typealias Sleep = (TimeInterval) -> Void

    static func waitUntil<T>(
        deadline: Date,
        pollInterval: TimeInterval,
        now: @escaping Now = Date.init,
        sleep: @escaping Sleep = { interval in
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        },
        snapshot: () -> T?,
        where predicate: (T) -> Bool
    ) -> T? {
        while now() < deadline {
            if let value = snapshot(), predicate(value) {
                return value
            }
            sleep(pollInterval)
        }
        return nil
    }
}
