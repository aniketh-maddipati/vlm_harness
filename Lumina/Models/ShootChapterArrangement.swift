import CoreGraphics
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

    func boardRole(in assets: [AssetRecord]) -> BurstBoardRole {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let marks = assetIDs.map { byID[$0]?.cull ?? .undecided }
        if marks.allSatisfy({ $0 == .reject }) { return .gone }
        if !marks.contains(.undecided) && marks.contains(.keep) { return .hole }
        return .plate
    }
}

enum BurstBoardRole: Equatable, Sendable {
    case plate
    case hole
    case gone
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
    static let sceneGapCeiling: TimeInterval = 15 * 60
    /// A walk this long is always a new chapter, even when the median gap is large.
    static let sceneGapWalk: TimeInterval = 8 * 60

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
            if gap >= threshold {
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
        let medianBased = min(max(median * 3, sceneGapFloor), sceneGapCeiling)
        return min(medianBased, sceneGapWalk)
    }
}

/// Time-proportional gaps on the left chronology rod.
enum ChapterRodLayout {
    static let minGap: CGFloat = 36
    static let maxGap: CGFloat = 140
    static let undatedGap: CGFloat = 52

    struct Mark: Identifiable, Equatable, Sendable {
        var id: String { chapterID }
        var chapterID: String
        var gapAfter: TimeInterval
        var spacingAfter: CGFloat
    }

    static func marks(for chapters: [ShootChapter]) -> [Mark] {
        guard !chapters.isEmpty else { return [] }
        let spacings = gaps(between: chapters)
        return chapters.enumerated().map { index, chapter in
            let next = chapters.indices.contains(index + 1) ? chapters[index + 1] : nil
            let gap: TimeInterval
            if let start = chapter.startedAt, let end = next?.startedAt {
                gap = max(0, end.timeIntervalSince(start))
            } else {
                gap = 0
            }
            return Mark(
                chapterID: chapter.id,
                gapAfter: gap,
                spacingAfter: index < spacings.count ? spacings[index] : 0
            )
        }
    }

    static func gaps(between chapters: [ShootChapter]) -> [CGFloat] {
        guard chapters.count > 1 else { return [] }
        var raw: [TimeInterval] = []
        for index in 0..<(chapters.count - 1) {
            if let start = chapters[index].startedAt, let end = chapters[index + 1].startedAt {
                raw.append(max(0, end.timeIntervalSince(start)))
            } else {
                raw.append(-1)
            }
        }
        let dated = raw.filter { $0 >= 0 }
        let lo = dated.min() ?? 60
        let hi = dated.max() ?? lo
        return raw.map { gap in
            if gap < 0 { return undatedGap }
            if hi <= lo { return minGap }
            let t = (gap - lo) / (hi - lo)
            return minGap + CGFloat(sqrt(t)) * (maxGap - minGap)
        }
    }

    static func elapsedLabel(seconds: TimeInterval) -> String? {
        guard seconds >= sceneWalkSeconds else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return "+ \(minutes) min"
    }

    private static let sceneWalkSeconds: TimeInterval = 8 * 60
}

/// Rest-state packing: large plates first. Density is a lean.
enum ChapterPack {
    static let readable: CGFloat = 160
    static let maxPlate: CGFloat = 280
    static let spacing: CGFloat = 28

    static func columns(
        count: Int,
        width: CGFloat,
        height: CGFloat,
        leanedColumns: Int?
    ) -> (columns: Int, plateHeight: CGFloat, allowScroll: Bool) {
        let count = max(1, count)
        let usableHeight = max(height, readable)
        let usableWidth = max(width, readable)
        if let leaned = leanedColumns {
            let cols = max(1, min(leaned, count))
            let rows = rowCount(count: count, columns: cols)
            let fitted = fittedHeight(rows: rows, height: usableHeight)
            return (cols, min(maxPlate, max(72, fitted)), fitted < readable)
        }

        var bestColumns = 1
        var bestScore: CGFloat = -1
        var fallbackColumns = 1
        var fallbackScore: CGFloat = -1
        for cols in 1...count {
            let rows = rowCount(count: count, columns: cols)
            let plateH = fittedHeight(rows: rows, height: usableHeight)
            let plateW = (usableWidth - spacing * CGFloat(max(0, cols - 1))) / CGFloat(cols)
            let score = min(plateW, plateH)
            if score > fallbackScore {
                fallbackScore = score
                fallbackColumns = cols
            }
            if score >= readable && score > bestScore {
                bestScore = score
                bestColumns = cols
            }
        }
        let cols = bestScore >= 0 ? bestColumns : fallbackColumns
        let rows = rowCount(count: count, columns: cols)
        let fitted = fittedHeight(rows: rows, height: usableHeight)
        return (cols, min(maxPlate, max(96, fitted)), fitted < readable)
    }

    private static func rowCount(count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }

    private static func fittedHeight(rows: Int, height: CGFloat) -> CGFloat {
        (height - spacing * CGFloat(max(0, rows - 1))) / CGFloat(max(1, rows))
    }
}

/// Hold-⌘G glance: same plates, ordered by look, release returns to time.
enum ChapterLookGlance {
    static func orderedIDs(
        bursts: [ShootBurst],
        assets: [AssetRecord],
        focusedBurstID: String?
    ) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var embeddings: [String: [Float]] = [:]
        for burst in bursts {
            guard let coverID = burst.preferredCoverID(in: assets) ?? burst.coverID,
                  let asset = byID[coverID],
                  let path = asset.gridThumbPath ?? asset.thumbPath,
                  let embedding = EmbeddingService.embed(url: URL(fileURLWithPath: path))
            else { continue }
            embeddings[burst.id] = embedding
        }
        guard let focusID = focusedBurstID ?? bursts.first?.id,
              let focusEmb = embeddings[focusID]
        else {
            return bursts.map(\.id)
        }
        return bursts.sorted { lhs, rhs in
            let left = embeddings[lhs.id].map { EmbeddingService.l2Distance(focusEmb, $0) }
                ?? Float.greatestFiniteMagnitude
            let right = embeddings[rhs.id].map { EmbeddingService.l2Distance(focusEmb, $0) }
                ?? Float.greatestFiniteMagnitude
            if left != right { return left < right }
            return lhs.id < rhs.id
        }.map(\.id)
    }
}
