import XCTest
@testable import Lumina

/// Falsifier for the silent-SLA-inheritance defect (E2 instruments).
///
/// `LatencyMetrics.sla(for:)` ended in a catch-all that handed `navigationSLAms` — 50 ms —
/// to every key no rule matched. That is defensible for a navigation key and wrong by 6×
/// for a per-frame key, whose budget at a pinned 120 Hz is 8.33 ms. Worse, nothing in the
/// output said which budget had been applied, so a frame key would have breached silently.
///
/// These tests pin both halves: the four declared keys now carry argued budgets, and the
/// fallback still behaves exactly as it always did for everything else. The second half
/// matters as much as the first — it is the evidence that adding the mapping moved no
/// existing consumer.
final class RenderInstrumentSLATests: XCTestCase {

    override func tearDown() {
        LatencyMetrics.resetSession()
        super.tearDown()
    }

    // MARK: - The four declared keys

    func testEachRenderKeyPinsItsDeclaredSLA() {
        XCTAssertEqual(
            LatencyMetrics.sla(for: P0RenderInstruments.Key.scrollFrame),
            LatencyMetrics.frameBudget120HzMs,
            "p0.scroll.frame is judged against one 120 Hz display interval, not the 50 ms navigation SLA"
        )
        XCTAssertEqual(
            LatencyMetrics.sla(for: P0RenderInstruments.Key.keyTravel),
            LatencyMetrics.gestureToPixelsSLAms
        )
        XCTAssertEqual(
            LatencyMetrics.sla(for: P0RenderInstruments.Key.keyMark),
            LatencyMetrics.gestureToPixelsSLAms
        )
        XCTAssertEqual(
            LatencyMetrics.sla(for: P0RenderInstruments.Key.zoomGesture),
            LatencyMetrics.gestureToPixelsSLAms
        )
    }

    /// The defect, stated as a number: the frame key's declared budget and what it would
    /// have silently inherited are not the same, and the gap is ~6×.
    func testFrameBudgetIsNotTheInheritedNavigationSLA() {
        let declared = LatencyMetrics.sla(for: P0RenderInstruments.Key.scrollFrame)
        XCTAssertNotEqual(declared, LatencyMetrics.navigationSLAms)
        XCTAssertLessThan(declared, LatencyMetrics.navigationSLAms)
        XCTAssertEqual(LatencyMetrics.navigationSLAms / declared, 6.0, accuracy: 0.01)
    }

    func testDeclaredKeysAreExactlyTheFourRenderKeys() {
        XCTAssertEqual(LatencyMetrics.declaredSLAKeys, P0RenderInstruments.Key.all.sorted())
    }

    // MARK: - The fallback, unchanged

