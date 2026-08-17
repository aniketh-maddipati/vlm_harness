import Foundation

/// UI-test copy of `Lumina/Core/ProbePolling.swift`.
/// XCUITest cannot import the app module; waitUntil still returns nil unless the predicate matched.
/// The yield callback is a RunLoop turn — not a wall-clock sleep (F04.3).
enum ProbePolling {
    typealias Now = () -> Date
    typealias Yield = (TimeInterval) -> Void

    static func waitUntil<T>(
        deadline: Date,
        pollInterval: TimeInterval,
        now: @escaping Now = Date.init,
        yield: @escaping Yield = { interval in
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        },
        snapshot: () -> T?,
        where predicate: (T) -> Bool
    ) -> T? {
        while now() < deadline {
            if let value = snapshot(), predicate(value) {
                return value
            }
            yield(pollInterval)
        }
        return nil
    }
}
