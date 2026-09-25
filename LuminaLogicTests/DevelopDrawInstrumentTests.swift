import XCTest
@testable import Lumina

/// Falsifier for the mixed-population defect in `p0.edit.draw_ms` (W0 instruments).
///
/// `LatencyMetrics.editDrawKey` brackets `DevelopMetalView.draw(in:)` from just before
/// the Core Image `startTask` pair to the command buffer's completion handler, so the
/// settled demosaic genuinely is inside that number. What it cannot do is hold two
/// populations apart: cheap draws of a materialized RAW stage and expensive draws of a
/// lazy `CIRAWFilter` graph land in one distribution, and the cheap one outnumbers the
/// expensive one by orders of magnitude during a scrub.
///
/// `testMixedKeyHidesTheLazyPopulationThatTheSplitKeysReveal` below is that claim as
/// arithmetic. The rest pin the budgets, the key names, the attribution rule, and the
/// off-by-default guarantee.
final class DevelopDrawInstrumentTests: XCTestCase {

    private static let allKeys = DevelopDrawInstruments.Key.all + [LatencyMetrics.editDrawKey]

    override func setUp() {
        super.setUp()
        for key in Self.allKeys { LatencyMetrics.clearCapture(key: key) }
        LatencyMetrics.resetSession()
        DevelopDrawInstruments.setEnabledForTesting(nil)
    }

    override func tearDown() {
        DevelopDrawInstruments.setEnabledForTesting(nil)
        for key in Self.allKeys { LatencyMetrics.clearCapture(key: key) }
        LatencyMetrics.resetSession()
        super.tearDown()
    }

    // MARK: - Key identity

    /// The exact strings a report will quote. Pinned so a rename is a deliberate act
    /// rather than a silently orphaned row in someone's evidence file.
    func testKeyNamesArePinned() {
        XCTAssertEqual(DevelopDrawInstruments.Key.drawWalkLazy, "p0.develop.draw_walk_lazy_ms")
        XCTAssertEqual(DevelopDrawInstruments.Key.drawWalkMaterialized, "p0.develop.draw_walk_materialized_ms")
        XCTAssertEqual(DevelopDrawInstruments.Key.drawLazy, "p0.develop.draw_lazy_ms")
        XCTAssertEqual(DevelopDrawInstruments.Key.drawMaterialized, "p0.develop.draw_materialized_ms")
        XCTAssertEqual(DevelopDrawInstruments.Key.all.count, 4)
        XCTAssertEqual(Set(DevelopDrawInstruments.Key.all).count, 4, "no key may alias another")
    }

    /// Static keys, not strings built from a backing at the call site. A dynamic key
    /// would miss `declaredSLAms` entirely and inherit the 50 ms navigation fallback
    /// without anything in the output saying so.
    func testEveryRecordableKeyIsDeclared() {
        for key in DevelopDrawInstruments.Key.all {
            XCTAssertTrue(
                LatencyMetrics.declaredSLAKeys.contains(key),
                "\(key) must be declared, or it silently inherits navigationSLAms"
            )
        }
    }

    // MARK: - Declared budgets (PROPOSED)

    func testDevelopDrawKeysDeclareTheFrameBudget() {
        for key in DevelopDrawInstruments.Key.all {
            XCTAssertEqual(
                LatencyMetrics.sla(for: key),
                LatencyMetrics.frameBudget120HzMs,
                "\(key) is judged against one 120 Hz display interval, not the 50 ms fallback"
            )
        }
    }

    /// The point of declaring them: the value they would otherwise have inherited is
    /// 6× looser, and the measured lazy draw (79.5–91.0 ms after a pan) sits above
    /// both — but only the declared budget makes a 4 ms materialized draw's breach
    /// meaningful at all.
    func testDevelopDrawBudgetIsNotTheInheritedNavigationSLA() {
        let declared = LatencyMetrics.sla(for: DevelopDrawInstruments.Key.drawLazy)
        XCTAssertNotEqual(declared, LatencyMetrics.navigationSLAms)
        XCTAssertLessThan(declared, LatencyMetrics.navigationSLAms)
    }

    /// W0's hard constraint: `p0.edit.draw_ms` keeps its name and its historical
    /// 50 ms budget. The new keys sit beside it; they do not re-budget it.
    func testEditDrawKeyIsUntouchedByTheNewKeys() {
        XCTAssertEqual(LatencyMetrics.editDrawKey, "p0.edit.draw_ms")
        XCTAssertEqual(LatencyMetrics.sla(for: LatencyMetrics.editDrawKey), LatencyMetrics.navigationSLAms)
        XCTAssertFalse(
            DevelopDrawInstruments.Key.all.contains(LatencyMetrics.editDrawKey),
            "the new keys must not collide with the historical one"
        )
    }

