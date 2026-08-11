#if DEBUG
import Foundation

/// Harness fake clock for debounce / fade timings.
///
/// DEBUG-only. Release builds do not compile this file; there is no clock injection
/// socket in shipping binaries. Product code may read `HarnessFakeClock.now` only
/// behind `#if DEBUG` + `UITestSupport.isActive` guards.
enum HarnessFakeClock {
    nonisolated(unsafe) private static var lockedMs: Int?
    nonisolated(unsafe) private static var offsetMs: Int = 0

    /// Current harness time. Falls back to wall clock when not active.
    static var now: Date {
        if let lockedMs {
            return Date(timeIntervalSince1970: TimeInterval(lockedMs) / 1000.0)
        }
        if UITestSupport.isActive {
            return Date().addingTimeInterval(TimeInterval(offsetMs) / 1000.0)
        }
        return Date()
    }

    static var nowMs: Int {
        Int(now.timeIntervalSince1970 * 1000.0)
    }

    static func reset() {
        lockedMs = nil
        offsetMs = 0
    }

    static func advance(ms: Int) {
        precondition(UITestSupport.isActive || lockedMs != nil, "fake clock advance outside harness")
        if let lockedMs {
            self.lockedMs = lockedMs + ms
        } else {
            offsetMs += ms
        }
    }

    static func lock(ms: Int) {
        lockedMs = ms
    }
}
#endif
