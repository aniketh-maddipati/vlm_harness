import Foundation

/// The open desk: one continue plate, large sets, and a short quieter row.
/// Harness copies, empty shells, one-frame scratches, and a second run of the
/// same pointed folder never receive a plate.
enum OpenShootArrangement {
    struct Result: Equatable, Sendable {
        var resume: RecentShootSummary?
        var largerSets: [RecentShootSummary]
        var smaller: [RecentShootSummary]
    }

    /// Edited frames against frames still as shot.
    static func editProgress(edited: Int, total: Int) -> (edited: Int, asShot: Int) {
        let edited = min(max(edited, 0), max(total, 0))
        return (edited, max(0, total - edited))
    }

    /// Below this, a shoot never reads as a "set" no matter the rest of the list.
    static let setFloor = 24

    /// Quieter row stops here. Older small shoots stay on disk.
    static let quieterCap = 6

    /// One frame is a scratch. It does not earn a plate.
    static let scratchCeiling = 1

    private static let harnessPrefixes = [
        "lumina-p0-",
        "lumina-authority-",
        "serialized-",
        "cold-open-",
        "auto-",
        "isolation-",
        "version-auto",
    ]

    static func arrange(
        _ shoots: [RecentShootSummary],
        resumeName: String? = nil
    ) -> Result {
        let admitted = collapseDuplicates(shoots.filter(isOnTheDesk))
        guard !admitted.isEmpty else {
            return Result(resume: nil, largerSets: [], smaller: [])
        }

        let resume = chooseResume(from: admitted, resumeName: resumeName)
        let rest = admitted.filter { $0.id != resume?.id }

        let larger = rest
            .filter { $0.assetCount >= setFloor }
            .sorted(by: setOrder)
        let quieter = rest
            .filter { $0.assetCount < setFloor && $0.keepCount > 0 }
            .sorted(by: quietOrder)
            .prefix(quieterCap)

        return Result(
            resume: resume,
            largerSets: larger,
            smaller: Array(quieter)
        )
    }

    static func isOnTheDesk(_ shoot: RecentShootSummary) -> Bool {
        if shoot.assetCount <= scratchCeiling { return false }
        if harnessPrefixes.contains(where: { shoot.name.hasPrefix($0) }) { return false }
        guard let path = shoot.rawFolderPath, !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return true
    }

    /// Same pointed folder is one plate: the copy with keeps, otherwise the newer one.
    static func collapseDuplicates(_ shoots: [RecentShootSummary]) -> [RecentShootSummary] {
        var kept: [String: RecentShootSummary] = [:]
        var order: [String] = []
        for shoot in shoots {
            let key = shoot.rawFolderPath ?? shoot.id.uuidString
            if let existing = kept[key] {
                kept[key] = prefer(shoot, over: existing) ? shoot : existing
            } else {
                kept[key] = shoot
                order.append(key)
            }
        }
        return order.compactMap { kept[$0] }
    }

    private static func chooseResume(
        from admitted: [RecentShootSummary],
        resumeName: String?
    ) -> RecentShootSummary? {
        if let resumeName,
           let named = admitted.first(where: { $0.name == resumeName }) {
            return named
        }
        return admitted.max(by: { $0.lastOpenedAt < $1.lastOpenedAt })
    }

    private static func prefer(_ candidate: RecentShootSummary, over existing: RecentShootSummary) -> Bool {
        if candidate.keepCount != existing.keepCount { return candidate.keepCount > existing.keepCount }
        return candidate.lastOpenedAt > existing.lastOpenedAt
    }

    private static func setOrder(_ a: RecentShootSummary, _ b: RecentShootSummary) -> Bool {
        if a.assetCount != b.assetCount { return a.assetCount > b.assetCount }
        if a.keepCount != b.keepCount { return a.keepCount > b.keepCount }
        return a.lastOpenedAt > b.lastOpenedAt
    }

    private static func quietOrder(_ a: RecentShootSummary, _ b: RecentShootSummary) -> Bool {
        if a.keepCount != b.keepCount { return a.keepCount > b.keepCount }
        return a.lastOpenedAt > b.lastOpenedAt
    }

    static func isHarnessName(_ name: String) -> Bool {
        harnessPrefixes.contains { name.hasPrefix($0) }
    }

    /// Camera dumps, one-letter scratches, and generated suffixes are not titles.
    static func plateTitle(name: String, from: Date?, to: Date?) -> String {
        guard isOpaqueName(name) else { return name }
        if let when = dateSpan(from: from, to: to) { return when }
        return name
    }

    static func isOpaqueName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 2 { return true }
        if trimmed.compare("Untitled", options: .caseInsensitive) == .orderedSame { return true }
        if trimmed.range(of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^\d*DCIM$|^\d+MSDCF$|^PRIVATE$"#, options: .regularExpression) != nil {
            return true
        }
        if let suffix = trimmed.split(separator: "-").last, suffix.count >= 8 {
            let vowels = CharacterSet(charactersIn: "aeiouAEIOU")
            let hasVowel = suffix.unicodeScalars.contains { vowels.contains($0) }
            let alnum = suffix.allSatisfy { $0.isLetter || $0.isNumber }
            if alnum, !hasVowel { return true }
        }
        return false
    }

    static func dateSpan(from: Date?, to: Date?) -> String? {
        guard let from else { return nil }
        let end = to ?? from
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.setLocalizedDateFormatFromTemplate("d MMM")
        let startText = day.string(from: from)
        if Calendar.current.isDate(from, inSameDayAs: end) { return startText }
        return "\(startText) – \(day.string(from: end))"
    }

    struct StillCandidate: Equatable, Sendable {
        var path: String
        var capturedAt: Date?
        var isKeep: Bool
        var quality: Double
    }

    /// One frame from each stretch of the shoot, preferring a keep and a higher score.
    static func sampleStills(_ candidates: [StillCandidate], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let unique = candidates.filter { !$0.path.isEmpty }
        guard !unique.isEmpty else { return [] }
        let keeps = unique.filter(\.isKeep)
        let pool = keeps.count >= min(limit, 3) ? keeps : unique
        let ordered = pool.sorted { lhs, rhs in
            switch (lhs.capturedAt, rhs.capturedAt) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.path < rhs.path
            }
        }
        if ordered.count <= limit { return ordered.map(\.path) }
        let buckets = stride(from: 0, to: limit, by: 1).map { index -> StillCandidate in
            let start = ordered.count * index / limit
            let end = max(start + 1, ordered.count * (index + 1) / limit)
            let slice = ordered[start..<end]
            return slice.max { lhs, rhs in
                if lhs.isKeep != rhs.isKeep { return rhs.isKeep }
                return lhs.quality < rhs.quality
            } ?? ordered[start]
        }
        var seen: Set<String> = []
        return buckets.map(\.path).filter { seen.insert($0).inserted }
    }
}
