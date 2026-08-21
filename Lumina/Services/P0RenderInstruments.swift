import AppKit
import QuartzCore

/// Display-link-derived render instruments for the P0 contact sheet.
///
/// Four keys, all recorded through `LatencyMetrics`, so capture mode applies to them
/// unchanged (`LatencyMetrics.beginCapture(key:)`) and every percentile they feed
/// carries its `Window` like any other key.
///
/// - `p0.scroll.frame` — interval between presented frames while the sheet is scrolling.
///   Display-link-derived: the cadence the display actually ran at, **not** how long a
///   layout pass took. A layout timer cannot see a dropped frame; this can.
/// - `p0.key.travel`   — arrow-key event → the first frame presented after the focus move.
/// - `p0.key.mark`     — P/X event → the first frame presented after the mark.
/// - `p0.zoom.gesture` — pinch or `+`/`-` → the first frame presented after the density change.
///
/// ## Stated bound
///
/// The three event keys are quantised by one display interval. The instrument resolves on
/// the first display-link callback after the state mutation returns; it cannot tell whether
/// that frame or the next one carried the change to glass. At a pinned 120 Hz that is up to
/// **8.33 ms** of over- or under-statement per sample. The bias belongs to the instrument,
/// not to an engine, so it is identical on both sides of an A/B and cancels in a delta.
/// Absolute values carry it — say so wherever they are quoted.
///
/// `NSEvent.timestamp` and `CADisplayLink.timestamp` share the mach absolute time base that
/// `CACurrentMediaTime()` reads, so the subtraction below is valid without conversion. The
/// event stamp is taken when the window server received the input, so queueing delay is
/// inside the number rather than hidden from it.
///
/// ## Off by default
///
/// The display link is created only while instruments are enabled, so an ordinary run pays
/// nothing and behaves identically — no timer, no wake-ups, no extra retain on the view.
/// Enable with the `--p0-instruments` launch argument or `P0RenderInstruments.shared.enable()`.
///
/// This type records; it never interprets. `P0KeyRoutingModifier` remains the sole owner of
/// key routing, and every `arm` call below sits *after* the state mutation it times.
@MainActor
final class P0RenderInstruments {
    static let shared = P0RenderInstruments()

    enum Key {
        static let scrollFrame = "p0.scroll.frame"
        static let keyTravel = "p0.key.travel"
        static let keyMark = "p0.key.mark"
        static let zoomGesture = "p0.zoom.gesture"

        static let all: [String] = [scrollFrame, keyTravel, keyMark, zoomGesture]
    }

    /// How long after the last bounds change the sheet still counts as scrolling.
    ///
    /// PROPOSED — an invented constant, not a token. It scopes which display-link ticks
    /// become `p0.scroll.frame` samples: without it the key would also sample idle frames
    /// and understate the glide. Promote to a token only if it survives ratification.
    static let scrollIdleTimeoutSeconds: CFTimeInterval = 0.100

    private(set) var isEnabled = false

    private var link: CADisplayLink?
    private weak var host: NSView?

    private var lastFrameTimestamp: CFTimeInterval?
    private var lastScrollActivity: CFTimeInterval?
    /// Event-time stamps awaiting the frame that shows their effect.
    private var pending: [String: CFTimeInterval] = [:]

    private init() {}

    /// True when the process was launched asking for instrumentation.
    static var launchRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--p0-instruments")
    }

    // MARK: - Lifecycle

    /// Start instrumenting. `capture` promotes all four keys out of the 512-sample ring so a
    /// 60 s glide reports its whole run rather than its tail.
    func enable(capture: Bool = true) {
        guard !isEnabled else { return }
        isEnabled = true
        if capture {
            for key in Key.all { LatencyMetrics.beginCapture(key: key) }
        }
        startLink()
    }

    func disable() {
        isEnabled = false
        stopLink()
        pending.removeAll()
        lastFrameTimestamp = nil
        lastScrollActivity = nil
    }

    /// Hand the instruments the view whose display cadence defines a frame. Called by the
    /// contact sheet; a no-op while disabled.
    func attach(to view: NSView) {
        host = view
        startLink()
    }

    func detach() {
        stopLink()
        host = nil
    }

    private func startLink() {
        guard isEnabled, link == nil, let host, host.window != nil else { return }
        let displayLink = host.displayLink(target: self, selector: #selector(frameTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    // MARK: - Recording

    /// Note that the sheet's visible bounds moved. Cheap enough to sit on the scroll path.
    ///
    /// `at` shares the display link's time base by default. It is a parameter so that the
    /// activity clock and the frame clock can be driven from one source in a test — mixing
    /// an injected frame time with a real activity time compares two different clocks and
    /// silently defeats the idle gate.
    func noteScrollActivity(at time: CFTimeInterval = CACurrentMediaTime()) {
        guard isEnabled else { return }
        lastScrollActivity = time
    }

    /// Stamp an event whose effect the next presented frame will carry.
    ///
    /// Call **after** the state mutation, so the next display-link callback is the first
    /// opportunity for the change to reach the screen.
    func arm(_ key: String, event: NSEvent) {
        arm(key, at: event.timestamp)
    }

    func arm(_ key: String, at eventTimestamp: CFTimeInterval) {
        guard isEnabled else { return }
        // Keep the earliest unresolved stamp: during autorepeat travel the honest number is
        // the age of the input still waiting on a frame, not the freshest one.
        if let existing = pending[key], existing <= eventTimestamp { return }
        pending[key] = eventTimestamp
    }

    @objc private func frameTick(_ sender: CADisplayLink) {
        presentFrame(at: sender.timestamp)
    }

    /// The body of a display-link callback, separated from the link so the sampling rules —
    /// scroll gating, interval arithmetic, pending resolution — are testable without a real
    /// display. The link supplies `timestamp`; nothing else here reads the clock.
    func presentFrame(at now: CFTimeInterval) {
        if let last = lastFrameTimestamp,
           let activity = lastScrollActivity,
           now - activity <= Self.scrollIdleTimeoutSeconds {
            LatencyMetrics.record(Key.scrollFrame, milliseconds: (now - last) * 1000)
        }
        lastFrameTimestamp = now

        guard !pending.isEmpty else { return }
        for (key, armedAt) in pending {
            LatencyMetrics.record(key, milliseconds: max(0, now - armedAt) * 1000)
        }
        pending.removeAll()
    }

    /// Test seam: forget frame history without tearing down the link.
    func resetFrameHistoryForTesting() {
        lastFrameTimestamp = nil
        lastScrollActivity = nil
        pending.removeAll()
    }
}
