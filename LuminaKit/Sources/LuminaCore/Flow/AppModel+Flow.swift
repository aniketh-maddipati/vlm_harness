import Foundation

// WP-1. Step switching (R-01, R-02, R-60): idempotent, last press wins.

public extension AppModel {
    func go(_ s: Step) {
        guard s != step else { return }
        if step == .edit { leaveEdit() }
        step = s
        stepChangedAt = clock.now
        toast = nil
        if s == .edit { enterEdit() }
        changed()
    }

    /// Seconds since the step last changed (the ⏎ guards).
    var sinceStepChange: TimeInterval { clock.now.timeIntervalSince(stepChangedAt) }
}
