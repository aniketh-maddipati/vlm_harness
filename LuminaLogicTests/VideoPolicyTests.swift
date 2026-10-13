import XCTest
@testable import Lumina

/// The video module's budgets, tiers, pacing and profile rules (`VideoPolicy`) with nothing
/// decoded behind them. Foundation only: these also run in the Linux Swift sandbox.
final class VideoPolicyTests: XCTestCase {
    typealias P = VideoPolicy

    // MARK: Filmstrip sampling

    func testFilmstripSkipsTheFirstAndLastFrameAndSpreadsEvenly() {
        let f = P.filmstripFractions(duration: 12)
        XCTAssertEqual(f.count, 8)
        XCTAssertEqual(f.first!, 1.0 / 16, accuracy: 1e-9, "half a slot in, never frame 0")
        XCTAssertEqual(f.last!, 15.0 / 16, accuracy: 1e-9, "never the last frame")
        for (a, b) in zip(f, f.dropFirst()) { XCTAssertEqual(b - a, 1.0 / 8, accuracy: 1e-9) }
    }

    func testShortClipsGetFewerFramesNeverFewerThanTwo() {
        XCTAssertEqual(P.filmstripFractions(duration: 3.4).count, 3, "one per second")
        XCTAssertEqual(P.filmstripFractions(duration: 0.3).count, 2)
        XCTAssertEqual(P.filmstripFractions(duration: 0).count, 0)
        XCTAssertEqual(P.filmstripFractions(duration: 600).count, P.filmstripFrames, "a long clip is still 8")
    }

    // MARK: Decode sizes

    func testTiersDecodeSmallAndNeverUpscale() {
        let fs = P.decodeSize(for: .filmstrip, width: 3840, height: 2160)
        XCTAssertEqual(fs.width, 160); XCTAssertEqual(fs.height, 90)
        let px = P.decodeSize(for: .proxy, width: 3840, height: 2160)
        XCTAssertEqual(px.width, 960); XCTAssertEqual(px.height, 540)
        let portrait = P.decodeSize(for: .proxy, width: 2160, height: 3840)
        XCTAssertEqual(portrait.height, 960); XCTAssertEqual(portrait.width, 540)
        let full = P.decodeSize(for: .frame, width: 3840, height: 2160)
        XCTAssertEqual(full.width, 3840); XCTAssertEqual(full.height, 2160)
        let tiny = P.decodeSize(for: .proxy, width: 320, height: 180)
        XCTAssertEqual(tiny.width, 320, "never upscaled")
        XCTAssertEqual(P.decodeSize(for: .proxy, width: 0, height: 0).width, 0)
    }

    func testFrameBytesMatchTheTable() {
        // 960 × 540 half-float RGBA ≈ 4 MB; a full 4K half-float frame ≈ 66 MB.
        XCTAssertEqual(P.frameBytes(width: 960, height: 540, halfFloat: true), 4_147_200)
        XCTAssertEqual(P.frameBytes(width: 3840, height: 2160, halfFloat: true), 66_355_200)
        XCTAssertEqual(P.frameBytes(width: 160, height: 90, halfFloat: false), 57_600)
        XCTAssertEqual(P.frameBytes(width: -1, height: 90, halfFloat: false), 0)
    }

    // MARK: Budgets and admission

    func testEightGBMacGetsOneDecoderAndSmallerCaches() {
        let m1 = P.budgets(physicalMemory: 8 << 30), big = P.budgets(physicalMemory: 32 << 30)
        XCTAssertEqual(m1.decoders, 1); XCTAssertEqual(big.decoders, 2)
        XCTAssertLessThan(m1.proxyBytes, big.proxyBytes)
        XCTAssertLessThan(m1.filmstripBytes, big.filmstripBytes)
        XCTAssertEqual(m1.fullFrames, 1); XCTAssertEqual(big.fullFrames, 1, "one full frame whatever the Mac")
        // A full 4K half-float frame plus the proxy cap fits the M1 peak gate with room for the decoder.
        XCTAssertLessThan(Double(m1.proxyBytes + m1.filmstripBytes + 66_355_200) / 1_048_576 + 200, P.m1Gates.peakMB)
    }

