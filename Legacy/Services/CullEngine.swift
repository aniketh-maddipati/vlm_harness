// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Foundation

enum CullEngine {
    static func assignBursts(_ photos: inout [PhotoRecord], gapSeconds: TimeInterval = 2.0) {
        let sorted = photos.sorted {
            ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast)
        }
        var burstIndex = 0
        var previousDate: Date?
        var burstMap: [UUID: String] = [:]

        for photo in sorted {
            if let prev = previousDate,
               let current = photo.capturedAt,
               current.timeIntervalSince(prev) <= gapSeconds {
                // same burst
            } else {
                burstIndex += 1
            }
            burstMap[photo.id] = "burst-\(burstIndex)"
            previousDate = photo.capturedAt
        }

        for index in photos.indices {
            photos[index].burstID = burstMap[photos[index].id]
        }
    }

    /// L1 catalog index — group bursts as sets without Vision embeddings.
    static func assignBurstClusters(_ photos: inout [PhotoRecord]) {
        for index in photos.indices {
            guard let burst = photos[index].burstID else { continue }
            photos[index].clusterID = burst
            photos[index].clusterLabel = "Burst"
        }
    }

    static func scoreAndTier(_ photos: inout [PhotoRecord], keepRate: Double) {
        for index in photos.indices {
            let face = photos[index].faceDetected ? photos[index].faceQuality : 0
            let sharp = photos[index].sharpness
            let exposure = photos[index].exposureHealth
            let aesthetic = photos[index].aesthetic
            let composite = sharp * 0.40 + face * 0.25 + exposure * 0.20 + aesthetic * 0.15
            photos[index].compositeQuality = min(max(composite, 0), 1)
            photos[index].cullScore = photos[index].compositeQuality
        }

        assignBurstHeroes(&photos)
        assignClusterHeroes(&photos)

        let sortedIDs = photos.sorted { $0.cullScore > $1.cullScore }.map(\.id)
        let keepCount = max(1, Int((Double(photos.count) * keepRate).rounded()))
        var keepSet = Set(sortedIDs.prefix(keepCount))

        for photo in photos where photo.isBurstHero && photo.sharpness >= 0.15 {
            keepSet.insert(photo.id)
        }
        for photo in photos where photo.isClusterHero && photo.sharpness >= 0.20 {
            keepSet.insert(photo.id)
        }

        for index in photos.indices {
            if photos[index].userDecidedAt == nil {
                photos[index].proposedTier = nil
            }
            let photo = photos[index]
            if photo.sharpness < 0.12 {
                photos[index].tier = .reject
            } else if keepSet.contains(photo.id) {
                photos[index].tier = .keep
            } else if photo.cullScore >= 0.35 {
                photos[index].tier = .unranked
            } else {
                photos[index].tier = .reject
            }
        }

        assignConfidence(&photos)
    }

    static func assignConfidence(_ photos: inout [PhotoRecord]) {
        let burstGroups = Dictionary(grouping: photos, by: { $0.burstID ?? "single-\($0.id.uuidString)" })

        for index in photos.indices {
            var flagged = false
            var kind: UncertaintyKind = .none
            var why: String?
            let photo = photos[index]
            let decisionTier = photo.proposedTier ?? photo.tier

            if photo.userDecidedAt != nil {
                photos[index].cullConfidence = 1
                photos[index].isFlagged = false
                photos[index].uncertaintyKind = .none
                photos[index].whyUncertain = nil
                continue
            }

            // High-confidence reject
            if photo.sharpness < 0.12 {
                photos[index].cullConfidence = 0.95
                photos[index].isFlagged = false
                photos[index].uncertaintyKind = .none
                photos[index].whyUncertain = nil
                if photo.userDecidedAt == nil {
                    photos[index].proposedTier = decisionTier
                    photos[index].tier = .unranked
                }
                continue
            }

            if decisionTier == .unranked && photo.cullScore >= 0.35 {
                flagged = true
                kind = .cullBorderline
                why = "Borderline quality \(String(format: "%.2f", photo.cullScore))"
            }
            if decisionTier == .keep && photo.sharpness < 0.45 {
                flagged = true
                kind = .cullBorderline
                why = "Keep with soft sharpness \(String(format: "%.2f", photo.sharpness))"
            }

            if let burstID = photo.burstID, let group = burstGroups[burstID], group.count > 1 {
                let sorted = group.sorted { $0.cullScore > $1.cullScore }
                if sorted.count >= 2 {
                    let delta = sorted[0].cullScore - sorted[1].cullScore
                    if delta < 0.08 {
                        flagged = true
                        kind = .cullTie
                        why = "Burst tie (\(String(format: "%.2f", sorted[0].cullScore)) vs \(String(format: "%.2f", sorted[1].cullScore)))"
                    }
                }
                if !photo.isBurstHero && decisionTier == .keep {
                    flagged = true
                    kind = .cullTie
                    why = why ?? "Non-hero keep in burst"
                }
            }

            if decisionTier == .keep, let recipe = photo.recipe, recipe.confidence < 0.55 {
                flagged = true
                kind = .editLowConfidence
                why = "Low edit confidence \(String(format: "%.2f", recipe.confidence))"
            }

            // Confidence: high when not flagged
            if flagged {
                photos[index].cullConfidence = kind == .cullTie ? 0.45 : 0.55
            } else if decisionTier == .keep {
                photos[index].cullConfidence = 0.85 + min(photo.cullScore * 0.1, 0.1)
            } else {
                photos[index].cullConfidence = 0.80
            }

            photos[index].editConfidence = photo.recipe?.confidence ?? 1.0
            photos[index].isFlagged = flagged
            photos[index].uncertaintyKind = kind
            photos[index].whyUncertain = why

            // Auditable calls stay proposals until a pile acceptance materializes them.
            if photo.userDecidedAt == nil, flagged || photo.sharpness < 0.12 {
                photos[index].proposedTier = decisionTier
                photos[index].tier = .unranked
            }
        }
    }

    private static func assignBurstHeroes(_ photos: inout [PhotoRecord]) {
        let groups = Dictionary(grouping: photos, by: { $0.burstID ?? "single-\($0.id.uuidString)" })
        for (burstID, group) in groups {
            guard let heroID = group.max(by: { $0.cullScore < $1.cullScore })?.id else { continue }
            for index in photos.indices where photos[index].burstID == burstID {
                photos[index].isBurstHero = photos[index].id == heroID
            }
        }
    }

    private static func assignClusterHeroes(_ photos: inout [PhotoRecord]) {
        let groups = Dictionary(grouping: photos, by: { $0.clusterID ?? "none" })
        for (clusterID, group) in groups {
            guard clusterID != "none",
                  let heroID = group.max(by: { $0.cullScore < $1.cullScore })?.id else { continue }
            for index in photos.indices where photos[index].clusterID == clusterID {
                photos[index].isClusterHero = photos[index].id == heroID
            }
        }
    }

    static func sorted(_ photos: [PhotoRecord], by mode: SortMode) -> [PhotoRecord] {
        switch mode {
        case .similar:
            return photos.sorted { a, b in
                let ca = a.clusterID ?? "~"
                let cb = b.clusterID ?? "~"
                if ca != cb { return ca < cb }
                return a.cullScore > b.cullScore
            }
        case .sharpest:
            return photos.sorted { $0.sharpness > $1.sharpness }
        case .quality:
            return photos.sorted { $0.compositeQuality > $1.compositeQuality }
        case .taste:
            return photos.sorted { $0.tasteMatch > $1.tasteMatch }
        case .all:
            return photos.sorted { ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast) }
        }
    }

    static func clusters(from photos: [PhotoRecord]) -> [PhotoCluster] {
        let clustered = photos.compactMap { photo -> (String, PhotoRecord)? in
            guard let clusterID = photo.clusterID else { return nil }
            return (clusterID, photo)
        }
        let groups = Dictionary(grouping: clustered, by: \.0).mapValues { $0.map(\.1) }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], group.count >= 1 else { return nil }
            let hero = group.first(where: \.isClusterHero)?.id ?? group.max(by: { $0.cullScore < $1.cullScore })?.id
            let faces = group.filter(\.faceDetected).count
            let dates = group.compactMap(\.capturedAt).sorted()
            var span: TimeInterval?
            if let first = dates.first, let last = dates.last {
                span = last.timeIntervalSince(first)
            }
            let why = whyGrouped(group: group, faces: faces, span: span)
            return PhotoCluster(
                id: key,
                label: group.first?.clusterLabel ?? key,
                whyGrouped: why,
                photoIDs: group.sorted { $0.cullScore > $1.cullScore }.map(\.id),
                heroID: hero,
                faceCount: faces,
                timeSpanSeconds: span
            )
        }
        .sorted { $0.photoIDs.count > $1.photoIDs.count }
    }

    private static func whyGrouped(group: [PhotoRecord], faces: Int, span: TimeInterval?) -> String {
        var parts: [String] = []
        let n = group.count
        if n == 1 {
            parts.append("Single frame — no near duplicates")
        } else if group.allSatisfy({ $0.burstID != nil && $0.burstID == group[0].burstID }) {
            parts.append("Same burst (\(n) frames within ~2s)")
        } else {
            parts.append("Similar composition / color (\(n) frames)")
        }
        if faces > 0 {
            parts.append(faces == n ? "faces in all" : "faces in \(faces)/\(n)")
        }
        if let span {
            if span < 3 {
                parts.append("shot within \(Int(span * 1000))ms")
            } else if span < 60 {
                parts.append("spans \(Int(span))s")
            } else {
                parts.append("spans \(Int(span / 60))m")
            }
        }
        let avgSharp = group.map(\.sharpness).reduce(0, +) / Double(max(n, 1))
        parts.append(String(format: "avg sharpness %.2f", avgSharp))
        return parts.joined(separator: " · ")
    }
}
