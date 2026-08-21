import XCTest
@testable import Lumina

/// Falsifier for the truncated-window bug (E2-preflight F2).
///
/// `LatencyMetrics` kept 512 samples per key and dropped the oldest on overflow. A 60 s
/// @ 120 Hz glide produces ~7,200 `scroll.frame` samples, so any percentile read off that
/// ring described the *last 512 frames* — warm-up and early stutter, exactly where a new
/// engine differs, had already aged out.
///
/// These tests pin both truths side by side: the ring cannot see early stutter, capture
/// mode can. The difference between the two assertions IS the bug being fixed.
final class LatencyMetricsWindowTests: XCTestCase {

    private func freshKey(_ name: String) -> String {
        let key = "test.\(name).\(UUID().uuidString)"
        LatencyMetrics.clearCapture(key: key)
        return key
    }

    override func tearDown() {
        LatencyMetrics.resetSession()
        super.tearDown()
    }

    // MARK: - The falsifier

    /// 10,000 samples; the first 150 are a 500 ms warm-up burst, the rest are 5 ms.
    ///
    /// Ring mode  → p99 ≈ 5 ms. The burst aged out. This assertion documents the OLD truth.
    /// Capture mode → p99 = 500 ms. The burst is in the number, where it belongs.
    func testWarmupBurstIsInvisibleToRingAndVisibleToCapture() {
        let burst = 150
        let total = 10_000

        // --- Ring mode (default behaviour, unchanged) ---
        let ringKey = freshKey("ring")
        for i in 0..<total {
            LatencyMetrics.record(ringKey, milliseconds: i < burst ? 500.0 : 5.0)
        }

        let ringP99 = LatencyMetrics.p99(for: ringKey)
        XCTAssertNotNil(ringP99)
        XCTAssertEqual(ringP99!, 5.0, accuracy: 0.001,
                       "OLD TRUTH: the 512-sample ring cannot see a warm-up burst 10,000 frames back.")

        let ringWindow = LatencyMetrics.window(for: ringKey)
        XCTAssertEqual(ringWindow?.mode, .ring)
        XCTAssertEqual(ringWindow?.sampleCount, 512)
        XCTAssertEqual(ringWindow?.totalRecorded, total)
        XCTAssertEqual(ringWindow?.coverage, .tail)
        XCTAssertEqual(ringWindow?.droppedCount, total - 512)
        XCTAssertEqual(ringWindow?.declaration, "n=512, tail (of 10000 recorded)",
                       "A tail number must say so out loud.")

        // --- Capture mode (opt-in, unbounded) ---
        let captureKey = freshKey("capture")
        LatencyMetrics.beginCapture(key: captureKey)
        for i in 0..<total {
            LatencyMetrics.record(captureKey, milliseconds: i < burst ? 500.0 : 5.0)
        }

        let captureP99 = LatencyMetrics.p99(for: captureKey)
        XCTAssertNotNil(captureP99)
        XCTAssertEqual(captureP99!, 500.0, accuracy: 0.001,
                       "NEW TRUTH: capture mode's p99 covers the whole run, burst included.")

        let captureWindow = LatencyMetrics.window(for: captureKey)
        XCTAssertEqual(captureWindow?.mode, .capture)
        XCTAssertEqual(captureWindow?.sampleCount, total)
        XCTAssertEqual(captureWindow?.totalRecorded, total)
        XCTAssertEqual(captureWindow?.coverage, .fullRun)
        XCTAssertEqual(captureWindow?.droppedCount, 0)
        XCTAssertEqual(captureWindow?.declaration, "n=10000, full run")

        // The diff between the two assertions is the bug.
        XCTAssertEqual(captureP99! - ringP99!, 495.0, accuracy: 0.001,
                       "495 ms of early stutter was invisible to the old instrument.")

        LatencyMetrics.clearCapture(key: captureKey)
    }

