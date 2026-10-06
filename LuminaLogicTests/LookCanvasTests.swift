import XCTest
@testable import Lumina

/// The Edit canvas's scheduling rules (addendum §3–4) with no display behind them: two tiers,
/// latest wins, one render at a time, sequence numbers, the 120 ms rest render; the byte-capped
/// LRU cache the bases and tiles live in; and the `nr` look key. Foundation only: these also run
/// in the Linux Swift sandbox.
final class LookCanvasTests: XCTestCase {
    typealias S = LookCanvasSchedule

    func testKeystrokeRendersFromBaseAndPresentsOnce() {
        var s = S()
        XCTAssertNil(s.tick(at: 0), "nothing to render yet")
        _ = s.keystroke("ev:+0.50", at: 1)
        let r = try! XCTUnwrap(s.tick(at: 2))
        XCTAssertEqual(r.tier, .base); XCTAssertEqual(r.look, "ev:+0.50"); XCTAssertTrue(r.stats)
        XCTAssertNil(s.tick(at: 3), "one render at a time")
        XCTAssertTrue(s.finished(r))
        XCTAssertEqual(s.presented, r.seq); XCTAssertEqual(s.presentedTier, .base)
        XCTAssertNil(s.tick(at: 4), "the newest look is on screen at full quality")
        XCTAssertFalse(s.restPending)
    }

    func testDragRendersSmallThenRestsOnDragEnd() {
        var s = S()
        s.dragStart(at: 0)
        s.submit("ev:+0.10", at: 1)
        let a = try! XCTUnwrap(s.tick(at: 2))
        XCTAssertEqual(a.tier, .small); XCTAssertFalse(a.stats)
        XCTAssertTrue(s.finished(a))
        XCTAssertTrue(s.restPending)
        XCTAssertNil(s.tick(at: 20), "still dragging, thumb moved 19 ms ago: no rest render yet")
        s.dragEnd(at: 30)
        let b = try! XCTUnwrap(s.tick(at: 31))
        XCTAssertEqual(b.tier, .base); XCTAssertEqual(b.look, "ev:+0.10"); XCTAssertEqual(b.lookSeq, a.lookSeq)
        XCTAssertTrue(s.finished(b))
        XCTAssertFalse(s.restPending)
        XCTAssertNil(s.tick(at: 40))
    }

    func testIdleRestRenderAfter120msEvenMidDrag() {
        var s = S(idleMs: 120)
        s.dragStart(at: 0)
        s.submit("sh:+30", at: 10)
        let a = try! XCTUnwrap(s.tick(at: 12)); XCTAssertEqual(a.tier, .small); _ = s.finished(a)
        XCTAssertNil(s.tick(at: 100))
        XCTAssertNil(s.tick(at: 129))
        let b = try! XCTUnwrap(s.tick(at: 130))
        XCTAssertEqual(b.tier, .base, "the thumb has been still for 120 ms: full quality")
        XCTAssertEqual(b.roi, nil, "rest renders are never region-only")
        _ = s.finished(b)
        s.submit("sh:+31", at: 200)
        XCTAssertEqual(try XCTUnwrap(s.tick(at: 201)).tier, .small, "the thumb moved again: back to small")
    }

    // MARK: The rest rule during a drag (N8)

    /// Runs a schedule on a 120 Hz display link from `from` to `to` (ms), finishing each render
    /// one refresh later; `events` are applied at their time. Returns the renders in order.
    private func run(_ s: inout S, from: Double, to: Double, _ events: [(at: Double, what: (inout S, Double) -> Void)]) -> [(at: Double, r: S.Request)] {
        var out: [(Double, S.Request)] = [], queue = events.sorted { $0.at < $1.at }[...], flying: S.Request?
        var t = from
        while t <= to {
            while let e = queue.first, e.at <= t { e.what(&s, e.at); queue.removeFirst() }
            if let f = flying { XCTAssertTrue(s.finished(f)); flying = nil }
            if let r = s.tick(at: t) { out.append((t, r)); flying = r }
            t += 1000 / 120
        }
        if let f = flying { _ = s.finished(f) }
        return out
    }

