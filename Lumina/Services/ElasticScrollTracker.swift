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

    /// The shoot in scroll order, and each path's position in it.
    private(set) var orderedPaths: [String] = []
    private var indexByPath: [String: Int] = [:]
    /// Median index of the realized plates — where the viewport is.
    private(set) var viewportCenter = 0

    init() {}

    /// The shoot changed (opened, re-sorted, a frame added). Hands the order to
    /// the browse service so the floor can be warmed nearest-first and evicted
    /// by distance. Same order in → no-op, so calling this on every mutation
    /// of `assets` is fine.
    func shootChanged(paths: [String]) {
        guard paths != orderedPaths else { return }
        orderedPaths = paths
        var index: [String: Int] = [:]
        for (offset, path) in paths.enumerated() where index[path] == nil {
            index[path] = offset
        }
        indexByPath = index
        Task { await BrowsePixelService.shared.setScrollOrder(paths: paths) }
    }

    func plateAppeared(path: String) {
        visiblePaths.insert(path)
        appearEvents += 1
        viewportMoved()
    }

    func plateDisappeared(path: String) {
        visiblePaths.remove(path)
        disappearEvents += 1
        viewportMoved()
    }

    /// The plate kept its identity but now shows a different frame.
    func plateChanged(from old: String, to new: String) {
        visiblePaths.remove(old)
        visiblePaths.insert(new)
        viewportMoved()
    }

    func reset() {
        visiblePaths.removeAll()
        appearEvents = 0
        disappearEvents = 0
    }

    private func viewportMoved() {
        let indices = visiblePaths.compactMap { indexByPath[$0] }.sorted()
        guard !indices.isEmpty else { return }
        let center = indices[indices.count / 2]
        guard center != viewportCenter else { return }
        viewportCenter = center
        Task { await BrowsePixelService.shared.setViewportCenter(index: center) }
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
