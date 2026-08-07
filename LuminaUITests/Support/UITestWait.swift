import Foundation

/// Every wait budget the harness is allowed to spend, in one place.
///
/// Rules these constants enforce (see docs/P0_UI_AUTOMATION_POSTMORTEM.md §3.9):
/// - No element lookup or probe wait may run anywhere near the 180 s per-test kill allowance.
///   The worst legal chain is launch (2 × `launchAttempt`) + one navigation wait — everything
///   else must fail fast with diagnostics instead of stacking another timeout on top.
/// - Deterministic flows wait on the **state probe** (auto-open through the real `openExisting`),
///   never on Open-surface accessibility elements.
/// - The Recent-row UX test gets one bounded row wait (`recentRow`) and one bounded
///   post-click transition wait (`transition`); it must not retry-click in a loop.
enum UITestWait {
    /// Per-attempt budget for the app's window + accessibility tree (and thus the state probe)
    /// to mount after launch. Two attempts maximum; then the test fails with diagnostics.
    static let launchAttempt: TimeInterval = 25

    /// Single bounded wait for auto-open (launch → real `openExisting` → contact sheet with
    /// assets). This is the only wait deterministic navigation is allowed to spend after launch.
    static let autoOpenNavigation: TimeInterval = 30

    /// The Recent row must appear within this window of `route == open` on a launched app
    /// (product acceptance: the list is populated before first meaningful paint).
    static let recentRow: TimeInterval = 12

    /// A single user action (click, key) must reflect in the probe within this window.
    static let transition: TimeInterval = 10
}
