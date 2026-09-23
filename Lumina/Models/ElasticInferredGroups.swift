import Foundation

/// One inferred group on the flags peek: why these frames belong together, and which
/// of them `G` would take to the set. Pure data — the session measures, this decides.
nonisolated struct ElasticInferredGroup: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case sameBurst = "same burst"
        case sameScene = "same scene"
        case sameSubject = "same subject"
    }

    var id: String
    var kind: Kind
    /// The facts, in one line: `5 frames in 1.6 s at 05:58 · leader is sharpest`.
    var reason: String
    /// What `G` takes, in words: `1 of 5` · `all` · `the sharp ones`.
    var pick: String
    var frameIDs: [UUID]
    var takeIDs: [UUID]
    /// A word on a frame — `sharpest` on a burst leader.
    var tags: [UUID: String]

    /// `G takes 3 (all)`, or just the pick when there is nothing to take.
    var takeLine: String {
        takeIDs.isEmpty ? pick : "G takes \(takeIDs.count) (\(pick))"
    }
}

/// The inference behind the flags peek. Everything here is derived from what is already
/// known about the shoot — bursts, moments, the measured sharpness of a thumbnail, and
/// the same on-device embedding `ChapterLookGlance` orders by — and nothing here writes
/// a decision. `G` does that, through the session's one command boundary.
nonisolated enum ElasticInferredGroups {

    /// What the session has measured so far. Missing entries mean "not yet", never "zero".
    struct Measurements: Equatable, Sendable {
        /// Normalised 0…1, higher is sharper (`BlurScorer`), off the grid thumbnail.
        var sharpness: [UUID: Double] = [:]
        /// Vision feature print, off the same thumbnail (`EmbeddingService.embed`).
        var embeddings: [UUID: [Float]] = [:]
    }

    /// What the caller knows that the arrangement does not.
    struct Context {
        var isPhone: (UUID) -> Bool
        var momentTimeLabel: (ShootChapter) -> String
        var momentLightWord: (ShootChapter) -> String
    }

    /// Below this a frame reads as soft. The import pipeline's own reject floor.
    static let softSharpness = 0.15
    /// Clipping past this share of the frame earns a `clips` flag.
    static let clipFlagFraction = 0.03
    /// Exposure this far from the burst's median earns a `drift` flag.
    static let driftStops = 0.6
    /// Two frames closer than this in embedding space share a subject.
    static let subjectDistance: Float = 0.35
    /// In a subject group, `G` takes the frames within this share of the sharpest.
    static let subjectSharpShare = 0.85

    // MARK: - Groups

    static func infer(
        chapters: [ShootChapter],
        assets: [AssetRecord],
        measurements: Measurements,
        context: Context
    ) -> [ElasticInferredGroup] {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var groups: [ElasticInferredGroup] = []
        var used: Set<UUID> = []

        // Same burst — the leader is the sharpest frame once that is measured.
        for chapter in chapters {
            for burst in chapter.bursts where burst.frameCount > 1 {
                let covers = burst.frames.map(\.coverID)
                let scores = covers.compactMap { measurements.sharpness[$0] }
                let measured = scores.count == covers.count
                let leader: UUID
                if measured, let best = covers.max(by: {
                    (measurements.sharpness[$0] ?? 0) < (measurements.sharpness[$1] ?? 0)
                }) {
                    leader = best
                } else {
                    leader = burst.preferredCoverID(in: assets) ?? covers[0]
                }
                let span = burstSpanSeconds(burst)
                let reason = "\(covers.count) frames in \(span) s at \(context.momentTimeLabel(chapter))"
                    + (measured ? " · leader is sharpest" : " · leader is the first frame")
                groups.append(ElasticInferredGroup(
                    id: "burst:\(burst.id)",
                    kind: .sameBurst,
                    reason: reason,
                    pick: "1 of \(covers.count)",
                    frameIDs: covers,
                    takeIDs: [leader],
                    tags: measured ? [leader: "sharpest"] : [:]
                ))
                used.formUnion(covers)
            }
        }

        // Same scene — the singles of one moment, taken whole (phones step back).
        for chapter in chapters {
            let singles = chapter.bursts
                .filter { $0.frameCount == 1 }
                .compactMap(\.coverID)
                .filter { !used.contains($0) }
            guard singles.count >= 2 else { continue }
            let cameras = singles.filter { !context.isPhone($0) }
            let take = cameras.isEmpty ? singles : cameras
            let start = chapter.startedAt ?? .distantPast
            let within = singles
                .compactMap { byID[$0]?.capturedAt }
                .map { $0.timeIntervalSince(start) }
                .max() ?? 0
            groups.append(ElasticInferredGroup(
                id: "scene:\(chapter.id)",
                kind: .sameScene,
                reason: "\(singles.count) frames within \(Int(within.rounded())) s · "
                    + "\(context.momentLightWord(chapter)) · same place, different framing",
                pick: "all",
                frameIDs: singles,
                takeIDs: take,
                tags: [:]
            ))
            used.formUnion(singles)
        }

        // Same subject — one look recurring across moments, by the same embedding
        // distance the look glance orders by.
        groups.append(contentsOf: subjectGroups(
            chapters: chapters,
            assets: assets,
            measurements: measurements,
            context: context
        ))

        return groups
    }

    private static func burstSpanSeconds(_ burst: ShootBurst) -> String {
        guard let first = burst.frames.first?.startedAt, let last = burst.frames.last?.startedAt else {
            return "0.0"
        }
        return String(format: "%.1f", max(0, last.timeIntervalSince(first)))
    }

    private static func subjectGroups(
        chapters: [ShootChapter],
        assets: [AssetRecord],
        measurements: Measurements,
        context: Context
    ) -> [ElasticInferredGroup] {
        // One representative per burst — its first frame, so a mark on the leader
        // never moves the representative and the groups never shift under `G`.
        var members: [(id: UUID, chapter: String)] = []
        for chapter in chapters {
            for burst in chapter.bursts {
                guard let cover = burst.coverID,
                      !context.isPhone(cover),
                      measurements.embeddings[cover] != nil else { continue }
                members.append((cover, chapter.id))
            }
        }
        guard members.count >= 2 else { return [] }

        // Greedy: a frame joins the first cluster whose seed it is close to.
        var clusters: [[(id: UUID, chapter: String)]] = []
        for member in members {
            guard let embedding = measurements.embeddings[member.id] else { continue }
            if let index = clusters.firstIndex(where: { cluster in
                guard let seed = measurements.embeddings[cluster[0].id] else { return false }
                return EmbeddingService.l2Distance(seed, embedding) < subjectDistance
            }) {
                clusters[index].append(member)
            } else {
                clusters.append([member])
            }
        }

        return clusters.compactMap { cluster in
            let moments = Set(cluster.map(\.chapter))
            guard cluster.count >= 2, moments.count >= 2 else { return nil }
            let ids = cluster.map(\.id)
            let scores = ids.compactMap { measurements.sharpness[$0] }
            let take: [UUID]
            if scores.count == ids.count, let best = scores.max(), best > 0 {
                take = ids.filter { (measurements.sharpness[$0] ?? 0) >= best * subjectSharpShare }
            } else {
                take = []
            }
            return ElasticInferredGroup(
                id: "subject:\(ids[0].uuidString)",
                kind: .sameSubject,
                reason: "\(ids.count) frames across \(moments.count) moments · one look recurs",
                pick: take.isEmpty ? "sharpness not measured yet" : "the sharp ones",
                frameIDs: ids,
                takeIDs: take,
                tags: [:]
            )
        }
    }

    // MARK: - Flags

    /// `soft · clips · drift` — what a frame needs a hand with, or nil when nothing.
    static func flags(
        for asset: AssetRecord,
        burstMates: [AssetRecord],
        measurements: Measurements
    ) -> String? {
        var flags: [String] = []
        if let sharpness = measurements.sharpness[asset.id], sharpness < softSharpness {
            flags.append("soft")
        }
        if let stats = asset.imageStats,
           stats.highlightClipFraction > clipFlagFraction || stats.shadowClipFraction > clipFlagFraction {
            flags.append("clips")
        }
        if burstMates.count > 1 {
            let exposures = burstMates.map { $0.recipe?.exposure ?? 0 }.sorted()
            let median = exposures[exposures.count / 2]
            if abs((asset.recipe?.exposure ?? 0) - median) > driftStops {
                flags.append("drift")
            }
        }
        return flags.isEmpty ? nil : flags.joined(separator: " · ")
    }
}