    /// Documents the historical behaviour deliberately left in place: a key outside the
    /// mapping still inherits `navigationSLAms` without saying so. This is not an
    /// endorsement — it is the boundary of what the mapping changed.
    func testUnmappedKeyStillSilentlyInheritsNavigationSLA() {
        XCTAssertEqual(LatencyMetrics.sla(for: "totally.unknown.key"), LatencyMetrics.navigationSLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "p0.something.new"), LatencyMetrics.navigationSLAms)
    }

    /// The reason the mapping matches exact keys instead of the `p0.` prefix: these already
    /// existed and must keep the budget they had.
    func testExistingP0KeysKeepTheirHistoricalBudget() {
        for key in ["p0.edit.slider_to_pixels", "p0.edit.nav_prewarm_count", "p0.visible_cell_cache"] {
            XCTAssertEqual(
                LatencyMetrics.sla(for: key),
                LatencyMetrics.navigationSLAms,
                "\(key) predates the mapping and must not be re-budgeted by it"
            )
        }
    }

    func testHistoricalPrefixRulesAreUntouched() {
        XCTAssertEqual(LatencyMetrics.sla(for: "spine.input_to_photon"), LatencyMetrics.navigationSLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "navigation.select"), LatencyMetrics.navigationSLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "spine.paint_commit"), LatencyMetrics.navigationSLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "spine.fidelity.x"), LatencyMetrics.fidelitySLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "develop.render"), LatencyMetrics.developScrubSLAms)
        XCTAssertEqual(LatencyMetrics.sla(for: "cache.hit"), LatencyMetrics.cacheHitSLAms)
    }

    // MARK: - Capture compatibility

    /// The keys must be promotable out of the 512-ring, or a 60 s glide reports its tail —
    /// the exact bug E1 repaired. Pins that the new keys inherit that repair.
    func testRenderKeysAreCaptureModeCompatible() {
        for key in P0RenderInstruments.Key.all {
            LatencyMetrics.clearCapture(key: key)
            LatencyMetrics.beginCapture(key: key)
            XCTAssertTrue(LatencyMetrics.isCapturing(key))
        }

        let key = P0RenderInstruments.Key.scrollFrame
        for i in 0..<600 { LatencyMetrics.record(key, milliseconds: Double(i)) }

        let window = LatencyMetrics.window(for: key)
        XCTAssertEqual(window?.sampleCount, 600, "capture keeps every sample; the ring would hold 512")
        XCTAssertEqual(window?.coverage, .fullRun)
        XCTAssertEqual(window?.mode, .capture)

        let reading = LatencyMetrics.reading(for: key)
        XCTAssertNotNil(reading?.window, "a render-key row cannot be emitted without its window")
    }

    /// Without capture, a long run silently reports its tail — the property that makes
    /// capture mode mandatory for the 60 s glide rather than optional.
    func testRenderKeyWithoutCaptureStillReportsTail() {
        let key = P0RenderInstruments.Key.keyTravel
        LatencyMetrics.clearCapture(key: key)
        for i in 0..<600 { LatencyMetrics.record(key, milliseconds: Double(i)) }

        let window = LatencyMetrics.window(for: key)
        XCTAssertEqual(window?.sampleCount, 512)
        XCTAssertEqual(window?.totalRecorded, 600)
        XCTAssertEqual(window?.coverage, .tail)
        XCTAssertEqual(window?.mode, .ring)
    }

    // MARK: - Default-off

    /// An ordinary run must be unchanged: no display link, no samples, no behaviour.
    func testInstrumentsAreOffUntilEnabled() {
        MainActor.assumeIsolated {
            let instruments = P0RenderInstruments.shared
            instruments.disable()
            XCTAssertFalse(instruments.isEnabled)

            LatencyMetrics.resetSession()
            instruments.noteScrollActivity()
            instruments.arm(P0RenderInstruments.Key.keyMark, at: 1.0)
            XCTAssertFalse(
                LatencyMetrics.recordedKeys().contains(P0RenderInstruments.Key.keyMark),
                "arming while disabled must record nothing"
            )
        }
    }
}

/// Pins the frame-sampling rules themselves, driven through `presentFrame(at:)` so the logic
/// is checked without a display. What a real display link adds beyond this is the cadence —
/// that part is only observable live, and E2's Window 1 is where it gets measured.
final class RenderInstrumentSamplingTests: XCTestCase {

    private func fresh() -> P0RenderInstruments {
        let instruments = P0RenderInstruments.shared
        instruments.disable()
        LatencyMetrics.resetSession()
        for key in P0RenderInstruments.Key.all { LatencyMetrics.clearCapture(key: key) }
        instruments.enable(capture: false)
        instruments.resetFrameHistoryForTesting()
        return instruments
    }

    override func tearDown() {
        MainActor.assumeIsolated { P0RenderInstruments.shared.disable() }
        LatencyMetrics.resetSession()
        super.tearDown()
    }

