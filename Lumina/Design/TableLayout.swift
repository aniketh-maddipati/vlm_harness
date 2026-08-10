import CoreGraphics
import Foundation

/// Swim-lane grouping and comparison-row geometry for the workbench table.
enum TableLayout {

    struct SwimLaneUnit: Identifiable, Hashable, Sendable {
        let id: String
        /// Lane header timestamp (HH:mm) — nil when this unit is a wrapped continuation only.
        let laneHeader: String?
        /// Scene break label between lanes (`+ 41 min`).
        let sceneBreakBefore: String?
        let groups: [GroupPresentation]
    }

    // MARK: - Swim lanes

    /// Wrapped sibling rows share one lane; the header timestamp lives on the lane, not each wrap page.
    static func swimLaneUnits(from groups: [GroupPresentation]) -> [SwimLaneUnit] {
        guard !groups.isEmpty else { return [] }
        var units: [SwimLaneUnit] = []
        var index = 0
        while index < groups.count {
            let head = groups[index]
            var laneGroups = [head]
            var next = index + 1
            if let siblingID = head.siblingGroupID {
                while next < groups.count,
                      groups[next].isSiblingContinuation,
                      groups[next].siblingGroupID == siblingID {
                    laneGroups.append(groups[next])
                    next += 1
                }
            }
            let sceneBreak = index > 0 ? sceneBreakLabel(from: groups[index - 1], to: head) : nil
            units.append(
                SwimLaneUnit(
                    id: head.siblingGroupID ?? head.id,
                    laneHeader: laneHeader(for: head),
                    sceneBreakBefore: sceneBreak,
                    groups: laneGroups
                )
            )
            index = next
        }
        return units
    }

    static func laneHeader(for group: GroupPresentation) -> String? {
        guard !group.isSiblingContinuation else { return nil }
        return CopyContractBuilder.laneTimestamp(from: group.timeStart)
    }

    static func sceneBreakLabel(from prior: GroupPresentation, to next: GroupPresentation) -> String? {
        guard let end = prior.timeEnd ?? prior.timeStart,
              let start = next.timeStart else { return nil }
        let minutes = Int(start.timeIntervalSince(end) / 60)
        guard minutes >= 1 else { return nil }
        return "+ \(minutes) min"
    }

    static func wrapSharesLane(_ group: GroupPresentation) -> Bool {
        group.isSiblingContinuation && group.siblingGroupID != nil
    }

    // MARK: - Responsive geometry (gap / wrap / compression)

    static func responsivePageSize(twoUp: Bool, availableWidth: CGFloat) -> Int {
        if twoUp { return 2 }
        guard availableWidth > 0 else { return 3 }
        let fits = Int((availableWidth - 60 + 16) / (300 + 16))
        return min(max(fits, 3), 5)
    }

    static func compactVisibleCount(availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return 6 }
        let tile = 104 + 6
        return min(max(Int((availableWidth - 60) / tile), 4), 12)
    }

    /// Justified tile width for an expanded comparison page (gap + mat included).
    static func comparisonTileWidth(
        availableWidth: CGFloat,
        pageSize: Int,
        twoUp: Bool,
        gap: CGFloat = 16,
        mat: CGFloat = 12
    ) -> CGFloat {
        guard availableWidth > 0 else { return twoUp ? 480 : 336 }
        let n = CGFloat(max(pageSize, 1))
        let per = (availableWidth - gap * (n - 1)) / n - mat * 2
        return min(max(per, 280), 720)
    }

    /// Focus boost and neighbor compression when one tile is selected.
    static func comparisonCompression(
        pageSize: Int,
        hasSelection: Bool,
        focusBoost: CGFloat = 1.22
    ) -> (focusScale: CGFloat, neighborScale: CGFloat) {
        let n = CGFloat(max(pageSize, 1))
        guard hasSelection, n > 1 else { return (1, 1) }
        let neighbor = (n - focusBoost) / (n - 1)
        return (focusBoost, neighbor)
    }
}
