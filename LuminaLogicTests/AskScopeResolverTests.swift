import XCTest
@testable import Lumina

/// A scope is a relationship the app resolves, never an ID the model names.
/// Every resolution here must be deterministic: same inputs, same IDs, same order.
final class AskScopeResolverTests: XCTestCase {

    private typealias S = ModelTestSupport

    // A moment of six frames: two bursts of three. `focus` sits in burst A.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let a1 = UUID(), a2 = UUID(), a3 = UUID()
    private let b1 = UUID(), b2 = UUID(), b3 = UUID()
    private let stranger = UUID()

    private func frame(_ id: UUID, seq: Int) -> ShootFrame {
        ShootFrame(id: id.uuidString, coverID: id, assetIDs: [id], startedAt: t0, sequence: seq, prefix: "DSC")
    }

    private func chapters() -> [ShootChapter] {
        let burstA = ShootBurst(id: "A", frames: [frame(a1, seq: 1), frame(a2, seq: 2), frame(a3, seq: 3)], startedAt: t0)
        let burstB = ShootBurst(id: "B", frames: [frame(b1, seq: 4), frame(b2, seq: 5), frame(b3, seq: 6)], startedAt: t0)
        return [ShootChapter(id: "moment", startedAt: t0, assetIDs: [a1, a2, a3, b1, b2, b3], bursts: [burstA, burstB])]
    }

    private func assets(embeddings: [UUID: [Float]] = [:], stats: [UUID: ImageStats] = [:]) -> [AssetRecord] {
        [a1, a2, a3, b1, b2, b3].enumerated().map { index, id in
            S.makeAsset(
                id: id,
                stats: stats[id],
                capturedAt: t0.addingTimeInterval(Double(index) * 2),
                embedding: embeddings[id]
            )
        }
    }

    private func input(
        focus: UUID?,
        embeddings: [UUID: [Float]] = [:],
        stats: [UUID: ImageStats] = [:],
        kept: [UUID] = [],
        selected: [UUID] = [],
        limit: Int = 12
    ) -> AskScopeResolver.Input {
        AskScopeResolver.Input(
            focusedAssetID: focus,
            assets: assets(embeddings: embeddings, stats: stats),
            chapters: chapters(),
            keptAssetIDs: kept,
            selectedAssetIDs: selected,
            similarLimit: limit
        )
    }

    // MARK: - Relationships

    func testFrameIsTheFocusedFrameAlone() {
        XCTAssertEqual(AskScopeResolver.frames(for: .frame, input: input(focus: a2)), [a2])
    }

    func testBurstIsTheFocusedFramesBurstInOrder() {
        XCTAssertEqual(AskScopeResolver.frames(for: .burst, input: input(focus: a2)), [a1, a2, a3])
        XCTAssertEqual(AskScopeResolver.frames(for: .burst, input: input(focus: b3)), [b1, b2, b3])
    }

    func testMomentIsTheWholeChapter() {
        XCTAssertEqual(AskScopeResolver.frames(for: .moment, input: input(focus: b1)), [a1, a2, a3, b1, b2, b3])
    }

    func testSetAndSelectionAreInputsFilteredToKnownFramesWithoutDuplicates() {
        let in_ = input(focus: a1, kept: [b2, stranger, a1, b2], selected: [a3, a3, stranger])
        XCTAssertEqual(AskScopeResolver.frames(for: .set, input: in_), [b2, a1],
                       "unknown frames are dropped, duplicates collapse, order is preserved")
        XCTAssertEqual(AskScopeResolver.frames(for: .selection, input: in_), [a3])
    }

    func testNoFocusResolvesNothingForFocusRelativeScopesButSetAndSelectionStillWork() {
        let in_ = input(focus: nil, kept: [a1], selected: [b1])
        for scope in [AskScope.frame, .burst, .moment, .similar] {
            XCTAssertTrue(AskScopeResolver.frames(for: scope, input: in_).isEmpty, "\(scope)")
        }
        XCTAssertEqual(AskScopeResolver.frames(for: .set, input: in_), [a1])
        XCTAssertEqual(AskScopeResolver.frames(for: .selection, input: in_), [b1])
    }

    func testAFrameOutsideAnyChapterNarrowsToItselfRatherThanWidening() {
        let lone = UUID()
        var in_ = input(focus: lone)
        in_.assets.append(S.makeAsset(id: lone))
        XCTAssertEqual(AskScopeResolver.frames(for: .burst, input: in_), [lone])
        XCTAssertEqual(AskScopeResolver.frames(for: .moment, input: in_), [lone])
    }

    // MARK: - Match excludes the focused frame

    func testMatchExcludesTheFocusedFrameAdjustIncludesIt() {
        let match = AskStep(scope: .burst, action: .syncFromFocus([.light]))
        let adjust = AskStep(scope: .burst, action: .adjust(AskDelta(exposure: 0.2)))
        XCTAssertEqual(AskScopeResolver.resolve(match, input: input(focus: a2)), [a1, a3])
        XCTAssertEqual(AskScopeResolver.resolve(adjust, input: input(focus: a2)), [a1, a2, a3])
    }

