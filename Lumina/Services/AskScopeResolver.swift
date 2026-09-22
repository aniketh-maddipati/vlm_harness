import Foundation

/// Turns a named relationship into concrete frames.
///
/// The planner picks an `AskScope`; this resolves it from data the app already owns.
/// Pure and deterministic — the same inputs always give the same IDs in the same
/// order — so the plan a photographer previews is the plan that gets applied.
///
/// The kept set and the selection arrive as **inputs** rather than being read from a
/// session, because `finalSetAssetIDs` lives only on the UI branch. This type has to
/// compile and be provable without it.
nonisolated enum AskScopeResolver {

    /// Everything a resolution needs. `chapters` defaults to arranging `assets`, but
    /// tests (and callers that already have an arrangement) can pass one in.
    nonisolated struct Input: Sendable {
        var focusedAssetID: UUID?
        var assets: [AssetRecord]
        var chapters: [ShootChapter]
        var keptAssetIDs: [UUID]
        var selectedAssetIDs: [UUID]
        /// How many neighbours `.similar` may reach, focused frame excluded.
        var similarLimit: Int

        init(
            focusedAssetID: UUID?,
            assets: [AssetRecord],
            chapters: [ShootChapter]? = nil,
            keptAssetIDs: [UUID] = [],
            selectedAssetIDs: [UUID] = [],
            similarLimit: Int = 12
        ) {
            self.focusedAssetID = focusedAssetID
            self.assets = assets
            self.chapters = chapters ?? ShootChapterArrangement.arrange(assets)
            self.keptAssetIDs = keptAssetIDs
            self.selectedAssetIDs = selectedAssetIDs
            self.similarLimit = similarLimit
        }
    }

    /// Frames a step touches, in apply order.
    ///
    /// `syncFromFocus` copies the focused frame onto the scope, so the focused frame
    /// itself is excluded: including it would write a mark that changes nothing.
    static func resolve(_ step: AskStep, input: Input) -> [UUID] {
        let ids = frames(for: step.scope, input: input)
        if case .syncFromFocus = step.action, let focus = input.focusedAssetID {
            return ids.filter { $0 != focus }
        }
        return ids
    }

    static func frames(for scope: AskScope, input: Input) -> [UUID] {
        switch scope {
        case .set:
            return known(input.keptAssetIDs, in: input)
        case .selection:
            return known(input.selectedAssetIDs, in: input)
        case .frame:
            return input.focusedAssetID.map { [$0] } ?? []
        case .burst:
            guard let focus = input.focusedAssetID else { return [] }
            return burstIDs(containing: focus, input: input)
        case .moment:
            guard let focus = input.focusedAssetID else { return [] }
            return momentIDs(containing: focus, input: input)
        case .similar:
            guard let focus = input.focusedAssetID else { return [] }
            return similarIDs(to: focus, input: input)
        }
    }

    // MARK: - Relationships

    /// The focused frame's burst. Falls back to the frame alone rather than widening:
    /// a scope that can't be resolved must never reach more frames than asked for.
    static func burstIDs(containing focus: UUID, input: Input) -> [UUID] {
        guard let chapter = ShootChapterArrangement.chapter(containing: focus, in: input.chapters),
              let burst = chapter.bursts.first(where: { $0.assetIDs.contains(focus) })
        else { return [focus] }
        return known(burst.assetIDs, in: input)
    }

    /// The focused frame's moment (chapter). Same narrowing fallback as `burstIDs`.
    static func momentIDs(containing focus: UUID, input: Input) -> [UUID] {
        guard let chapter = ShootChapterArrangement.chapter(containing: focus, in: input.chapters)
        else { return [focus] }
        return known(chapter.assetIDs, in: input)
    }

    /// Frames that look like the focused one, nearest first, focused frame excluded.
    ///
    /// Candidates come from the focused frame's moment — "similar" means similar
    /// *here*, not across the whole card.
    ///
    /// Ranking is deliberately **two-tier**. An embedding distance and an image-statistics
    /// distance are not comparable numbers, so frames carrying an embedding are ranked
    /// among themselves first, and frames without one follow, ranked by statistics and
    /// time. Blending the two scales into one score would invent a precision that
    /// neither metric has.
    static func similarIDs(to focus: UUID, input: Input) -> [UUID] {
        let byID = Dictionary(input.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let focusAsset = byID[focus] else { return [] }
        let candidates = momentIDs(containing: focus, input: input)
            .filter { $0 != focus }
            .compactMap { byID[$0] }
        guard !candidates.isEmpty else { return [] }

        var embedded: [(asset: AssetRecord, score: Double)] = []
        var measured: [(asset: AssetRecord, score: Double)] = []

        let focusEmbedding = focusAsset.embedding
        for candidate in candidates {
            if let focusEmbedding, let other = candidate.embedding,
               let distance = cosineDistance(focusEmbedding, other) {
                embedded.append((candidate, distance))
            } else {
                measured.append((candidate, statisticalDistance(focusAsset, candidate)))
            }
        }

        let ranked = sortedByScore(embedded) + sortedByScore(measured)
        return ranked.prefix(max(0, input.similarLimit)).map(\.asset.id)
    }

    // MARK: - Distances

    /// 0 = identical direction. Nil when either vector is degenerate, so the caller
    /// falls back to measurements instead of ranking on a meaningless number.
    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            let x = Double(a[i]), y = Double(b[i])
            dot += x * y; normA += x * x; normB += y * y
        }
        guard normA > 1e-12, normB > 1e-12 else { return nil }
        let cosine = dot / (normA.squareRoot() * normB.squareRoot())
        return 1 - min(max(cosine, -1), 1)
    }

    /// Weighting between how alike two frames measure and how close together they were
    /// shot. Time is a weak signal on its own — two frames minutes apart can be the same
    /// setup — so it only breaks ties between frames that already measure alike.
    static let statisticsWeight = 0.7
    static let timeWeight = 0.3
    /// Beyond this gap, time proximity carries no further information.
    static let timeWindow: TimeInterval = 300

    /// 0 = indistinguishable by the measurements the engine already keeps.
    /// Frames with no `ImageStats` score as maximally distant rather than being
    /// guessed at — the same refusal `applyAuto` makes.
    static func statisticalDistance(_ a: AssetRecord, _ b: AssetRecord) -> Double {
        let time = timeDistance(a.capturedAt, b.capturedAt)
        guard let statsA = a.imageStats, let statsB = b.imageStats else {
            return statisticsWeight * 1.0 + timeWeight * time
        }
        return statisticsWeight * statsDistance(statsA, statsB) + timeWeight * time
    }

    /// Histogram shape dominates; mean and the two clip fractions refine it. All terms
    /// are already 0…1, so the result is too.
    static func statsDistance(_ a: ImageStats, _ b: ImageStats) -> Double {
        let histogram = histogramDistance(a, b)
        let mean = abs(a.mean - b.mean)
        let low = abs(a.shadowClipFraction - b.shadowClipFraction)
        let high = abs(a.highlightClipFraction - b.highlightClipFraction)
        return min(1, 0.5 * histogram + 0.3 * mean + 0.1 * low + 0.1 * high)
    }

    /// L1 between the two normalized histograms, halved so it lands in 0…1.
    static func histogramDistance(_ a: ImageStats, _ b: ImageStats) -> Double {
        guard a.luminanceBins.count == b.luminanceBins.count else { return 1 }
        let totalA = Double(a.sampleCount), totalB = Double(b.sampleCount)
        guard totalA > 0, totalB > 0 else { return 1 }
        var sum = 0.0
        for i in 0..<a.luminanceBins.count {
            sum += abs(Double(a.luminanceBins[i]) / totalA - Double(b.luminanceBins[i]) / totalB)
        }
        return min(1, sum / 2)
    }

    /// 0 = same instant, 1 = `timeWindow` apart or more, or either date missing.
    static func timeDistance(_ a: Date?, _ b: Date?) -> Double {
        guard let a, let b else { return 1 }
        return min(1, abs(a.timeIntervalSince(b)) / timeWindow)
    }

    // MARK: - Ordering

    /// Total order: score, then capture time, then ID. Two frames that measure
    /// identically must still rank in the same order on every machine and every run.
    private static func sortedByScore(
        _ entries: [(asset: AssetRecord, score: Double)]
    ) -> [(asset: AssetRecord, score: Double)] {
        entries.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            let lhsDate = lhs.asset.capturedAt ?? .distantPast
            let rhsDate = rhs.asset.capturedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.asset.id.uuidString < rhs.asset.id.uuidString
        }
    }

    /// Keeps only IDs this shoot actually has, in the order given, without duplicates.
    /// A scope can never name a frame that isn't there.
    private static func known(_ ids: [UUID], in input: Input) -> [UUID] {
        let present = Set(input.assets.map(\.id))
        var seen = Set<UUID>()
        return ids.filter { present.contains($0) && seen.insert($0).inserted }
    }
}
