import Foundation

/// One camera exposure — RAW + JPEG (and leftover `_1` / `-Edit`) share a stem.
struct ShootFrame: Identifiable, Equatable, Sendable {
    var id: String
    var coverID: UUID
    var assetIDs: [UUID]
    var startedAt: Date?
    var sequence: Int?
    var prefix: String
}

struct ShootBurst: Identifiable, Equatable, Sendable {
    var id: String
    var frames: [ShootFrame]
    var startedAt: Date?

    var assetIDs: [UUID] { frames.flatMap(\.assetIDs) }
    var frameCount: Int { frames.count }
    var coverID: UUID? { frames.first?.coverID }

    func preferredCoverID(in assets: [AssetRecord]) -> UUID? {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        if let undecided = frames.first(where: { byID[$0.coverID]?.cull == .undecided }) {
            return undecided.coverID
        }
        return coverID
    }
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

/// Filename stem for pairing siblings (`IMG_2841.CR3` + `IMG_2841.JPG`).
struct CaptureName: Equatable, Sendable {
    var stemKey: String
    var sequence: Int?
    var prefix: String

    static func parse(_ filename: String) -> CaptureName {
        var base = (filename as NSString).deletingPathExtension
        let suffixes = ["-edit", "-edited", " (1)", "-copy", "_copy"]
        for suffix in suffixes {
            if base.lowercased().hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"^(.*\d{3,})[-_]\d$"#),
           let match = regex.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)),
           let kept = Range(match.range(at: 1), in: base) {
            base = String(base[kept])
        }

        guard let digits = lastDigitRun(in: base), digits.count >= 3 else {
            return CaptureName(stemKey: base.lowercased(), sequence: nil, prefix: base)
        }
        let prefix = String(base.dropLast(digits.count))
        return CaptureName(
            stemKey: (prefix + digits).lowercased(),
            sequence: Int(digits),
            prefix: prefix
        )
    }

    private static func lastDigitRun(in text: String) -> String? {
        var run = ""
        for character in text.reversed() {
            if character.isNumber {
                run.insert(character, at: run.startIndex)
            } else if run.isEmpty {
                continue
            } else {
                break
            }
        }
        return run.isEmpty ? nil : run
    }
}

/// Chapters from scene-sized pauses; bursts from stem frames + confirmed runs.
enum ShootChapterArrangement {
    static let burstGap: TimeInterval = 2
    static let sceneGapFloor: TimeInterval = 3 * 60
    static let sceneGapCeiling: TimeInterval = 45 * 60

    static func arrange(_ assets: [AssetRecord]) -> [ShootChapter] {
        let frames = collapseStems(assets)
        guard !frames.isEmpty else { return [] }
        let dated = frames.filter { $0.startedAt != nil }
        let undated = frames.filter { $0.startedAt == nil }

        var chapters: [ShootChapter] = sceneGroups(dated).map(makeChapter)
        if !undated.isEmpty {
            chapters.append(makeChapter(undated))
        }
        return chapters
    }

    static func chapter(containing assetID: UUID, in chapters: [ShootChapter]) -> ShootChapter? {
        chapters.first { $0.assetIDs.contains(assetID) }
    }

    static func collapseStems(_ assets: [AssetRecord]) -> [ShootFrame] {
        let sorted = assets.sorted { lhs, rhs in
            let left = lhs.capturedAt ?? .distantPast
            let right = rhs.capturedAt ?? .distantPast
            if left != right { return left < right }
            return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
        }
        var buckets: [String: [AssetRecord]] = [:]
        var order: [String] = []
        for asset in sorted {
            let key = CaptureName.parse(asset.filename).stemKey
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(asset)
        }
        return order.compactMap { key in
            guard let members = buckets[key], let cover = preferCover(members) else { return nil }
            let name = CaptureName.parse(cover.filename)
            return ShootFrame(
                id: cover.id.uuidString,
                coverID: cover.id,
                assetIDs: members.map(\.id),
                startedAt: members.compactMap(\.capturedAt).min(),
                sequence: name.sequence,
                prefix: name.prefix
            )
        }
    }

    static func bursts(in assets: [AssetRecord]) -> [ShootBurst] {
        bursts(from: collapseStems(assets))
    }

    static func bursts(from frames: [ShootFrame]) -> [ShootBurst] {
        guard !frames.isEmpty else { return [] }
        var groups: [[ShootFrame]] = []
        var current: [ShootFrame] = [frames[0]]
        for index in 1..<frames.count {
            if sameBurst(current[current.count - 1], frames[index]) {
                current.append(frames[index])
            } else {
                groups.append(current)
                current = [frames[index]]
            }
        }
        groups.append(current)
        return groups.map { members in
            ShootBurst(
                id: members[0].id,
                frames: members,
                startedAt: members[0].startedAt
            )
        }
    }

    private static func sameBurst(_ previous: ShootFrame, _ next: ShootFrame) -> Bool {
        if let start = previous.startedAt, let end = next.startedAt {
            return end.timeIntervalSince(start) <= burstGap
        }
        guard previous.startedAt == nil, next.startedAt == nil else { return false }
        guard previous.prefix.caseInsensitiveCompare(next.prefix) == .orderedSame,
              let a = previous.sequence, let b = next.sequence else {
            return false
        }
        return b == a + 1
    }

    private static func makeChapter(_ frames: [ShootFrame]) -> ShootChapter {
        ShootChapter(
            id: frames[0].id,
            startedAt: frames[0].startedAt,
            assetIDs: frames.flatMap(\.assetIDs),
            bursts: bursts(from: frames)
        )
    }

    private static func preferCover(_ members: [AssetRecord]) -> AssetRecord? {
        let previewed = members.filter { $0.thumbPath != nil || $0.gridThumbPath != nil }
        let pool = previewed.isEmpty ? members : previewed
        return pool.min { lhs, rhs in
            let left = lhs.capturedAt ?? .distantPast
            let right = rhs.capturedAt ?? .distantPast
            if left != right { return left < right }
            return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
        }
    }

    private static func sceneGroups(_ dated: [ShootFrame]) -> [[ShootFrame]] {
        guard !dated.isEmpty else { return [] }
        guard dated.count > 1 else { return [dated] }
        let threshold = sceneThreshold(for: dated)
        var groups: [[ShootFrame]] = []
        var current: [ShootFrame] = [dated[0]]
        for index in 1..<dated.count {
            let previous = dated[index - 1]
            let next = dated[index]
            let gap: TimeInterval
            if let start = previous.startedAt, let end = next.startedAt {
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

    static func sceneThreshold(for dated: [ShootFrame]) -> TimeInterval {
        var gaps: [TimeInterval] = []
        for index in 1..<dated.count {
            if let start = dated[index - 1].startedAt, let end = dated[index].startedAt {
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
