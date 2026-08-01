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

    static func scoreAndTier(_ photos: inout [PhotoRecord], keepRate: Double) {
        for index in photos.indices {
            let faceBonus = photos[index].faceDetected ? 0.35 : 0.0
            let sharpComponent = photos[index].sharpness * 0.65
            photos[index].cullScore = min(max(sharpComponent + faceBonus, 0), 1)
        }

        assignBurstHeroes(&photos)

        let sortedIDs = photos.sorted { $0.cullScore > $1.cullScore }.map(\.id)
        let keepCount = max(1, Int((Double(photos.count) * keepRate).rounded()))

        var keepSet = Set(sortedIDs.prefix(keepCount))

        // Always keep burst heroes if they're reasonable.
        for photo in photos where photo.isBurstHero && photo.sharpness >= 0.15 {
            keepSet.insert(photo.id)
        }

        for index in photos.indices {
            let photo = photos[index]
            if photo.sharpness < 0.12 {
                photos[index].tier = .reject
            } else if keepSet.contains(photo.id) {
                photos[index].tier = .keep
            } else if photo.cullScore >= 0.35 {
                photos[index].tier = .maybe
            } else {
                photos[index].tier = .reject
            }
        }

        flagForReview(&photos)
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

    private static func flagForReview(_ photos: inout [PhotoRecord]) {
        let groups = Dictionary(grouping: photos, by: { $0.burstID ?? "single-\($0.id.uuidString)" })

        for index in photos.indices {
            var flagged = false
            let photo = photos[index]

            if photo.tier == .maybe { flagged = true }
            if photo.tier == .keep && photo.sharpness < 0.45 { flagged = true }

            if let burstID = photo.burstID, let group = groups[burstID], group.count > 1 {
                let sorted = group.sorted { $0.cullScore > $1.cullScore }
                if sorted.count >= 2 {
                    let delta = sorted[0].cullScore - sorted[1].cullScore
                    if delta < 0.08 { flagged = true }
                }
                if !photo.isBurstHero && photo.tier == .keep { flagged = true }
            }

            photos[index].isFlagged = flagged
        }
    }
}
