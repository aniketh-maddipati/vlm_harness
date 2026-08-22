import Foundation

struct ShootBurst: Identifiable, Equatable, Sendable {
    /// First member — stable for the life of this run.
    var id: String
    var assetIDs: [UUID]
    var startedAt: Date?
}

struct ShootChapter: Identifiable, Equatable, Sendable {
    var id: String
    var startedAt: Date?
    var assetIDs: [UUID]
    var bursts: [ShootBurst]
}

enum ChapterFocusPreference: Equatable, Sendable {
    case firstUndecided
    case last
}

/// Time-only chapters and bursts. Stem collapse is the next slice.
enum ShootChapterArrangement {
    static let burstGap: TimeInterval = 2
    static let sceneGapFloor: TimeInterval = 3 * 60
    static let sceneGapCeiling: TimeInterval = 45 * 60

    static func arrange(_ assets: [AssetRecord]) -> [ShootChapter] {
        guard !assets.isEmpty else { return [] }
        let sorted = assets.sorted { lhs, rhs in
            (lhs.capturedAt ?? .distantPast) < (rhs.capturedAt ?? .distantPast)
        }
        let dated = sorted.filter { $0.capturedAt != nil }
        let undated = sorted.filter { $0.capturedAt == nil }

        var chapters: [ShootChapter] = sceneGroups(dated).map(makeChapter)
        if !undated.isEmpty {
            chapters.append(makeChapter(undated))
        }
        return chapters
    }

    static func chapter(containing assetID: UUID, in chapters: [ShootChapter]) -> ShootChapter? {
        chapters.first { $0.assetIDs.contains(assetID) }
    }

    private static func makeChapter(_ assets: [AssetRecord]) -> ShootChapter {
        ShootChapter(
            id: assets[0].id.uuidString,
            startedAt: assets[0].capturedAt,
            assetIDs: assets.map(\.id),
            bursts: bursts(in: assets)
        )
    }

    static func bursts(in assets: [AssetRecord]) -> [ShootBurst] {
        guard !assets.isEmpty else { return [] }
        var groups: [[AssetRecord]] = []
        var current: [AssetRecord] = [assets[0]]
        for index in 1..<assets.count {
            let previous = assets[index - 1]
            let next = assets[index]
            let gap: TimeInterval
            if let start = previous.capturedAt, let end = next.capturedAt {
                gap = end.timeIntervalSince(start)
            } else {
                gap = burstGap + 1
            }
            if gap <= burstGap {
                current.append(next)
            } else {
                groups.append(current)
                current = [next]
            }
        }
        groups.append(current)
        return groups.map { members in
            ShootBurst(
                id: members[0].id.uuidString,
                assetIDs: members.map(\.id),
                startedAt: members[0].capturedAt
            )
        }
    }

    private static func sceneGroups(_ dated: [AssetRecord]) -> [[AssetRecord]] {
        guard !dated.isEmpty else { return [] }
        guard dated.count > 1 else { return [dated] }
        let threshold = sceneThreshold(for: dated)
        var groups: [[AssetRecord]] = []
        var current: [AssetRecord] = [dated[0]]
        for index in 1..<dated.count {
            let previous = dated[index - 1]
            let next = dated[index]
            let gap: TimeInterval
            if let start = previous.capturedAt, let end = next.capturedAt {
                gap = end.timeIntervalSince(start)
            } else {
                gap = 0
            }
            if gap > threshold {
                groups.append(current)
                current = [next]
            } else {
                current.append(next)
            }
        }
        groups.append(current)
        return groups
    }

    static func sceneThreshold(for dated: [AssetRecord]) -> TimeInterval {
        var gaps: [TimeInterval] = []
        for index in 1..<dated.count {
            if let start = dated[index - 1].capturedAt, let end = dated[index].capturedAt {
                let gap = end.timeIntervalSince(start)
                if gap > 0 { gaps.append(gap) }
            }
        }
        guard !gaps.isEmpty else { return 12 * 60 }
        gaps.sort()
        let median = gaps[gaps.count / 2]
        return min(max(median * 5, sceneGapFloor), sceneGapCeiling)
    }
}
