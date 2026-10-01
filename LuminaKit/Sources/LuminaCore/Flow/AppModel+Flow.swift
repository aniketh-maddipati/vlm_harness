import Foundation

// WP-1. Step switching (R-01, R-02, R-60): idempotent, last press wins.

public extension AppModel {
    /// Go to a step: a tab click, ⌘1…⌘4, a screen's own button.
    ///
    /// Idempotent: going to the step already on screen changes nothing. It does not restart the
    /// ⏎ guards, clear the message or write to the store, so a held or repeated ⌘-digit is free.
    /// Last press wins: every call completes before the next one is looked at, so a burst of
    /// presses 15 ms apart ends on the step of the last one (R-02).
    func go(_ s: Step) {
        guard s != step else { return }
        if step == .edit { leaveEdit() }
        step = s
        stepChangedAt = clock.now
        toast = nil
        if s == .edit { enterEdit() }
        changed()
    }

    /// Seconds since the step last changed (the ⏎ guards: 450 ms on Open, R-01; 1.5 s on Save, R-33).
    var sinceStepChange: TimeInterval { clock.now.timeIntervalSince(stepChangedAt) }
}

// MARK: The top bar's words (README "Global shell", shoot meta)

public extension AppModel {
    /// Photos that have arrived: all of an imported folder, what has been copied of a card.
    private var arrived: Int { shoot.local ? total : min(copied, total) }

    /// "12 keepers · 5 scenes", or "No shoot open" before anything has been copied or imported.
    var shellShootTitle: String {
        arrived > 0 ? "\(decisions.keptCount) keepers · \(shoot.scenes.count) scenes" : "No shoot open"
    }

    /// `shell.copyStatus`: "Copying 42/117" while the card is being copied, "All 117 copied and
    /// checked" after, nothing before.
    var shellCopyStatus: String {
        let n = arrived
        if n == 0 { return "" }
        return n < total ? "Copying \(n)/\(total)" : "All \(total) copied and checked"
    }

    /// The copy is still running (the status is gold).
    var shellIsCopying: Bool { arrived > 0 && arrived < total }
}

public extension Step {
    /// "⌘1" … "⌘4", shown after the tab's label from 760 wide.
    var tabHint: String { "⌘\(index + 1)" }
    /// The tab's tooltip (README: only Edit and Save have one).
    var tabTooltip: String? {
        switch self {
        case .edit: "Optional · nothing changes unless you move a setting"
        case .save: "Available any time · ⌘4"
        case .open, .cull: nil
        }
    }
}