    func testFilmstripsStayCompressedSoAWholeCardFitsThe8GBBudget() {
        // The ILCE-7M3 card: 401 clips. Raw RGBA filmstrips would be 185 MB; compressed they fit
        // with room to spare, even on the 8 GB budget.
        let m1 = P.budgets(physicalMemory: 8 << 30)
        XCTAssertGreaterThanOrEqual(P.filmstripClips(in: m1.filmstripBytes), 401 * 4)
        XCTAssertGreaterThan(401 * P.frameBytes(width: 160, height: 90, halfFloat: false) * P.filmstripFrames, m1.filmstripBytes, "raw would not fit; that is why they are compressed")
        XCTAssertEqual(P.filmstripClips(in: 0), 0)
    }

    func testAdmissionAsksBeforeAllocating() {
        XCTAssertTrue(P.admits(inFlightBytes: 0, request: 4 << 20, cap: 16 << 20))
        XCTAssertTrue(P.admits(inFlightBytes: 12 << 20, request: 4 << 20, cap: 16 << 20), "exactly the cap is allowed")
        XCTAssertFalse(P.admits(inFlightBytes: 13 << 20, request: 4 << 20, cap: 16 << 20))
    }

    func testPressureDropsExpendableTiersFirstAndNeverTheGrid() {
        XCTAssertEqual(P.drops(pressure: .none), [])
        XCTAssertEqual(P.drops(pressure: .warning), ["fullFrames", "proxiesNotHovered"])
        XCTAssertEqual(P.drops(pressure: .critical), ["fullFrames", "proxiesNotHovered", "filmstripsOffscreen"])
        XCTAssertFalse(P.pressureOrder.contains { $0.lowercased().contains("hovered") && !$0.contains("Not") })
        XCTAssertFalse(P.pressureOrder.contains { $0.contains("Onscreen") || $0.contains("InView") }, "what is drawn is never dropped")
        XCTAssertTrue(P.Pressure.warning < .critical)
    }

    // MARK: Pacing