    private func looks(every gap: Double, from: Double, to: Double) -> [(at: Double, what: (inout S, Double) -> Void)] {
        stride(from: from, through: to, by: gap).enumerated().map { i, t in (t, { s, at in s.submit("tc:\(i),0,0", at: at) }) }
    }

    /// A slow drag on a whole-number slider: a look every 110 ms for 2 s (with one late by 15 ms,
    /// past the 120 ms rule). Every look renders from `small`, nothing from `base` until the drag ends.
    func testSlowDragGetsNoRestRenderBeforeDragEnd() {
        for jitter in [0.0, 15] {
            var s = S()
            var events = looks(every: 110, from: 60, to: 2000)
            if jitter > 0 { let k = events.count / 2; for i in k..<events.count { events[i].at += jitter } }
            let n = events.count, last = events.last!.at
            events.insert((0, { s, at in s.dragStart(at: at) }), at: 0)
            let during = run(&s, from: 0, to: last + 100, events)
            XCTAssertEqual(during.filter { $0.r.tier == .base }.count, 0, "jitter \(jitter): a rest render in the middle of the drag")
            XCTAssertEqual(during.count, n, "every look rendered once, from small")
            XCTAssertEqual(s.cadence ?? 0, 110, accuracy: 0.001)
            XCTAssertEqual(s.restAfterMs, 165, accuracy: 0.001)
            XCTAssertEqual(s.stats.coalesced, 0)
            // Drag end: the rest render on the next refresh, however long the cadence was.
            s.dragEnd(at: last + 101)
            let rest = try! XCTUnwrap(s.tick(at: last + 102))
            XCTAssertEqual(rest.tier, .base); XCTAssertEqual(rest.lookSeq, n); XCTAssertTrue(rest.stats)
            XCTAssertTrue(s.finished(rest)); XCTAssertFalse(s.restPending)
        }
    }

    /// A fast drag (a look every refresh or two): the rule is the 120 ms one, as before.
    func testFastDragRestsAfter120msAsBefore() {
        var s = S()
        var events = looks(every: 16, from: 10, to: 2000)
        let last = events.last!.at
        events.insert((0, { s, at in s.dragStart(at: at) }), at: 0)
        let during = run(&s, from: 0, to: last + 110, events)
        XCTAssertEqual(during.filter { $0.r.tier == .base }.count, 0)
        XCTAssertEqual(s.restAfterMs, 120, "1.5 × 16 ms is under idleMs")
        XCTAssertNil(s.tick(at: last + 119.9))
        let rest = try! XCTUnwrap(s.tick(at: last + 120))
        XCTAssertEqual(rest.tier, .base, "the thumb held still for 120 ms with the button down")
    }

    /// A slow drag that stops for 400 ms and goes on: one rest render in the pause (after 1.5 ×
    /// the cadence), none before or after, and the pause does not become the cadence.
    func testAPauseMidDragRestsOnce() {
        var s = S()
        var events = looks(every: 110, from: 60, to: 800)              // … 720
        let stopped = events.last!.at
        events += looks(every: 110, from: stopped + 400, to: stopped + 400 + 770).map { e in (e.at, { s, at in s.submit("tc:0,\(Int(at)),0", at: at) }) }
        let last = events.last!.at
        events.insert((0, { s, at in s.dragStart(at: at) }), at: 0)
        let renders = run(&s, from: 0, to: last + 100, events)
        let rests = renders.filter { $0.r.tier == .base }
        XCTAssertEqual(rests.count, 1)
        XCTAssertEqual(rests[0].at, stopped + 165, accuracy: 1000 / 120 + 0.001, "after 1.5 × the 110 ms cadence of stillness")
        XCTAssertEqual(s.cadence ?? 0, 110, accuracy: 0.001, "the 400 ms gap was a pause, not the cadence")
        XCTAssertEqual(renders.last?.r.tier, .small)
        s.dragEnd(at: last + 101)
        XCTAssertEqual(try! XCTUnwrap(s.tick(at: last + 102)).tier, .base)
    }

