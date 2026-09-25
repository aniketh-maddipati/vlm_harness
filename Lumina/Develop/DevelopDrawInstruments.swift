import Foundation

/// Draw-path instruments for the develop canvas, attributed by RAW-stage backing.
///
/// ## Why this exists beside `p0.edit.draw_ms`
///
/// `LatencyMetrics.editDrawKey` already brackets `DevelopMetalView.draw(in:)` from
/// just before the `startTask` pair to the command buffer's completion handler, so
/// the settled demosaic **is** inside that number. What it cannot do is separate the
/// two populations it samples:
///
/// - draws of a **materialized** RAW stage (an `MTLTexture`; measured 3.5–4.5 ms), and
/// - draws of a **lazy** RAW stage (`CIRAWFilter.outputImage`; measured 79.5–91.0 ms
///   after any pan / zoom / resize, and 288.7 ms on the first draw)
///
/// into one key. Interactive draws vastly outnumber settled ones during a scrub, so
/// the p50 of `p0.edit.draw_ms` reports the cheap population and the expensive one
/// hides in a tail that also contains ordinary GPU jitter. A W1 before/after cannot
/// be argued from a distribution that mixes the thing being changed with the thing
/// being left alone.
///
/// Evidence: `~/LuminaEvidence/render-latency-research-20260924/04-lazy-redraw.txt`.
/// **Stated bound on that evidence:** it was produced by a standalone bench using the
/// blocking `CIContext.render(toBitmap:)`, not by this app's asynchronous
/// `startTask` + command-buffer path. The magnitudes are the reason these keys exist;
/// they are not this app's numbers. These keys produce this app's numbers.
///
/// ## The four keys
///
/// Each draw of an attributed surface produces **two** samples — one walk, one total —
/// into the pair of keys matching its backing:
///
/// - `draw_walk_*_ms` — wall time of the `startTask(toClear:)` + `startTask(toRender:to:)`
///   pair alone. This is Core Image's graph analysis, kernel selection and command
///   encoding, and it runs **on the thread that calls `draw(in:)`** — the main thread,
///   because `MTKView` is driven by `enableSetNeedsDisplay`. A large walk is therefore
///   a stalled main thread, not merely a busy GPU.
/// - `draw_*_ms` — the same interval extended to GPU completion. Directly comparable to
///   `p0.edit.draw_ms`, except attributed.
///
/// Subtracting walk from total gives GPU time without a second clock. That subtraction
/// is the thing that distinguishes "the graph was re-walked" from "the GPU was busy",
/// and it is **UNMEASURED today** — no run of this instrument exists yet.
///
/// ## How a W1 delta gets proven from these
///
/// W1 materializes the authoritative stage, after which settled draws stop producing
/// `lazyGraph` samples at all — so the *same* key cannot be compared across the change.
/// The comparison is:
///
/// - **before:** `draw_lazy_ms` (settled pan/zoom) vs `draw_materialized_ms` (interactive)
///   **in the same run**. Same host, same instrument, same session: the gap between them
///   is the cost W1 removes, with the materialized key acting as the control.
/// - **after:** settled pan/zoom lands in `draw_materialized_ms`, and `draw_lazy_ms`
///   should have no samples. The materialized key's own distribution must not have
///   regressed against its before value — that is what rules out "the host got faster".
///
/// A reviewer checking the arithmetic needs the sample counts: every key carries its
/// `LatencyMetrics.Window`, and the number of draws that were *not* attributed is
/// `window(for: p0.edit.draw_ms).totalRecorded` minus the two attributed counts.
///
/// ## Off by default
///
/// Nothing here records unless the process was launched with `--p0-instruments`, the
/// same gate `P0RenderInstruments` and `DevelopPresentationMeasurement` use. An
/// ordinary run pays one `Bool` read per draw and renders identical pixels: this
/// instrument observes work the app already does and never forces any.
nonisolated enum DevelopDrawInstruments {

    enum Key {
        /// CPU walk/encode of a draw whose RAW stage is a lazy `CIRAWFilter` graph.
        static let drawWalkLazy = "p0.develop.draw_walk_lazy_ms"
        /// CPU walk/encode of a draw whose RAW stage is a materialized texture.
        static let drawWalkMaterialized = "p0.develop.draw_walk_materialized_ms"
        /// Walk + GPU completion for a lazy-stage draw.
        static let drawLazy = "p0.develop.draw_lazy_ms"
        /// Walk + GPU completion for a materialized-stage draw.
        static let drawMaterialized = "p0.develop.draw_materialized_ms"

        static let all: [String] = [drawLazy, drawMaterialized, drawWalkLazy, drawWalkMaterialized]
    }

    /// The launch gate. `static let` so the argument scan happens once per process.
    static let launchRequested = ProcessInfo.processInfo.arguments.contains("--p0-instruments")

    /// Test seam only. Never set outside tests; a real run reads `launchRequested`.
    nonisolated(unsafe) private static var forcedEnabled: Bool?

    static var isEnabled: Bool { forcedEnabled ?? launchRequested }

    static func setEnabledForTesting(_ enabled: Bool?) { forcedEnabled = enabled }

    // MARK: - Key selection

    /// The walk key for a backing, or `nil` when the surface is unattributed.
    ///
    /// `nil` is the sampling rule, not a failure: a proxy / ImageIO-fallback / browse
    /// surface never passed through the RAW stage, so folding its draws into either
    /// distribution would put non-RAW work in a number about RAW work.
    static func walkKey(for backing: DevelopRawStageBacking) -> String? {
        switch backing {
        case .lazyGraph: return Key.drawWalkLazy
        case .materialized: return Key.drawWalkMaterialized
        case .unattributed: return nil
        }
    }

    /// The walk-plus-GPU-completion key for a backing, or `nil` when unattributed.
    static func drawKey(for backing: DevelopRawStageBacking) -> String? {
        switch backing {
        case .lazyGraph: return Key.drawLazy
        case .materialized: return Key.drawMaterialized
        case .unattributed: return nil
        }
    }

    // MARK: - Recording

    /// Record the CPU cost of the Core Image `startTask` pair for one draw.
    static func recordWalk(milliseconds: Double, backing: DevelopRawStageBacking) {
        record(key: walkKey(for: backing), milliseconds: milliseconds)
    }

    /// Record one draw from just before the `startTask` pair to GPU completion.
    static func recordDraw(milliseconds: Double, backing: DevelopRawStageBacking) {
        record(key: drawKey(for: backing), milliseconds: milliseconds)
    }

    private static func record(key: String?, milliseconds: Double) {
        guard isEnabled, let key else { return }
        // Capture mode, for the same reason the E1 repair introduced it: a pan is
        // thousands of draws and the 512-sample ring would report only its tail —
        // which is where the first, most expensive draws have already aged out.
        LatencyMetrics.beginCapture(key: key)
        LatencyMetrics.record(key, milliseconds: milliseconds)
    }
}
