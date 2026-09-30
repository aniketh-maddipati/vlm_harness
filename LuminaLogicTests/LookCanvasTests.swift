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
}