    /// The cadence belongs to one drag, and stillness never waits longer than 3 × idleMs.
    func testCadenceIsPerDragAndCapped() {
        var s = S()
        s.dragStart(at: 0)
        s.submit("a", at: 0); s.submit("b", at: 110)
        XCTAssertEqual(s.restAfterMs, 165, accuracy: 0.001)
        s.submit("c", at: 270)                                           // 160 ms: still under 165, the cadence follows
        XCTAssertEqual(s.restAfterMs, 240, accuracy: 0.001)
        s.submit("d", at: 500); s.submit("e", at: 835)                   // 230, then 335 (under 345)
        XCTAssertEqual(s.restAfterMs, 360, "never more than 3 × idleMs")
        s.dragEnd(at: 900)
        XCTAssertEqual(s.restAfterMs, 120, "not dragging: idleMs")
        s.dragStart(at: 1000)
        XCTAssertNil(s.cadence, "a new drag starts without one")
        s.submit("f", at: 1010)
        XCTAssertEqual(s.restAfterMs, 120)
        s.reset()
        XCTAssertNil(s.cadence)
    }

    /// Not dragging: nothing changed. A look renders from `base` at once (no small tier, no wait),
    /// and a look let go mid-drag after one step still rests at 120 ms (the test above this mark).
    func testNotDraggingIsUnchanged() {
        var s = S()
        for (i, t) in [0.0, 110, 220, 330].enumerated() {
            s.submit("ev:+0.\(i)", at: t)
            let r = try! XCTUnwrap(s.tick(at: t + 1))
            XCTAssertEqual(r.tier, .base); XCTAssertTrue(s.finished(r))
            XCTAssertNil(s.tick(at: t + 100))
        }
        XCTAssertNil(s.cadence, "looks outside a drag set no cadence")
        XCTAssertEqual(s.restAfterMs, 120)
        XCTAssertEqual(s.stats.small, 0); XCTAssertEqual(s.stats.base, 4)
    }

    func testLatestWinsAndNeverQueuesBehindARenderInFlight() {
        var s = S()
        s.dragStart(at: 0)
        for i in 1...50 { s.submit("ev:+0.\(String(format: "%02d", i))", at: Double(i)) }
        let a = try! XCTUnwrap(s.tick(at: 51))
        XCTAssertEqual(a.look, "ev:+0.50", "only the newest value renders")
        XCTAssertEqual(s.stats.coalesced, 49)
        for i in 51...60 { s.submit("ev:+0.\(i)", at: Double(i + 1)) }
        XCTAssertNil(s.tick(at: 62), "a render is in flight: nothing queues behind it")
        XCTAssertTrue(s.finished(a))
        let b = try! XCTUnwrap(s.tick(at: 63))
        XCTAssertEqual(b.look, "ev:+0.60", "the next tick takes the newest value, not the 10 in between")
        XCTAssertEqual(s.stats.started, 2)
        XCTAssertEqual(s.stats.coalesced, 58)
    }

    /// `pending`: a newer look waits that no render has started (the canvas counts a tick with a
    /// render still in flight and a look pending as a missed present).
    func testPendingMeansANewerLookNoRenderHasStarted() {
        var s = S()
        XCTAssertFalse(s.pending)
        s.dragStart(at: 0)
        s.submit("ev:+0.10", at: 1)
        XCTAssertTrue(s.pending)
        let a = try! XCTUnwrap(s.tick(at: 2))
        XCTAssertFalse(s.pending, "started")
        s.submit("ev:+0.20", at: 3)
        XCTAssertTrue(s.pending, "a newer look arrived while the render is in flight")
        XCTAssertNil(s.tick(at: 4))
        _ = s.finished(a)
        let b = try! XCTUnwrap(s.tick(at: 5))
        XCTAssertEqual(b.look, "ev:+0.20")
        XCTAssertFalse(s.pending)
    }

    func testSequenceNumbersGateWhatIsPresented() {
        var s = S()
        _ = s.keystroke("ev:+1", at: 0)
        let a = try! XCTUnwrap(s.tick(at: 1))
        _ = s.keystroke("ev:+2", at: 2)
        s.failed(a)                                   // e.g. the drawable was lost
        let b = try! XCTUnwrap(s.tick(at: 3))
        XCTAssertGreaterThan(b.seq, a.seq)
        XCTAssertTrue(s.finished(b))
        XCTAssertFalse(s.finished(a), "an older render finishing late is not presented")
        XCTAssertEqual(s.stats.stale, 1)
        XCTAssertEqual(s.presentedLook, "ev:+2")
    }

