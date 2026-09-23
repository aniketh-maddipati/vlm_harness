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

    /// Where the centre has been, most recent last, for the velocity estimate.
    private var centerHistory: [(time: CFTimeInterval, center: Int)] = []
    /// Frames per second along the shoot order, signed. Zero when still.
    private(set) var velocity: Double = 0
    /// The direction the window is built for: +1 forward, −1 back, 0 still.
    private(set) var committedDirection = 0
    private var pendingDirection = 0
    private var pendingSince: CFTimeInterval = 0
    /// The largest |velocity| seen since `reset` — for a report.
    private(set) var peakSpeed: Double = 0
    /// The last window handed to the browse service, for a report.
    private(set) var lastWindow = PrefetchWindow.empty

    /// How far back the velocity looks. Long enough to ride out one row
    /// realizing at a time, short enough that a reversal is seen within a
    /// few frames.
    static let velocityHorizonSeconds: CFTimeInterval = 0.25
    /// Below this the reader is holding still and the window is symmetric.
    static let stillFramesPerSecond: Double = 2
    /// A change of direction must hold this long before the window turns.
    /// The median jumps backward for a sample when a row above the viewport
    /// realizes; turning on that would cancel two screens of good prefetch.
    static let reversalConfirmSeconds: CFTimeInterval = 0.12
    /// Screens ahead of the leading edge to prefetch at speed.
    static let screensAhead = 2
    /// Screens behind the trailing edge to keep before cancelling.
    static let screensKeptBehind = 1
    /// A screen is never treated as narrower than this many frames.
    static let minimumScreenFrames = 8

    let clock: () -> CFTimeInterval

    init(clock: @escaping () -> CFTimeInterval = { CACurrentMediaTime() }) {
        self.clock = clock
    }

    /// What to prefetch at the grid tier, nearest to the leading edge first,
    /// and the span of indices the service should keep or cancel around.
    struct PrefetchWindow: Equatable {
        /// Indices to warm, in issue order.
        var ahead: [Int]
        /// Indices in this span are kept; prefetch outside it is cancelled.
        var keep: ClosedRange<Int>

        static let empty = PrefetchWindow(ahead: [], keep: 0...0)
    }

    /// Pure: the window for a viewport whose realized plates span
    /// `visible`, moving at `velocity` frames/s through `count` frames.
    ///
    /// Still: one screen either side, nearest first. Moving: two screens
    /// past the leading edge in the direction of travel, plus a screen behind
    /// the trailing edge kept resident; everything further behind is
    /// cancelled.
    static func prefetchWindow(
        visible: ClosedRange<Int>,
        velocity: Double,
        count: Int
    ) -> PrefetchWindow {
        guard count > 0 else { return .empty }
        let last = count - 1
        let screen = max(visible.count, minimumScreenFrames)
        func clamp(_ index: Int) -> Int { min(max(index, 0), last) }

        if abs(velocity) < stillFramesPerSecond {
            let low = clamp(visible.lowerBound - screen)
            let high = clamp(visible.upperBound + screen)
            var ahead: [Int] = []
            for step in 1...screen {
                let below = visible.upperBound + step
                let above = visible.lowerBound - step
                if below <= high { ahead.append(below) }
                if above >= low { ahead.append(above) }
            }
            return PrefetchWindow(ahead: ahead, keep: low...high)
        }

        let forward = velocity > 0
        let leading = forward ? visible.upperBound : visible.lowerBound
        let trailing = forward ? visible.lowerBound : visible.upperBound
        let reach = screen * screensAhead
        var ahead: [Int] = []
        for step in 1...reach {
            let index = forward ? leading + step : leading - step
            guard index >= 0, index <= last else { break }
            ahead.append(index)
        }
        let behind = screen * screensKeptBehind
        let keepLow = forward ? clamp(trailing - behind) : clamp(leading - reach)
        let keepHigh = forward ? clamp(leading + reach) : clamp(trailing + behind)
        return PrefetchWindow(ahead: ahead, keep: keepLow...keepHigh)
    }

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
        centerHistory.removeAll()
        velocity = 0
        peakSpeed = 0
        committedDirection = 0
        pendingDirection = 0
        lastWindow = .empty
    }

    private func viewportMoved() {
        let indices = visiblePaths.compactMap { indexByPath[$0] }.sorted()
        guard let low = indices.first, let high = indices.last else { return }
        let center = indices[indices.count / 2]
        guard center != viewportCenter else { return }
        viewportCenter = center
        Task { await BrowsePixelService.shared.setViewportCenter(index: center) }

        // Velocity over the horizon, then the window it implies.
        let now = clock()
        centerHistory.append((now, center))
        centerHistory.removeAll { now - $0.time > Self.velocityHorizonSeconds * 2 }
        if let oldest = centerHistory.first(where: { now - $0.time <= Self.velocityHorizonSeconds }),
           now - oldest.time > 0.02 {
            velocity = Double(center - oldest.center) / (now - oldest.time)
        } else {
            velocity = 0
        }
        peakSpeed = max(peakSpeed, abs(velocity))

        // Direction with hysteresis: a reversal counts once it has held for
        // `reversalConfirmSeconds`; a blip keeps the committed direction and
        // the window it built.
        let observed = abs(velocity) < Self.stillFramesPerSecond ? 0 : (velocity > 0 ? 1 : -1)
        if observed != 0, observed != committedDirection {
            if pendingDirection != observed {
                pendingDirection = observed
                pendingSince = now
            } else if now - pendingSince >= Self.reversalConfirmSeconds {
                committedDirection = observed
                pendingDirection = 0
            }
        } else {
            pendingDirection = 0
            if observed == 0, committedDirection != 0, now - (centerHistory.last?.time ?? now) > Self.velocityHorizonSeconds {
                committedDirection = 0
            }
        }
        let effectiveVelocity: Double = committedDirection == 0
            ? (observed == 0 ? 0 : velocity)
            : Double(committedDirection) * max(abs(velocity), Self.stillFramesPerSecond)

        var window = Self.prefetchWindow(visible: low...high, velocity: effectiveVelocity, count: orderedPaths.count)
        // The median moves in phases as rows leave and arrive, so the
        // estimate dips below "still" mid-flick. A still window must not
        // cancel what a moving one just issued: keep the hull of both, and
        // let only a reversal or real distance cancel.
        if abs(effectiveVelocity) < Self.stillFramesPerSecond, lastWindow != .empty {
            window.keep = min(window.keep.lowerBound, lastWindow.keep.lowerBound)
                ... max(window.keep.upperBound, lastWindow.keep.upperBound)
        }
        guard window != lastWindow else { return }
        lastWindow = window
        let paths = orderedPaths
        let ahead = window.ahead.compactMap { paths.indices.contains($0) ? paths[$0] : nil }
        let keep = Set(window.keep.compactMap { paths.indices.contains($0) ? paths[$0] : nil })
        Task { await BrowsePixelService.shared.setGridPrefetchWindow(ahead: ahead, keep: keep) }
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
