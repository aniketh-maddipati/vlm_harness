import Foundation

/// Ranks past shoots so the Open surface can give weight to the one you left
/// and to the large sets — not a flat row of equals.
enum OpenShootArrangement {
    struct Result: Equatable, Sendable {
        var resume: RecentShootSummary?
        var largerSets: [RecentShootSummary]
        var smaller: [RecentShootSummary]
    }

    /// Below this, a shoot never reads as a "set" no matter the rest of the list.
    static let setFloor = 24

    static func arrange(_ shoots: [RecentShootSummary]) -> Result {
        guard !shoots.isEmpty else {
            return Result(resume: nil, largerSets: [], smaller: [])
        }

        let resume = shoots.max(by: { $0.lastOpenedAt < $1.lastOpenedAt })
        let rest = shoots
            .filter { $0.id != resume?.id }
            .sorted(by: Self.impactOrder)

        let peak = max(resume?.assetCount ?? 0, rest.map(\.assetCount).max() ?? 0)
        let cutoff = max(setFloor, Int((Double(peak) * 0.35).rounded()))

        var larger: [RecentShootSummary] = []
        var smaller: [RecentShootSummary] = []
        for shoot in rest {
            if shoot.assetCount >= cutoff, shoot.assetCount >= setFloor {
                larger.append(shoot)
            } else {
                smaller.append(shoot)
            }
        }

        return Result(resume: resume, largerSets: larger, smaller: smaller)
    }

    static func impactOrder(_ a: RecentShootSummary, _ b: RecentShootSummary) -> Bool {
        if a.assetCount != b.assetCount { return a.assetCount > b.assetCount }
        return a.lastOpenedAt > b.lastOpenedAt
    }
}
