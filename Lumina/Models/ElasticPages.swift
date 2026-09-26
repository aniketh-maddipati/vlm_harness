import Foundation

/// The four surfaces a shoot moves through. `open` is the desk (the word "import"
/// is not used). Order is the flip order.
nonisolated enum ElasticSurface: String, CaseIterable, Equatable, Sendable {
    case open
    case chron
    case scroll
    case stitch

    var title: String {
        switch self {
        case .open: return "Open"
        case .chron: return "Chron"
        case .scroll: return "Scroll"
        case .stitch: return "Stitch"
        }
    }

    func flipped() -> ElasticSurface {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Where a pager may step. Geometry of the index only — never a cull, a recipe,
/// or a selection.
nonisolated enum ElasticPages {
    struct Index: Equatable {
        /// 1-based place in the run. `0` when the run is empty.
        var position: Int
        var count: Int

        var canRetreat: Bool { count > 0 && position > 1 }
        var canAdvance: Bool { count > 0 && position > 0 && position < count }

        var label: String {
            guard count > 0, position > 0 else { return "" }
            return "\(position) / \(count)"
        }

        /// The 0-based neighbor of `current`, or nil when the step would leave the run.
        static func neighbor(current: Int, count: Int, step: Int) -> Int? {
            guard count > 0, (0..<count).contains(current), step != 0 else { return nil }
            let next = current + step
            guard (0..<count).contains(next) else { return nil }
            return next
        }
    }
}