    // MARK: - Attribution rule

    func testBackingSelectsItsOwnKeyPair() {
        XCTAssertEqual(DevelopDrawInstruments.walkKey(for: .lazyGraph), DevelopDrawInstruments.Key.drawWalkLazy)
        XCTAssertEqual(DevelopDrawInstruments.drawKey(for: .lazyGraph), DevelopDrawInstruments.Key.drawLazy)
        XCTAssertEqual(
            DevelopDrawInstruments.walkKey(for: .materialized),
            DevelopDrawInstruments.Key.drawWalkMaterialized
        )
        XCTAssertEqual(
            DevelopDrawInstruments.drawKey(for: .materialized),
            DevelopDrawInstruments.Key.drawMaterialized
        )
    }

    /// The sampling rule, stated as a falsifier: a proxy / ImageIO-fallback / browse
    /// surface never went through the RAW stage, so its draws are left out of both
    /// distributions rather than guessed into one. An unattributed draw is visible as
    /// the gap between `p0.edit.draw_ms`'s total and the two attributed counts.
    func testUnattributedSurfacesAreNotSampled() {
        XCTAssertNil(DevelopDrawInstruments.walkKey(for: .unattributed))
        XCTAssertNil(DevelopDrawInstruments.drawKey(for: .unattributed))

        DevelopDrawInstruments.setEnabledForTesting(true)
        DevelopDrawInstruments.recordWalk(milliseconds: 42, backing: .unattributed)
        DevelopDrawInstruments.recordDraw(milliseconds: 42, backing: .unattributed)
        XCTAssertTrue(LatencyMetrics.recordedKeys().isEmpty)
    }