    func testMatchOnFrameScopeResolvesToNothing() {
        // Copying the focused frame onto itself is a no-op; it must not write a mark.
        let match = AskStep(scope: .frame, action: .syncFromFocus([.light]))
        XCTAssertTrue(AskScopeResolver.resolve(match, input: input(focus: a2)).isEmpty)
    }

    // MARK: - Similar

    func testSimilarNeverIncludesTheFocusedFrame() {
        let ids = AskScopeResolver.frames(for: .similar, input: input(focus: a1))
        XCTAssertFalse(ids.contains(a1))
        XCTAssertFalse(ids.isEmpty)
    }

    func testSimilarRanksByEmbeddingWhenPresentNearestFirst() {
        let embeddings: [UUID: [Float]] = [
            a1: [1, 0, 0],
            a2: [0.99, 0.1, 0],   // nearest
            b2: [0.7, 0.7, 0],    // middle
            b3: [0, 1, 0],        // far
        ]
        let ids = AskScopeResolver.frames(for: .similar, input: input(focus: a1, embeddings: embeddings))
        XCTAssertEqual(Array(ids.prefix(3)), [a2, b2, b3])
        // Frames without an embedding follow, never interleaved with the embedded tier.
        XCTAssertEqual(Set(ids.suffix(from: 3)), [a3, b1])
    }

    func testSimilarFallsBackToStatisticsAndTimeWithoutEmbeddings() {
        let stats: [UUID: ImageStats] = [
            a1: S.stats(mean: 0.30, bins: S.spikeBins(at: 10)),
            b3: S.stats(mean: 0.30, bins: S.spikeBins(at: 10)),   // identical measurements, far in time
            a2: S.stats(mean: 0.30, bins: S.spikeBins(at: 11)),   // one bin off, adjacent in time
            b1: S.stats(mean: 0.90, bins: S.spikeBins(at: 30)),   // very different
        ]
        let ids = AskScopeResolver.frames(for: .similar, input: input(focus: a1, stats: stats))
        XCTAssertEqual(ids.first, b3, "identical measurements win even across a time gap")
        XCTAssertEqual(ids[1], a2)
        XCTAssertTrue(ids.firstIndex(of: b1)! > ids.firstIndex(of: a2)!)
        XCTAssertEqual(ids.count, 5)
    }

    func testFramesWithoutMeasurementsRankLastNotGuessed() {
        let stats: [UUID: ImageStats] = [
            a1: S.stats(mean: 0.3),
            b1: S.stats(mean: 0.31),
        ]
        let ids = AskScopeResolver.frames(for: .similar, input: input(focus: a1, stats: stats))
        XCTAssertEqual(ids.first, b1, "the one measured frame ranks ahead of every unmeasured one")
    }

    func testSimilarHonorsTheLimit() {
        XCTAssertEqual(AskScopeResolver.frames(for: .similar, input: input(focus: a1, limit: 2)).count, 2)
        XCTAssertTrue(AskScopeResolver.frames(for: .similar, input: input(focus: a1, limit: 0)).isEmpty)
    }

    func testSimilarIsDeterministicUnderTies() {
        // Every candidate identical: order must still be the same run to run, by time then ID.
        let same = S.stats(mean: 0.4)
        let stats = Dictionary(uniqueKeysWithValues: [a1, a2, a3, b1, b2, b3].map { ($0, same) })
        let first = AskScopeResolver.frames(for: .similar, input: input(focus: a1, stats: stats))
        let second = AskScopeResolver.frames(for: .similar, input: input(focus: a1, stats: stats))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, [a2, a3, b1, b2, b3], "ties break by capture time")
    }

    // MARK: - Distances

    func testCosineDistanceIsZeroForSameDirectionAndNilForDegenerate() {
        XCTAssertEqual(AskScopeResolver.cosineDistance([1, 2, 3], [2, 4, 6])!, 0, accuracy: 1e-9)
        XCTAssertEqual(AskScopeResolver.cosineDistance([1, 0], [0, 1])!, 1, accuracy: 1e-9)
        XCTAssertNil(AskScopeResolver.cosineDistance([0, 0], [1, 1]))
        XCTAssertNil(AskScopeResolver.cosineDistance([1, 2], [1, 2, 3]))
        XCTAssertNil(AskScopeResolver.cosineDistance([], []))
    }

    func testStatsDistanceIsBoundedAndZeroForIdentical() {
        let a = S.stats(mean: 0.2, low: 0.1, high: 0.05, bins: S.spikeBins(at: 3))
        let b = S.stats(mean: 0.9, low: 0, high: 0.5, bins: S.spikeBins(at: 28))
        XCTAssertEqual(AskScopeResolver.statsDistance(a, a), 0)
        XCTAssertGreaterThan(AskScopeResolver.statsDistance(a, b), 0.5)
        XCTAssertLessThanOrEqual(AskScopeResolver.statsDistance(a, b), 1)
    }

    func testTimeDistanceSaturatesAtTheWindow() {
        XCTAssertEqual(AskScopeResolver.timeDistance(t0, t0), 0)
        XCTAssertEqual(AskScopeResolver.timeDistance(t0, t0.addingTimeInterval(AskScopeResolver.timeWindow * 5)), 1)
        XCTAssertEqual(AskScopeResolver.timeDistance(t0, nil), 1)
    }
}