    func testROITravelsOnlyWithSmallRenders() {
        var s = S()
        let roi = S.ROI(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
        s.dragStart(at: 0)
        s.submit("clr:+20", at: 1, roi: roi)
        let a = try! XCTUnwrap(s.tick(at: 2))
        XCTAssertEqual(a.roi, roi)
        _ = s.finished(a)
        s.dragEnd(at: 3)
        let b = try! XCTUnwrap(s.tick(at: 4))
        XCTAssertNil(b.roi)
        XCTAssertTrue(S.ROI(x: 0, y: 0, w: 1, h: 1).isWhole); XCTAssertFalse(roi.isWhole)
    }

    /// The canvas draws the newest look again when its base lands or its size changes. A look of
    /// the page's that had not been drawn yet keeps its `seq`, so its frame is still acknowledged
    /// (the first entry into Edit sat on "rendering…" when a re-render took its place without it).
    func testAgainKeepsThePagesSeqAndLook() {
        var s = S()
        XCTAssertFalse(s.again(at: 0), "nothing to draw again before a look was given")
        _ = s.keystroke("ev:+1", at: 0)                                  // entering the photo
        let a = try! XCTUnwrap(s.tick(at: 1)); _ = s.finished(a)
        _ = s.submit("ev:+2", at: 2, pageSeq: 7, pageAt: 100)            // the page's look, no base yet
        XCTAssertTrue(s.again(at: 3))                                    // the canvas got its size
        XCTAssertTrue(s.again(at: 4))                                    // the base landed
        let b = try! XCTUnwrap(s.tick(at: 5))
        XCTAssertEqual(b.look, "ev:+2", "the newest look, not the last one presented")
        XCTAssertEqual(b.pageSeq, 7); XCTAssertEqual(b.pageAt, 100); XCTAssertEqual(b.tier, .base)
        _ = s.finished(b)
        XCTAssertNil(s.tick(at: 6))
        // Drawn again after it was on screen (the stand-in, then the RAW): the same seq, not timed twice.
        XCTAssertTrue(s.again(at: 7))
        let c = try! XCTUnwrap(s.tick(at: 8))
        XCTAssertEqual(c.look, "ev:+2"); XCTAssertEqual(c.pageSeq, 7); XCTAssertEqual(c.pageAt, 0)
        XCTAssertGreaterThan(c.seq, b.seq); XCTAssertGreaterThan(c.lookSeq, b.lookSeq)
        // During a drag it is still a full-quality render.
        _ = s.finished(c); s.dragStart(at: 9); XCTAssertTrue(s.again(at: 10))
        XCTAssertEqual(s.tick(at: 11)?.tier, .base)
    }

    func testResetForgetsEverything() {
        var s = S()
        _ = s.keystroke("ev:+1", at: 0)
        let a = try! XCTUnwrap(s.tick(at: 1)); _ = s.finished(a)
        s.reset()
        XCTAssertNil(s.presentedLook); XCTAssertNil(s.tick(at: 2)); XCTAssertFalse(s.restPending)
    }

    // MARK: LookByteCache

    func testByteCacheEvictsLeastRecentlyUsedAndKeepsPinned() {
        var c = LookByteCache<String, String>(cap: 100)
        c.set("a", "A", bytes: 40); c.set("b", "B", bytes: 40)
        XCTAssertEqual(c.get("a"), "A")                          // a is now the most recent
        let gone = c.set("c", "C", bytes: 40)
        XCTAssertEqual(gone, ["B"], "b was least recently used")
        XCTAssertEqual(c.keys, ["a", "c"]); XCTAssertEqual(c.bytes, 80); XCTAssertEqual(c.evictions, 1)
        c.pinned = ["a"]
        let gone2 = c.set("d", "D", bytes: 40)
        XCTAssertEqual(gone2, ["C"], "the pinned entry stays even though it is older")
        XCTAssertEqual(Set(c.keys), ["a", "d"])
        XCTAssertEqual(c.set("big", "X", bytes: 90), ["D"], "a new entry is never evicted by its own insert")
        XCTAssertEqual(c.bytes, 130, "pinned + the new entry may exceed the cap")
        XCTAssertEqual(c.trim(to: 0), ["X"])
        XCTAssertEqual(c.keys, ["a"])
        XCTAssertNil(c.get("nope")); XCTAssertEqual(c.misses, 1)
        XCTAssertEqual(c.removeAll(where: { $0 == "a" }), ["A"])
        XCTAssertEqual(c.bytes, 0)
    }

    func testByteCacheReplaceAndPeek() {
        var c = LookByteCache<Int, Int>(cap: 10)
        c.set(1, 10, bytes: 4)
        XCTAssertEqual(c.set(1, 11, bytes: 6), [10], "replacing returns the old value")
        XCTAssertEqual(c.bytes, 6); XCTAssertEqual(c.peek(1), 11); XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c.remove(1), 11); XCTAssertEqual(c.bytes, 0)
    }