    /// A surface that never reached the RAW stage must default to unattributed, not to
    /// whichever case happens to be first — that default is what keeps non-RAW draws
    /// out of a number about RAW work.
    func testResultAndDisplayFrameDefaultToUnattributed() {
        let result = DevelopRenderResult(
            requestID: UUID(), generation: 1, photoID: UUID(), quality: .interactive,
            fidelity: .interactive, ciImage: nil, cgImage: nil, extent: .zero,
            durationMs: 0, cacheHit: false, rawStageCacheHit: false, cancelled: false,
            usedProxyFallback: false, colorSpaceName: "test"
        )
        XCTAssertEqual(result.rawStageBacking, .unattributed)

        let frame = OrientedDisplayImage.DisplayFrame(
            assetID: UUID(), image: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)),
            recipe: nil, layoutSize: .zero, identity: nil
        )
        XCTAssertEqual(frame.rawStageBacking, .unattributed)
    }

    // MARK: - Off by default

    /// An ordinary run pays nothing and records nothing. This is the same guarantee
    /// `P0RenderInstruments` makes, and W0 must not weaken it: the develop canvas
    /// draws at display rate, so an ungated sample would be a per-frame lock on the
    /// main thread in every shipping session.
    func testRecordsNothingWhileDisabled() {
        DevelopDrawInstruments.setEnabledForTesting(false)
        XCTAssertFalse(DevelopDrawInstruments.isEnabled)
        DevelopDrawInstruments.recordWalk(milliseconds: 91, backing: .lazyGraph)
        DevelopDrawInstruments.recordDraw(milliseconds: 91, backing: .lazyGraph)
        DevelopDrawInstruments.recordWalk(milliseconds: 4, backing: .materialized)
        DevelopDrawInstruments.recordDraw(milliseconds: 4, backing: .materialized)
        XCTAssertTrue(
            LatencyMetrics.recordedKeys().isEmpty,
            "a disabled instrument must not record, and must not open a capture buffer either"
        )
    }

    /// The test process is not launched with `--p0-instruments`, so the real gate is off
    /// unless a test forces it. Pins that the seam defaults to the launch argument
    /// rather than to "on".
    func testLaunchGateIsOffInAnOrdinaryProcess() {
        DevelopDrawInstruments.setEnabledForTesting(nil)
        XCTAssertEqual(DevelopDrawInstruments.isEnabled, DevelopDrawInstruments.launchRequested)
        XCTAssertFalse(DevelopDrawInstruments.launchRequested)
    }

    // MARK: - Separation

    func testEnabledInstrumentSeparatesTheTwoPopulations() {
        DevelopDrawInstruments.setEnabledForTesting(true)
        for _ in 0..<10 {
            DevelopDrawInstruments.recordWalk(milliseconds: 1.2, backing: .materialized)
            DevelopDrawInstruments.recordDraw(milliseconds: 4.0, backing: .materialized)
            DevelopDrawInstruments.recordWalk(milliseconds: 70.0, backing: .lazyGraph)
            DevelopDrawInstruments.recordDraw(milliseconds: 90.0, backing: .lazyGraph)
        }

        XCTAssertEqual(LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawMaterialized) ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawLazy) ?? 0, 90.0, accuracy: 0.001)
        XCTAssertEqual(
            LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawWalkMaterialized) ?? 0, 1.2, accuracy: 0.001)
        XCTAssertEqual(
            LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawWalkLazy) ?? 0, 70.0, accuracy: 0.001)

        for key in DevelopDrawInstruments.Key.all {
            XCTAssertEqual(
                LatencyMetrics.window(for: key)?.sampleCount, 10,
                "\(key) must hold only its own population"
            )
        }
    }

    /// **The defect, as arithmetic.** One key holding both populations reports the cheap
    /// one at p50 *and* at p95; only p99 sees the expensive draws at all, and even then
    /// it cannot say how many there were or which tier they came from. Split by backing,
    /// the 90 ms population is the p50 of its own key with its own sample count.
    ///
    /// This is why a W1 before/after cannot be argued from `p0.edit.draw_ms` alone.
    func testMixedKeyHidesTheLazyPopulationThatTheSplitKeysReveal() {
        DevelopDrawInstruments.setEnabledForTesting(true)

        // 100 interactive draws at 4 ms, 5 settled pan draws at 90 ms — roughly the
        // ratio a scrub-then-pan session produces.
        for _ in 0..<100 {
            LatencyMetrics.record(LatencyMetrics.editDrawKey, milliseconds: 4.0)
            DevelopDrawInstruments.recordDraw(milliseconds: 4.0, backing: .materialized)
        }
        for _ in 0..<5 {
            LatencyMetrics.record(LatencyMetrics.editDrawKey, milliseconds: 90.0)
            DevelopDrawInstruments.recordDraw(milliseconds: 90.0, backing: .lazyGraph)
        }

        XCTAssertEqual(LatencyMetrics.p50(for: LatencyMetrics.editDrawKey) ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(
            LatencyMetrics.p95(for: LatencyMetrics.editDrawKey) ?? 0, 4.0, accuracy: 0.001,
            "even p95 of the mixed key reports the cheap population"
        )
        XCTAssertLessThan(
            LatencyMetrics.p95(for: LatencyMetrics.editDrawKey) ?? 0,
            LatencyMetrics.sla(for: LatencyMetrics.editDrawKey),
            "the mixed key does not even breach its own 50 ms budget while 90 ms draws are happening"
        )

        XCTAssertEqual(LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawLazy) ?? 0, 90.0, accuracy: 0.001)
        XCTAssertEqual(LatencyMetrics.window(for: DevelopDrawInstruments.Key.drawLazy)?.sampleCount, 5)
        XCTAssertGreaterThan(
            LatencyMetrics.p50(for: DevelopDrawInstruments.Key.drawLazy) ?? 0,
            LatencyMetrics.sla(for: DevelopDrawInstruments.Key.drawLazy)
        )

        // The unattributed count a reviewer checks the arithmetic with.
        let total = LatencyMetrics.window(for: LatencyMetrics.editDrawKey)?.totalRecorded ?? 0
        let attributed = (LatencyMetrics.window(for: DevelopDrawInstruments.Key.drawLazy)?.totalRecorded ?? 0)
            + (LatencyMetrics.window(for: DevelopDrawInstruments.Key.drawMaterialized)?.totalRecorded ?? 0)
        XCTAssertEqual(total - attributed, 0, "every draw in this scenario was attributable")
    }

    // MARK: - Capture compatibility

    /// A pan is thousands of draws. Without capture the 512-sample ring reports only the
    /// tail — which is exactly where the first and most expensive draws have aged out.
    /// The instrument promotes its keys on first sample, so this holds without a harness
    /// remembering to call `beginCapture`.
    func testRecordingPromotesTheKeyOutOfTheRing() {
        DevelopDrawInstruments.setEnabledForTesting(true)
        for i in 0..<600 {
            DevelopDrawInstruments.recordDraw(milliseconds: Double(i), backing: .lazyGraph)
        }
        let window = LatencyMetrics.window(for: DevelopDrawInstruments.Key.drawLazy)
        XCTAssertEqual(window?.sampleCount, 600, "capture keeps every sample; the ring would hold 512")
        XCTAssertEqual(window?.coverage, .fullRun)
        XCTAssertEqual(window?.mode, .capture)
        XCTAssertNotNil(
            LatencyMetrics.reading(for: DevelopDrawInstruments.Key.drawLazy)?.window,
            "a develop-draw row cannot be emitted without its window"
        )
    }
}
