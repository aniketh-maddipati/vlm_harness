import SwiftUI

/// Which plates the time table has realized — so scroll can be measured, and
/// later anticipated.
///
/// The table's tiles report through `ChapterPlateImage` when the environment
/// carries a tracker. The set shelf and the version column do not: they show
/// frames from anywhere in the shoot and would drag the visible window toward
/// frames that are nowhere near the cursor.
///
/// `LazyVStack` realizes a whole moment row at once, so `visiblePaths` is
/// "what the scroll path has asked for" — the honest set to check for wells.
///
/// Deliberately not `@Observable`: a plate appearing must never invalidate
/// the views being scrolled.
@MainActor
final class ElasticScrollTracker {
    static let shared = ElasticScrollTracker()

    /// Paths of plates SwiftUI currently has realized.
    private(set) var visiblePaths: Set<String> = []
    /// Lifetime counters — evidence, in a report, that scrolling realized rows.
    private(set) var appearEvents = 0
    private(set) var disappearEvents = 0

    init() {}

    func plateAppeared(path: String) {
        visiblePaths.insert(path)
        appearEvents += 1
    }

    func plateDisappeared(path: String) {
        visiblePaths.remove(path)
        disappearEvents += 1
    }

    /// The plate kept its identity but now shows a different frame.
    func plateChanged(from old: String, to new: String) {
        visiblePaths.remove(old)
        visiblePaths.insert(new)
    }

    func reset() {
        visiblePaths.removeAll()
        appearEvents = 0
        disappearEvents = 0
    }
}

nonisolated private struct ElasticScrollTrackerKey: EnvironmentKey {
    nonisolated static let defaultValue: ElasticScrollTracker? = nil
}

extension EnvironmentValues {
    /// Nil everywhere except under the time table.
    var elasticScrollTracker: ElasticScrollTracker? {
        get { self[ElasticScrollTrackerKey.self] }
        set { self[ElasticScrollTrackerKey.self] = newValue }
    }
}