    /// Frames presented while the sheet is scrolling become samples; the interval recorded is
    /// the gap between presented frames, which is what a dropped frame shows up in.
    func testScrollFramesSampleTheInterval() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            var t: CFTimeInterval = 100
            instruments.presentFrame(at: t)          // first tick: no previous, no sample
            for _ in 0..<4 {
                instruments.noteScrollActivity(at: t)
                t += 0.008
                instruments.presentFrame(at: t)
            }
            let samples = LatencyMetrics.capturedSamples(for: P0RenderInstruments.Key.scrollFrame)
            let count = samples.isEmpty
                ? LatencyMetrics.window(for: P0RenderInstruments.Key.scrollFrame)?.sampleCount
                : samples.count
            XCTAssertEqual(count, 4)
            XCTAssertEqual(LatencyMetrics.p50(for: P0RenderInstruments.Key.scrollFrame) ?? 0, 8.0, accuracy: 0.001)
        }
    }

    /// A long frame is reported as a long frame. This is the property that makes the key worth
    /// having: a layout timer would have reported the same short work either way.
    func testDroppedFrameIsVisibleInTheSample() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            instruments.noteScrollActivity(at: 10.0)
            instruments.presentFrame(at: 10.0)
            instruments.noteScrollActivity(at: 10.045)
            instruments.presentFrame(at: 10.050)   // 50 ms — six missed 120 Hz frames
            let p99 = LatencyMetrics.p99(for: P0RenderInstruments.Key.scrollFrame) ?? 0
            XCTAssertEqual(p99, 50.0, accuracy: 0.001)
            XCTAssertGreaterThan(p99, LatencyMetrics.sla(for: P0RenderInstruments.Key.scrollFrame))
        }
    }

    /// Idle frames are not glide frames. Without this gate the key would average in the still
    /// table and understate the glide.
    func testIdleFramesAreNotSampled() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            instruments.presentFrame(at: 200.0)
            instruments.presentFrame(at: 200.008)   // never scrolled
            instruments.presentFrame(at: 200.016)
            XCTAssertNil(LatencyMetrics.window(for: P0RenderInstruments.Key.scrollFrame))
        }
    }

    func testScrollSamplingStopsAfterTheIdleTimeout() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            instruments.noteScrollActivity(at: 300.0)
            instruments.presentFrame(at: 300.0)
            instruments.presentFrame(at: 300.008)   // still inside the idle window
            let during = LatencyMetrics.window(for: P0RenderInstruments.Key.scrollFrame)?.sampleCount ?? 0

            instruments.presentFrame(at: 300.0 + P0RenderInstruments.scrollIdleTimeoutSeconds + 0.010)
            let after = LatencyMetrics.window(for: P0RenderInstruments.Key.scrollFrame)?.sampleCount ?? 0
            XCTAssertEqual(during, after, "a frame past the idle timeout is not a glide frame")
        }
    }

    /// An armed event resolves on the next presented frame, and the number spans from the
    /// event's own timestamp — queueing delay included, not hidden.
    func testArmedEventResolvesOnNextFrameFromEventTime() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            instruments.arm(P0RenderInstruments.Key.keyMark, at: 500.000)
            instruments.presentFrame(at: 500.012)
            XCTAssertEqual(LatencyMetrics.p50(for: P0RenderInstruments.Key.keyMark) ?? 0, 12.0, accuracy: 0.001)

            // Resolved once, not re-reported on later frames.
            instruments.presentFrame(at: 500.020)
            XCTAssertEqual(LatencyMetrics.window(for: P0RenderInstruments.Key.keyMark)?.sampleCount, 1)
        }
    }

    /// During autorepeat travel the honest number is the age of the oldest input still waiting
    /// on a frame — not the freshest, which would flatter the engine.
    func testAutorepeatKeepsTheOldestUnresolvedStamp() {
        MainActor.assumeIsolated {
            let instruments = fresh()
            instruments.arm(P0RenderInstruments.Key.keyTravel, at: 600.000)
            instruments.arm(P0RenderInstruments.Key.keyTravel, at: 600.008)
            instruments.arm(P0RenderInstruments.Key.keyTravel, at: 600.016)
            instruments.presentFrame(at: 600.020)
            XCTAssertEqual(
                LatencyMetrics.p50(for: P0RenderInstruments.Key.keyTravel) ?? 0, 20.0, accuracy: 0.001,
                "the oldest waiting input defines the latency, not the newest"
            )
        }
    }

    func testDisabledInstrumentsRecordNothing() {
        MainActor.assumeIsolated {
            let instruments = P0RenderInstruments.shared
            instruments.disable()
            LatencyMetrics.resetSession()
            instruments.noteScrollActivity(at: 1.0)
            instruments.arm(P0RenderInstruments.Key.keyTravel, at: 1.0)
            instruments.presentFrame(at: 2.0)
            XCTAssertTrue(LatencyMetrics.recordedKeys().isEmpty)
        }
    }
}