    // MARK: the nr key

    func testNoiseReductionKeyRoundTripsAndClamps() throws {
        let l = try Look.parse("ev:+0.5 nr:35")
        XCTAssertEqual(l.nr, 35)
        XCTAssertTrue(l.format().contains(" nr:35"))
        XCTAssertEqual(try Look.parse(l.format()), l)
        XCTAssertNil(try Look.parse("ev:+0.5").nr)
        XCTAssertEqual(try Look.parse("nr:500").nr, 100)
        XCTAssertTrue(try Look.parse("nr:20").isNeutral, "nr is a develop parameter, not a look stage")
        XCTAssertEqual(Look.keys.firstIndex(of: "nr"), Look.keys.firstIndex(of: "bw")! - 1)
    }

    // MARK: LookRawPolicy

    func testTiersAndPin() {
        let a7 = LookDecoderInfo(supported: [7, 8, 9], raw9: true, fastest: 8)
        let old = LookDecoderInfo(supported: [7, 8], raw9: false, fastest: 8)
        XCTAssertNil(LookRawPolicy.version(for: .cull, body: a7, pinned: 9), "Cull never decodes a RAW")
        XCTAssertEqual(LookRawPolicy.version(for: .canvas, body: a7, pinned: 9), 8, "the canvas takes the fastest")
        XCTAssertEqual(LookRawPolicy.version(for: .region, body: a7, pinned: 9), 9)
        XCTAssertEqual(LookRawPolicy.version(for: .export, body: a7, pinned: 8), 8, "the pin wins over a newer decoder")
        XCTAssertEqual(LookRawPolicy.version(for: .export, body: old, pinned: 9), 8, "a body without the pin takes its newest")
        XCTAssertEqual(LookRawPolicy.pin(for: ["a": a7, "b": old]), 9)
        XCTAssertEqual(LookRawPolicy.fallback(after: 9, supported: [7, 8, 9]), 8)
        XCTAssertNil(LookRawPolicy.fallback(after: 7, supported: [7, 8, 9]))
        var h = LookShootHeader(bodies: ["ILCE-7M4": old], decoderVersion: 8)
        XCTAssertFalse(h.offersUpdate); XCTAssertFalse(h.raw9Active)
        h.bodies["ILCE-7M4"] = a7
        XCTAssertTrue(h.offersUpdate, "a newer decoder appeared: offer, never switch")
        h.decoderVersion = 9
        XCTAssertTrue(h.raw9Active)
        let back = try! LookShootHeader.decode(try! h.encoded())
        XCTAssertEqual(back, h)
    }

    func testThermalAndMemoryRules() {
        XCTAssertEqual(LookRawPolicy.regionDelayMs(thermalState: 0, lowPower: false), 0)
        XCTAssertEqual(LookRawPolicy.regionDelayMs(thermalState: 2, lowPower: false), 400)
        XCTAssertEqual(LookRawPolicy.regionDelayMs(thermalState: 1, lowPower: true), 400)
        XCTAssertEqual(LookRawPolicy.exportMemoryLimitMB(physicalMemory: 8 << 30), 512)
        XCTAssertEqual(LookRawPolicy.exportMemoryLimitMB(physicalMemory: 16 << 30), 0)
        XCTAssertEqual(LookRawPolicy.pressureOrder, ["tiles", "prefetchBases"])
    }

