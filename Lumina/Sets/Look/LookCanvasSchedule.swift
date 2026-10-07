import Foundation

/// The Edit canvas's scheduling rules (roadmap addendum §3–4), as plain state with no display,
/// Metal or timer behind it, so `LookCanvasTests` can run them on any machine:
///
/// - **Two tiers.** While a slider is dragged the look renders from `small` (a quarter of the
///   canvas, linear); on drag end, on a keystroke, or once the thumb has been still for `idleMs`
///   (during a drag: `restAfterMs`, which follows the drag's own cadence), the newest look
///   renders from `base` at full quality (a *rest* render). Histogram and clipping are computed
///   on rest renders only.
/// - **Latest wins.** Sliders emit continuously; only the newest look per photo is kept. A render
///   in flight is never queued behind: the next `tick` starts the newest value, at most once per
///   display refresh.
/// - **Sequence numbers.** Every render carries one; the overlay presents a finished render only
///   if it is newer than the last presented.
///
/// `LookCanvasController` owns one of these per canvas and calls `tick` from its display link.
nonisolated struct LookCanvasSchedule: Sendable {
    enum Tier: String, Sendable, Codable { case small, base }

    /// The visible part of the photo when the view is zoomed, as fractions of the frame (x, y
    /// from the top-left). Nil = the whole photo.
    struct ROI: Equatable, Sendable, Codable {
        var x: Double, y: Double, w: Double, h: Double
        var isWhole: Bool { x <= 0 && y <= 0 && w >= 1 && h >= 1 }
        /// Exactly the photo: nothing to place, the canvas fits it. A region reaching beyond the
        /// photo (the page zoomed out) is whole and still has a place of its own.
        var isFit: Bool { x == 0 && y == 0 && w == 1 && h == 1 }
    }

    /// One render to start now.
    struct Request: Equatable, Sendable {
        let look: String
        /// The render's own sequence number: presented only if newer than the last presented.
        let seq: Int
        /// The schedule's own count of the look this render shows (latency is measured on it).
        let lookSeq: Int
        /// The page's `seq` for that look (`luminaPresented(seq)` names it).
        let pageSeq: Int
        let tier: Tier
        /// Only the visible region, during a drag on a zoomed view.
        let roi: ROI?
        /// Rest renders compute the histogram and the clipping overlay too.
        var stats: Bool { tier == .base }
        /// When the look arrived, on the schedule's clock (ms).
        let submittedAt: Double
        /// When the page emitted the look, on the page's clock (ms); 0 when unknown.
        let pageAt: Double
    }

    struct Stats: Codable, Equatable, Sendable {
        var submitted = 0
        var started = 0
        var small = 0
        var base = 0
        var coalesced = 0       // looks that were replaced before they rendered
        var stale = 0           // finished renders an older seq: not presented
        var presented = 0
    }

    /// A full-quality render is owed this long after the thumb stops moving.
    var idleMs: Double = 120

    /// During a drag the thumb counts as still only after 1.5 × the drag's own cadence, when that
    /// is longer than `idleMs`: a slider that steps in whole numbers delivers looks 100 to 117 ms
    /// apart on a slow drag, and one late step must not put a rest render (its histogram, and a
    /// frame the next look waits behind) in the middle of it.
    static let cadenceFactor = 1.5
    /// … and never longer than this many `idleMs`: looks further apart than that are pauses.
    static let maxIdleFactor = 3.0

    /// The gap between the last two looks of this drag (ms); a gap long enough to rest was a
    /// pause, not the cadence, and leaves it as it was. Nil until the drag's second look.
    private(set) var cadence: Double?
    private var dragSubmitAt: Double?

    /// How long the newest look must have stood before it is owed a rest render: `idleMs`, or
    /// while dragging `max(idleMs, 1.5 × cadence)` (at most 3 × `idleMs`).
    var restAfterMs: Double {
        guard dragging, let c = cadence else { return idleMs }
        return min(max(idleMs, Self.cadenceFactor * c), Self.maxIdleFactor * idleMs)
    }

    private(set) var dragging = false
    private(set) var latest: (look: String, seq: Int, at: Double, roi: ROI?, pageSeq: Int, pageAt: Double)?
    private(set) var inFlight: Int?
    private(set) var presented = Int.min
    private(set) var presentedTier: Tier?
    private(set) var presentedLook: String?
    private var lastStarted: (lookSeq: Int, tier: Tier)?
    private var restWanted = false
    private var renderSeq = 0
    private var lookSeq = 0
    private(set) var stats = Stats()

    init(idleMs: Double = 120) { self.idleMs = idleMs }

    // MARK: Inputs (from the page, through plumbing)

    /// A new look value. Returns the page-facing sequence number it was given.
    @discardableResult
    mutating func submit(_ look: String, at now: Double, roi: ROI? = nil, pageSeq: Int = 0, pageAt: Double = 0) -> Int {
        lookSeq += 1
        if dragging {
            if let p = dragSubmitAt, now >= p, now - p < restAfterMs { cadence = now - p }
            dragSubmitAt = now
        }
        // The previous newest never started: it is replaced, not rendered.
        if let l = latest, l.seq > (lastStarted?.lookSeq ?? Int.min) { stats.coalesced += 1 }
        latest = (look, lookSeq, now, roi, pageSeq, pageAt)
        stats.submitted += 1
        return lookSeq
    }

    mutating func dragStart(at now: Double) { dragging = true; restWanted = false; cadence = nil; dragSubmitAt = nil }

    /// The thumb was let go: the newest look renders from `base` next.
    mutating func dragEnd(at now: Double) { dragging = false; restWanted = true }

    /// A key changed the value: a full-quality render now, whatever the drag state.
    mutating func keystroke(_ look: String, at now: Double, roi: ROI? = nil, pageSeq: Int = 0, pageAt: Double = 0) -> Int {
        let s = submit(look, at: now, roi: roi, pageSeq: pageSeq, pageAt: pageAt)
        restWanted = true
        return s
    }

    // MARK: The display link

    /// Called once per display refresh. Nil when nothing needs rendering or a render is in flight.
    /// A newer look is waiting that no render has started yet.
    var pending: Bool {
        guard let l = latest else { return false }
        return lastStarted.map { l.seq > $0.lookSeq } ?? true
    }

    mutating func tick(at now: Double) -> Request? {
        guard inFlight == nil, let l = latest else { return nil }
        let unstarted = lastStarted.map { l.seq > $0.lookSeq } ?? true
        let tier: Tier
        if unstarted {
            tier = (dragging && !restWanted) ? .small : .base
        } else {
            // The newest look is on screen (or in the pipe) from `small`: owe it a rest render
            // when the drag ends, a key asks, or the thumb has been still for restAfterMs (idleMs,
            // longer on a drag whose looks come further apart than that).
            guard lastStarted?.tier == .small, restWanted || !dragging || now - l.at >= restAfterMs else { return nil }
            tier = .base
        }
        restWanted = false
        renderSeq += 1
        inFlight = renderSeq
        lastStarted = (l.seq, tier)
        stats.started += 1
        if tier == .small { stats.small += 1 } else { stats.base += 1 }
        return Request(look: l.look, seq: renderSeq, lookSeq: l.seq, pageSeq: l.pageSeq, tier: tier, roi: tier == .small ? l.roi : nil, submittedAt: l.at, pageAt: l.pageAt)
    }

    /// A render finished. True when the overlay should present it (it is newer than the last presented).
    mutating func finished(_ r: Request) -> Bool {
        if inFlight == r.seq { inFlight = nil }
        guard r.seq > presented else { stats.stale += 1; return false }
        presented = r.seq
        presentedTier = r.tier
        presentedLook = r.look
        stats.presented += 1
        return true
    }

    mutating func failed(_ r: Request) {
        if inFlight == r.seq { inFlight = nil }
        // Don't retry the same value forever: treat it as started and wait for the next change.
    }

    /// Another photo, or Edit closed: nothing pending, nothing presented.
    mutating func reset() {
        dragging = false; latest = nil; inFlight = nil; presented = Int.min; presentedTier = nil; presentedLook = nil
        lastStarted = nil; restWanted = false; cadence = nil; dragSubmitAt = nil
    }

    /// A full-quality render is still owed (the last one shown came from `small`).
    var restPending: Bool {
        guard let l = latest else { return false }
        if let s = lastStarted, l.seq > s.lookSeq { return true }
        return lastStarted?.tier == .small
    }
}