    /// The single-spike case, recorded because its arithmetic is counter-intuitive.
    ///
    /// One 500 ms spike at sample #100 of 10,000 sits at p99.99, NOT p99 — so p99 reads
    /// 5 ms in *both* modes. What separates them is the maximum: the ring's max is 5 ms
    /// because the spike aged out; capture's max is the spike. A falsifier that asserted
    /// "capture p99 sees a single spike" would fail for arithmetic reasons, not because
    /// the instrument was broken. p99 only moves once ≥101 of 10,000 samples are slow.
    func testSingleSpikeMovesTheMaximumNotP99() {
        let total = 10_000
        let spikeIndex = 100

        let ringKey = freshKey("ring.single")
        for i in 0..<total {
            LatencyMetrics.record(ringKey, milliseconds: i == spikeIndex ? 500.0 : 5.0)
        }

        let captureKey = freshKey("capture.single")
        LatencyMetrics.beginCapture(key: captureKey)
        for i in 0..<total {
            LatencyMetrics.record(captureKey, milliseconds: i == spikeIndex ? 500.0 : 5.0)
        }

        // p99 is blind to a lone spike in both modes — arithmetic, not a defect.
        XCTAssertEqual(LatencyMetrics.p99(for: ringKey)!, 5.0, accuracy: 0.001)
        XCTAssertEqual(LatencyMetrics.p99(for: captureKey)!, 5.0, accuracy: 0.001)

        // The maximum is where the modes diverge.
        XCTAssertEqual(LatencyMetrics.percentile(ringKey, 1.0)!, 5.0, accuracy: 0.001,
                       "OLD TRUTH: the spike aged out of the ring entirely.")
        XCTAssertEqual(LatencyMetrics.percentile(captureKey, 1.0)!, 500.0, accuracy: 0.001,
                       "NEW TRUTH: capture mode still holds the spike.")

        LatencyMetrics.clearCapture(key: captureKey)
    }

    // MARK: - Default behaviour is unchanged

    /// `SpeedContractHUD` reads `p95(for:)` and `sampleCount(for:)` live. A key that never
    /// calls `beginCapture` must behave exactly as before.
    func testUncapturedKeyKeepsRingBehaviour() {
        let key = freshKey("hud")
        for _ in 0..<2_000 { LatencyMetrics.record(key, milliseconds: 7.0) }

        XCTAssertEqual(LatencyMetrics.sampleCount(for: key), 512,
                       "sampleCount still reports the ring, as the HUD expects.")
        XCTAssertFalse(LatencyMetrics.isCapturing(key))
        XCTAssertEqual(LatencyMetrics.window(for: key)?.mode, .ring)
        XCTAssertTrue(LatencyMetrics.capturedSamples(for: key).isEmpty)
    }

    /// A short run that never overflows the ring is full-run coverage, not a tail.
    func testShortRunIsFullRunCoverage() {
        let key = freshKey("short")
        for _ in 0..<100 { LatencyMetrics.record(key, milliseconds: 3.0) }

        let window = LatencyMetrics.window(for: key)
        XCTAssertEqual(window?.coverage, .fullRun)
        XCTAssertEqual(window?.droppedCount, 0)
        XCTAssertEqual(window?.declaration, "n=100, full run")
    }

    // MARK: - Reporting

    /// A percentile cannot be emitted without its window.
    func testReadingRowCarriesWindowDeclaration() {
        let key = freshKey("row")
        LatencyMetrics.beginCapture(key: key)
        for i in 0..<1_000 { LatencyMetrics.record(key, milliseconds: i < 20 ? 100.0 : 4.0) }

        let reading = LatencyMetrics.reading(for: key)
        XCTAssertNotNil(reading)
        XCTAssertTrue(reading!.row.contains("n=1000, full run"),
                      "Every emitted row declares its window. Row was: \(reading!.row)")
        XCTAssertEqual(reading!.window.coverage, .fullRun)

        LatencyMetrics.clearCapture(key: key)
    }

    /// `SessionCache` calls `resetSession()` at session edges. Capture registration must
    /// survive it, or a harness would silently fall back to the ring mid-run.
    func testResetSessionClearsSamplesButKeepsCaptureRegistration() {
        let key = freshKey("reset")
        LatencyMetrics.beginCapture(key: key)
        for _ in 0..<1_000 { LatencyMetrics.record(key, milliseconds: 9.0) }
        XCTAssertEqual(LatencyMetrics.window(for: key)?.sampleCount, 1_000)

        LatencyMetrics.resetSession()

        XCTAssertNil(LatencyMetrics.window(for: key), "Samples cleared.")
        XCTAssertTrue(LatencyMetrics.isCapturing(key), "Capture registration survives the reset.")

        for _ in 0..<600 { LatencyMetrics.record(key, milliseconds: 9.0) }
        let window = LatencyMetrics.window(for: key)
        XCTAssertEqual(window?.mode, .capture, "Still capturing after the session boundary.")
        XCTAssertEqual(window?.sampleCount, 600)
        XCTAssertEqual(window?.coverage, .fullRun)

        LatencyMetrics.clearCapture(key: key)
    }

    /// Gate 1.4 — capture cost is trivial, but the number should be checkable.
    func testCaptureMemoryCostIsStated() {
        let key = freshKey("memory")
        LatencyMetrics.beginCapture(key: key)
        for _ in 0..<7_200 { LatencyMetrics.record(key, milliseconds: 8.3) }

        // 7,200 doubles × 8 bytes = 57,600 bytes for a 60 s @ 120 Hz glide.
        XCTAssertEqual(LatencyMetrics.captureMemoryBytes(), 7_200 * 8)

        LatencyMetrics.clearCapture(key: key)
    }
}