    func testRegionTilesCoverTheROIPlusOneTileOfMargin() {
        // A 24 MP frame (6000 × 4000): 12 × 8 tiles of 512.
        let roi = LookCanvasSchedule.ROI(x: 0.4, y: 0.4, w: 0.17, h: 0.19)    // 2400…3420 × 1600…2360
        let t = LookRawPolicy.tiles(covering: roi, width: 6000, height: 4000)
        let cols = Set(t.map(\.col)), rows = Set(t.map(\.row))
        XCTAssertEqual(cols, Set(3...7), "columns 4…6 hold the region, one more on each side")
        XCTAssertEqual(rows, Set(2...5))
        XCTAssertEqual(t.count, cols.count * rows.count)
        let edge = LookRawPolicy.tiles(covering: LookCanvasSchedule.ROI(x: 0, y: 0, w: 0.05, h: 0.05), width: 6000, height: 4000)
        XCTAssertEqual(Set(edge.map(\.col)), Set(0...1)); XCTAssertEqual(Set(edge.map(\.row)), Set(0...1))
        XCTAssertTrue(LookRawPolicy.tiles(covering: roi, width: 0, height: 0).isEmpty)
    }

    /// `Look.rot`: the loupe's region is named in the turned picture, the tiles live in the frame as shot.
    func testRegionOfATurnedPictureMapsBackToTheFrame() {
        typealias ROI = LookCanvasSchedule.ROI
        let roi = ROI(x: 0.1, y: 0.2, w: 0.3, h: 0.4)
        func same(_ a: ROI, _ b: ROI, _ what: String) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-12, what); XCTAssertEqual(a.y, b.y, accuracy: 1e-12, what)
            XCTAssertEqual(a.w, b.w, accuracy: 1e-12, what); XCTAssertEqual(a.h, b.h, accuracy: 1e-12, what)
        }
        XCTAssertEqual(LookRawPolicy.unturned(roi, rot: 0), roi)
        // Turned clockwise, the picture's top left corner is the frame's bottom left.
        same(LookRawPolicy.unturned(ROI(x: 0, y: 0, w: 0.25, h: 0.5), rot: 90), ROI(x: 0, y: 0.75, w: 0.5, h: 0.25), "90")
        same(LookRawPolicy.unturned(ROI(x: 0, y: 0, w: 0.25, h: 0.5), rot: 180), ROI(x: 0.75, y: 0.5, w: 0.25, h: 0.5), "180")
        same(LookRawPolicy.unturned(ROI(x: 0, y: 0, w: 0.25, h: 0.5), rot: 270), ROI(x: 0.5, y: 0, w: 0.5, h: 0.25), "270")
        // Turning the frame's region forward again (90 then 270, 180 twice) is the region itself.
        same(LookRawPolicy.unturned(LookRawPolicy.unturned(roi, rot: 90), rot: 270), roi, "90 + 270")
        same(LookRawPolicy.unturned(LookRawPolicy.unturned(roi, rot: 180), rot: 180), roi, "180 twice")
        same(LookRawPolicy.unturned(roi, rot: -90), LookRawPolicy.unturned(roi, rot: 270), "-90 is 270")
        XCTAssertTrue(LookRawPolicy.unturned(ROI(x: 0, y: 0, w: 1, h: 1), rot: 90).isWhole)
    }

    // MARK: The warm-up plan (LookWarmPlan)

    private let stages = LookRules().lookStages

    func testEverySliderSwitchesExactlyOneStage() throws {
        XCTAssertEqual(LookWarmPlan.signature(Look(), stages: stages), "none")
        var seen: Set<String> = []
        for (key, field) in Look.sliders {
            var l = Look(); l[keyPath: field] = key == "shp" ? 30 : 10
            let on = stages.filter(l.runs)
            XCTAssertEqual(on.count, 1, "\(key) runs \(on)")
            seen.formUnion(on)
        }
        var wb = Look(); wb.wb = Look.WhiteBalance(kelvin: 5200, tint: 3)
        XCTAssertEqual(stages.filter(wb.runs), ["whiteBalance"])
        var bw = Look(); bw.bw = true
        XCTAssertEqual(stages.filter(bw.runs), ["colour"])
        // The stages whose controls are not plain sliders: each of their keys switches exactly that stage.
        for text in ["tc:0,+10,0", "tc:-5,0,0", "crv:0,0/0.5,0.6/1,1", "crvr:0,0.1/1,1", "crvg:0,0/1,0.9", "crvb:0,0/0.4,0.5/1,1", "tc:+10,0,0 crv:0,0/0.5,0.6/1,1 crvb:0,0/1,0.9"] {
            XCTAssertEqual(stages.filter(try Look.parse(text).runs), ["curve"], text)
        }
        for text in ["mixh:0,0,+10,0,0,0,0,0", "mixs:-100,0,0,0,0,0,0,0", "mixl:0,0,0,0,0,0,0,+1", "mixh:+5,0,0,0,0,0,0,0 mixs:0,0,0,-5,0,0,0,0 mixl:0,0,0,0,+5,0,0,0"] {
            XCTAssertEqual(stages.filter(try Look.parse(text).runs), ["mixer"], text)
        }
        XCTAssertEqual(LookWarmPlan.signature(try Look.parse("con:+10 tc:0,+5,0 sat:+5 mixs:0,+5,0,0,0,0,0,0 clr:+5"), stages: stages), "contrast+curve+colour+mixer+clarity", "in the order the stages run")
        XCTAssertEqual(seen.union(["whiteBalance", "curve", "mixer"]), Set(stages), "every stage has a control that switches it on")
        // rot is geometry (the base), the vignette's shape draws nothing without an amount.
        XCTAssertEqual(LookWarmPlan.signature(try Look.parse("rot:90 vigs:20,-50,80,40 tc:0,0,0 crv:0,0/1,1"), stages: stages), "none")
        // nr and crop belong to the base (the RAW stage, the geometry), not to a look stage.
        XCTAssertEqual(LookWarmPlan.signature(try Look.parse("nr:40 crop:0.1,0.1,0.5,0.5/2"), stages: stages), "none")
        XCTAssertEqual(LookWarmPlan.signature(try Look.parse("vig:-20 ev:+0.30 con:+10"), stages: stages), "exposure+contrast+vignette", "in the order the stages run")
    }

    func testTogglingSwitchesOneStageAndLeavesTheRest() throws {
        let look = try Look.parse("ev:+0.30 con:+10 sat:-20 bw:1 bl:-5")
        for stage in stages {
            let t = look.toggling(stage)
            XCTAssertNotEqual(t.runs(stage), look.runs(stage), stage)
            for other in stages where other != stage { XCTAssertEqual(t.runs(other), look.runs(other), "\(stage) touched \(other)") }
            XCTAssertEqual(LookWarmPlan.signature(t.toggling(stage), stages: stages), LookWarmPlan.signature(look, stages: stages))
            XCTAssertEqual(t.crop, look.crop); XCTAssertEqual(t.nr, look.nr)
        }
        XCTAssertEqual(look.toggling("no such stage"), look)
    }

    func testWarmPlanCoversEverySetOneSliderCanReach() throws {
        let look = try Look.parse("ev:+0.30 con:+10")
        let around = LookWarmPlan.looks(around: look, stages: stages).map { LookWarmPlan.signature($0, stages: stages) }
        XCTAssertEqual(around.count, stages.count + 1)
        XCTAssertEqual(Set(around).count, around.count)
        XCTAssertEqual(around.first, "exposure+contrast", "the look on the canvas comes first")
        XCTAssertTrue(around.contains("contrast"), "exposure dragged through 0")
        XCTAssertTrue(around.contains("exposure"))
        XCTAssertTrue(around.contains("exposure+tone+contrast"), "the first drag on shadows")
        XCTAssertTrue(around.contains("exposure+contrast+vignette"))
        // Any single slider change from the look lands on a warmed set.
        for (key, field) in Look.sliders {
            for v in [0.0, key == "shp" ? 40 : -15] {
                var l = look; l[keyPath: field] = v
                XCTAssertTrue(around.contains(LookWarmPlan.signature(l, stages: stages)), "\(key) = \(v)")
            }
        }
    }

    /// The vignette is one stage and one program whatever its shape: a shape slider never changes the set.
    func testVignetteShapeNeverChangesTheStageSet() throws {
        let plain = try Look.parse("ev:+0.30 vig:-20"), shaped = try Look.parse("ev:+0.30 vig:-20 vigs:50,-40,50,30")
        XCTAssertEqual(LookWarmPlan.signature(plain, stages: stages), "exposure+vignette")
        XCTAssertEqual(LookWarmPlan.signature(shaped, stages: stages), "exposure+vignette")
        XCTAssertEqual(LookWarmPlan.signature(try Look.parse("ev:+0.30 vigs:50,0,50,30"), stages: stages), "exposure", "a shape without an amount runs nothing")
        XCTAssertEqual(LookWarmPlan.looks(around: shaped, stages: stages).count, stages.count + 1)
        let off = try Look.parse("vigs:50,-40,50,0")
        XCTAssertEqual(off.toggling("vignette").vignetteShape, off.vignetteShape, "switching the amount on keeps the shape")
    }

    func testWarmPlanOrdersSmallFirstAndNeverRepeats() throws {
        var plan = LookWarmPlan()
        let look = try Look.parse("ev:+0.30 con:+10"), env = "2024x1472/506x368>1760x1280|P3|fit"
        var jobs = plan.jobs(around: look, stages: stages, env: env)
        XCTAssertEqual(jobs.count, 2 * (stages.count + 1))
        XCTAssertEqual(jobs.prefix(stages.count + 1).map(\.tier), Array(repeating: .small, count: stages.count + 1), "what a drag renders comes first")
        XCTAssertEqual(jobs.first?.stages, "exposure+contrast")
        XCTAssertEqual(Set(jobs.map(\.key)).count, jobs.count)
        // The drawable rendered the look from base itself (entering Edit): not warmed again.
        let own = plan.rendering(look, tier: .base, stages: stages, env: env)
        XCTAssertTrue(own.first); XCTAssertFalse(own.warmed); XCTAssertEqual(own.stages, "exposure+contrast")
        XCTAssertFalse(plan.rendering(look, tier: .base, stages: stages, env: env).first)
        XCTAssertEqual(plan.jobs(around: look, stages: stages, env: env).count, jobs.count - 1)
        while let job = plan.next(around: look, stages: stages, env: env) { plan.finished(job, ms: 12) }
        XCTAssertEqual(plan.stats.warmed, jobs.count - 1)
        XCTAssertEqual(plan.stats.ms, 12 * Double(jobs.count - 1)); XCTAssertEqual(plan.stats.maxMs, 12)
        // The first frame of a drag on shadows: a set the drawable has not rendered, already warmed.
        var dragged = look; dragged.shadows = -30
        let first = plan.rendering(dragged, tier: .small, stages: stages, env: env)
        XCTAssertTrue(first.first); XCTAssertTrue(first.warmed); XCTAssertEqual(first.stages, "exposure+tone+contrast")
        // At rest on the new look the plan owes only what the new set adds, both tiers.
        jobs = plan.jobs(around: dragged, stages: stages, env: env)
        XCTAssertEqual(jobs.count, 2 * (stages.count - 1), "the look itself and the look without tone are done")
        XCTAssertFalse(jobs.contains { $0.stages == "exposure+contrast" || $0.stages == "exposure+tone+contrast" })
        // Another canvas size (or display, or zoom) is another set of programs.
        XCTAssertEqual(plan.jobs(around: look, stages: stages, env: "other").count, 2 * (stages.count + 1))
        // Two stages away (a pasted look) is not covered until the canvas rests on it.
        var pasted = look; pasted.clarity = 20; pasted.vignette = -10
        let far = plan.rendering(pasted, tier: .small, stages: stages, env: env)
        XCTAssertTrue(far.first); XCTAssertFalse(far.warmed)
    }

    func testWarmPlanDisabledOwesNothingButStillCountsFirstRenders() throws {
        var plan = LookWarmPlan(enabled: false)
        let look = try Look.parse("ev:+0.30")
        XCTAssertTrue(plan.jobs(around: look, stages: stages, env: "e").isEmpty)
        XCTAssertNil(plan.next(around: look, stages: stages, env: "e"))
        let r = plan.rendering(look, tier: .small, stages: stages, env: "e")
        XCTAssertTrue(r.first); XCTAssertFalse(r.warmed)
        XCTAssertFalse(plan.stats.enabled)
    }
}