    func testAskedLevelTakesTheWorstSignal() {
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: false, pressure: .none, slowdown: 1.0), 0)
        XCTAssertEqual(P.askedLevel(thermalState: 1, lowPower: false, pressure: .none, slowdown: 1.0), 1, "fair eases")
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: true, pressure: .none, slowdown: 1.0), 1, "low power eases")
        XCTAssertEqual(P.askedLevel(thermalState: 2, lowPower: false, pressure: .none, slowdown: 1.0), 2, "serious slows")
        XCTAssertEqual(P.askedLevel(thermalState: 3, lowPower: false, pressure: .none, slowdown: 1.0), 3, "critical pauses")
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: false, pressure: .warning, slowdown: 1.0), 2)
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: false, pressure: .critical, slowdown: 1.0), 3)
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: false, pressure: .none, slowdown: 1.5), 1, "a slowed chip shows in decode time even at nominal")
        XCTAssertEqual(P.askedLevel(thermalState: 0, lowPower: false, pressure: .none, slowdown: 3.0), 2)
        XCTAssertEqual(P.askedLevel(thermalState: 1, lowPower: false, pressure: .none, slowdown: 3.0), 2, "the worst wins")
    }

    func testStepsDownAtOnceAndUpOneAtATimeAfterQuiet() {
        XCTAssertEqual(P.nextLevel(current: 0, asked: 3, quietFor: 0), 3, "down at once, as far as asked")
        XCTAssertEqual(P.nextLevel(current: 3, asked: 0, quietFor: 5), 3, "not yet")
        XCTAssertEqual(P.nextLevel(current: 3, asked: 0, quietFor: P.recoverAfterSeconds), 2, "one step")
        XCTAssertEqual(P.nextLevel(current: 2, asked: 0, quietFor: 60), 1, "never two at once")
        XCTAssertEqual(P.nextLevel(current: 1, asked: 1, quietFor: 600), 1, "stays where it is asked to be")
        XCTAssertEqual(P.nextLevel(current: 0, asked: 0, quietFor: 600), 0)
    }

    func testPaceLevelsCutDutyCycleThenDecodersThenPause() {
        let b = P.Budgets()
        let p0 = P.pace(level: 0, budgets: b), p1 = P.pace(level: 1, budgets: b), p2 = P.pace(level: 2, budgets: b), p3 = P.pace(level: 3, budgets: b)
        XCTAssertEqual(p0.dutyCycle, 1.0); XCTAssertNil(p0.reason); XCTAssertEqual(p0.decoders, 2); XCTAssertFalse(p0.paused)
        XCTAssertEqual(p1.dutyCycle, 0.6); XCTAssertEqual(p1.decoders, 2); XCTAssertEqual(p1.reason, "facts eased")
        XCTAssertEqual(p2.dutyCycle, 0.25); XCTAssertEqual(p2.decoders, 1); XCTAssertEqual(p2.reason, "facts slowed")
        XCTAssertEqual(p3.dutyCycle, 0.0); XCTAssertTrue(p3.paused); XCTAssertEqual(p3.reason, "facts paused")
        XCTAssertEqual(P.pace(level: 9, budgets: b).level, 3, "clamped")
        XCTAssertEqual(P.pace(level: -1, budgets: b).level, 0)
        XCTAssertEqual(P.pace(level: 2, budgets: b, reason: "facts slowed · thermal").reason, "facts slowed · thermal")
        for (a, b) in zip(P.dutyCycles, P.dutyCycles.dropFirst()) { XCTAssertLessThan(b, a, "every level does less than the one above") }
    }

    // MARK: Seeking

    func testAllIntraSeeksExactlyLongGOPKeyframeFirst() {
        XCTAssertTrue(P.isAllIntra(keyFlags: [true, true, true, true]))
        // An ILCE-7M3 XAVC S clip: a keyframe every 12 frames (measured 2026-10-08).
        XCTAssertFalse(P.isAllIntra(keyFlags: [true] + Array(repeating: false, count: 11) + [true]))
        XCTAssertFalse(P.isAllIntra(keyFlags: []), "nothing sampled is not a claim")
        XCTAssertEqual(P.seek(allIntra: true), .exact)
        XCTAssertEqual(P.seek(allIntra: false), .keyframeFirst)
    }

    // MARK: Profile → transform

    func testTheSevenMarkThreeCardIsNotLog() {
        XCTAssertEqual(P.transform(gamma: "rec709-xvycc", primaries: "rec709"), .display)
        XCTAssertEqual(P.transform(gamma: "rec709", primaries: "rec709"), .display)
    }

    func testSLogProfilesPickTheirTransform() {
        XCTAssertEqual(P.transform(gamma: "s-log3-cine", primaries: "s-gamut3-cine"), .slog3SGamut3Cine)
        XCTAssertEqual(P.transform(gamma: "s-log3", primaries: "s-gamut3-cine"), .slog3SGamut3Cine)
        XCTAssertEqual(P.transform(gamma: "s-log3", primaries: "s-gamut3"), .slog3SGamut3)
        XCTAssertEqual(P.transform(gamma: "S-Log3", primaries: nil), .slog3SGamut3Cine, "case-insensitive; PP8's gamut when none is named")
        XCTAssertEqual(P.transform(gamma: "s-log2", primaries: "s-gamut3"), .slog2SGamut3)
        XCTAssertEqual(P.transform(gamma: "hlg", primaries: "rec2020"), .hlg)
    }

    func testNoSidecarOrAnUnknownValueIsUnknownNeverAGuess() {
        XCTAssertEqual(P.transform(gamma: nil, primaries: nil), .unknown)
        XCTAssertEqual(P.transform(gamma: "", primaries: "rec709"), .unknown)
        XCTAssertEqual(P.transform(gamma: "s-log4", primaries: "rec709"), .unknown)
    }

    func testSidecarNameFollowsSonysLayout() {
        XCTAssertEqual(P.sidecarName(forClip: "C0002.MP4"), "C0002M01.XML")
        XCTAssertEqual(P.sidecarName(forClip: "PRIVATE/M4ROOT/CLIP/C0400.mp4"), "C0400M01.XML")
        XCTAssertNil(P.sidecarName(forClip: "DSC00001.ARW"))
        XCTAssertNil(P.sidecarName(forClip: ".MP4"))
    }

    func testTheProfileQuestionsAnswersMapToTransforms() {
        XCTAssertEqual(P.transform(answer: "S-Log3"), .slog3SGamut3Cine)
        XCTAssertEqual(P.transform(answer: "S-Log2"), .slog2SGamut3)
        XCTAssertEqual(P.transform(answer: "HLG"), .hlg)
        XCTAssertEqual(P.transform(answer: "none"), .display)
        XCTAssertEqual(P.transform(answer: "whatever"), .unknown)
    }

    // MARK: Levels

    func testEachLevelKeepsOneMoreTierAndFurlingNeverDropsFilmstrips() {
        XCTAssertEqual(P.residentTiers(at: .chapters), [.filmstrip])
        XCTAssertEqual(P.residentTiers(at: .takes), [.filmstrip])
        XCTAssertEqual(P.residentTiers(at: .clip), [.filmstrip, .proxy])
        XCTAssertEqual(P.residentTiers(at: .frame), [.filmstrip, .proxy, .frame])
        XCTAssertEqual(P.release(from: .frame, to: .clip), [.frame])
        XCTAssertEqual(P.release(from: .frame, to: .chapters), [.proxy, .frame])
        XCTAssertEqual(P.release(from: .clip, to: .takes), [.proxy])
        XCTAssertEqual(P.release(from: .takes, to: .chapters), [], "filmstrips stay")
        XCTAssertEqual(P.release(from: .chapters, to: .frame), [], "unfurling releases nothing")
        XCTAssertTrue(P.Level.chapters < .frame)
    }

    func testMajorityModeFollowsTheCount() {
        XCTAssertEqual(P.mode(clips: 401, photos: 776), .photos, "the ILCE-7M3 card opens in photos")
        XCTAssertEqual(P.mode(clips: 50, photos: 3), .video)
        XCTAssertEqual(P.mode(clips: 5, photos: 5), .photos, "a tie is the shipped step")
    }

    // MARK: Chips

    func testChipsAreWorstFirstAtMostThreeAndOnlyWhenReady() {
        var f = P.Facts(ev: 1.3, clip: 0.04, crush: 0.09, sharp: 10, pan: 1, shake: 3, bump: true, state: .ready)
        let c = P.chips(for: f, shootMedianSharp: 100)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0], .clipped(0.04), "clipping is the worst")
        XCTAssertEqual(c[1], .crushed(0.09))
        XCTAssertEqual(c[2], .soft)
        let all = P.chips(for: f, shootMedianSharp: 100, max: 9)
        XCTAssertEqual(all.map(\.fact), ["clip", "crush", "sharp", "bump", "ev", "shake"])
        f.state = .pending
        XCTAssertEqual(P.chips(for: f, shootMedianSharp: 100), [], "a pending clip shows no chip")
        f.state = .unreliable
        XCTAssertEqual(P.chips(for: f, shootMedianSharp: 100), [])
    }

    func testChipsBelowTheirLinesAreNotShown() {
        let f = P.Facts(ev: 0.6, clip: 0.01, crush: 0.02, sharp: 90, pan: 2, shake: 1, bump: false, state: .ready)
        XCTAssertEqual(P.chips(for: f, shootMedianSharp: 100), [], "a normal clip has no chips")
    }

    func testPanOnlyWhenShakeIsUnderItsLineAndSoftNeedsTheShootsMedian() {
        let pan = P.Facts(pan: 8, shake: 0.5, state: .ready)
        XCTAssertEqual(P.chips(for: pan), [.pan])
        let both = P.Facts(pan: 8, shake: 3, state: .ready)
        XCTAssertEqual(P.chips(for: both), [.shake], "shake wins; a pan with shake is shake")
        let soft = P.Facts(sharp: 10, state: .ready)
        XCTAssertEqual(P.chips(for: soft), [], "no median yet → soft can't be judged")
        XCTAssertEqual(P.chips(for: soft, shootMedianSharp: 100), [.soft])
        XCTAssertEqual(P.chips(for: soft, shootMedianSharp: 20), [], "10 is not under 35% of 20")
    }

    func testDismissedFactsLeaveTheTileAndTheSweep() {
        let f = P.Facts(clip: 0.04, shake: 3, bump: true, state: .ready)
        XCTAssertEqual(P.chips(for: f).map(\.fact), ["clip", "bump", "shake"])
        XCTAssertEqual(P.chips(for: f, dismissed: ["clip", "shake"]).map(\.fact), ["bump"])
        XCTAssertTrue(P.sweeps(f))
        XCTAssertTrue(P.sweeps(f, dismissed: ["clip"]), "bump still sweeps")
        XCTAssertFalse(P.sweeps(f, dismissed: ["clip", "bump"]), "shake never sweeps")
    }

    func testSweepTakesOnlyTechnicalMissesAndNeverPending() {
        XCTAssertTrue(P.sweeps(P.Facts(clip: 0.03, state: .ready)))
        XCTAssertTrue(P.sweeps(P.Facts(crush: 0.06, state: .ready)))
        XCTAssertTrue(P.sweeps(P.Facts(sharp: 1, state: .ready), shootMedianSharp: 100))
        XCTAssertTrue(P.sweeps(P.Facts(bump: true, state: .ready)))
        XCTAssertFalse(P.sweeps(P.Facts(ev: 2.5, state: .ready)), "exposure is a judgement, not a miss")
        XCTAssertFalse(P.sweeps(P.Facts(pan: 9, shake: 9, state: .ready)))
        XCTAssertFalse(P.sweeps(P.Facts(clip: 0.5, state: .pending)))
    }

    func testRateAndSidecarChips() {
        XCTAssertEqual(P.chips(for: P.Facts(), fps: 119.88, shootFps: 23.976), [.rate("120p")])
        XCTAssertEqual(P.chips(for: P.Facts(), fps: 23.976, shootFps: 23.976), [], "the shoot's own rate is not a chip")
        let c = P.chips(for: P.Facts(clip: 0.5, state: .ready), sidecar: false)
        XCTAssertEqual(c.first, .sidecarMissing, "a missing sidecar outranks everything: the preview can't be trusted")
    }

    func testChipWordsArePlain() {
        XCTAssertEqual(P.Chip.stops(1.3).text, "+1.3 stops")
        XCTAssertEqual(P.Chip.stops(-2.06).text, "−2.1 stops")
        XCTAssertEqual(P.Chip.clipped(0.0449).text, "4% clipped")
        XCTAssertEqual(P.Chip.crushed(0.09).text, "9% crushed")
        XCTAssertEqual(P.Chip.rate("60p").text, "60p")
        XCTAssertEqual(P.Chip.sidecarMissing.text, "sidecar missing")
        let banned = ["ai", "smart", "detect", "suggest", "recommend", "auto", "score", "confidence"]
        for chip: P.Chip in [.soft, .shake, .pan, .bump, .sidecarMissing, .stops(1), .clipped(0.1), .crushed(0.1), .rate("60p")] {
            for b in banned { XCTAssertFalse(chip.text.lowercased().contains(b), "\(chip.text) says \(b)") }
        }
    }

    func testTheAreaSentenceReadsPlainly() {
        XCTAssertEqual(P.areaSentence(mark: "cut", clips: 9, bytes: 4_509_715_660), "cut 9 clips · 4.2 GB")
        XCTAssertEqual(P.areaSentence(mark: "keep", clips: 1, bytes: 1_073_741_824), "keep 1 clip · 1.0 GB")
        XCTAssertEqual(P.areaSentence(mark: "maybe", clips: 38, bytes: 12_992_276_070), "maybe 38 clips · 12 GB")
    }

    // MARK: Skimming

    func testSkimMapsTheTileEdgesToTheClipsEnds() {
        XCTAssertEqual(P.skimTime(x: 0, tileWidth: 320, duration: 12), 0)
        XCTAssertEqual(P.skimTime(x: 160, tileWidth: 320, duration: 12), 6, accuracy: 1e-9)
        XCTAssertEqual(P.skimTime(x: 320, tileWidth: 320, duration: 12), 12, accuracy: 1e-9)
        XCTAssertEqual(P.skimTime(x: 900, tileWidth: 320, duration: 12), 12, "clamped past the edge")
        XCTAssertEqual(P.skimTime(x: -5, tileWidth: 320, duration: 12), 0)
        XCTAssertEqual(P.skimTime(x: 10, tileWidth: 0, duration: 12), 0)
    }

    func testLongClipsSkimApproximatelyOnATile() {
        // A 12 s clip at 320 px: 37 ms per px, precise. The card's longest clip (7752 frames at
        // 23.98, 323 s) at 320 px: 1 s per px, approximate.
        XCTAssertEqual(P.secondsPerPx(tileWidth: 320, duration: 12), 0.0375, accuracy: 1e-9)
        XCTAssertFalse(P.skimIsApproximate(tileWidth: 320, duration: 12))
        XCTAssertTrue(P.skimIsApproximate(tileWidth: 320, duration: 323))
        XCTAssertFalse(P.skimIsApproximate(tileWidth: 320, duration: 80), "80 s at 320 px is exactly the line")
        XCTAssertTrue(P.skimIsApproximate(tileWidth: 240, duration: 80), "a smaller tile tips it over")
        XCTAssertTrue(P.tileWidths.contains(P.tileWidthDefault))
        XCTAssertGreaterThanOrEqual(P.tileWidths.min()!, P.hitPx * 5, "even the small tile has room for 44 px targets")
    }

    func testTheFirstFrameShownIsTheKeyframeBeforeForLongGOP() {
        // The card's clips: a keyframe every 12 frames at 23.976.
        let fps = 24000.0 / 1001
        let t = 5.0                                   // frame 119.88 → 119 → keyframe 108
        XCTAssertEqual(P.firstFrame(for: t, keyframeEvery: 12, fps: fps, allIntra: false), 108 / fps, accuracy: 1e-9)
        XCTAssertEqual(P.firstFrame(for: t, keyframeEvery: 12, fps: fps, allIntra: true), t, "All-Intra: the frame itself")
        XCTAssertEqual(P.firstFrame(for: 0, keyframeEvery: 12, fps: fps, allIntra: false), 0)
        XCTAssertEqual(P.firstFrame(for: t, keyframeEvery: 1, fps: fps, allIntra: false), t, "every frame a keyframe")
        XCTAssertLessThan(P.scrubFirstMs, P.scrubExactMs)
    }

    // MARK: Gates

    func testM1GatesAreTheBriefsNumbers() {
        let g = P.m1Gates
        XCTAssertEqual(g.decodersPeak, 2); XCTAssertEqual(g.fullFramesPeak, 1)
        XCTAssertGreaterThan(g.flags50ClipsSeconds, g.firstRowSeconds)
        XCTAssertEqual(g.proxyDiskMB, Double(P.Budgets().proxyDiskBytes) / 1_048_576, "the disk gate is the disk budget")
        XCTAssertGreaterThanOrEqual(g.decodersPeak, P.budgets(physicalMemory: 64 << 30).decoders, "no budget exceeds its gate")
    }
}
