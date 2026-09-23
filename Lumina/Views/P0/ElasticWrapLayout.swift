import SwiftUI

/// Frame groups wrapped into rows: a burst gap between rows, a scene gap between
/// groups.
///
/// This measured every subview three times per layout pass: once arranging inside
/// `sizeThatFits`, once arranging again inside `placeSubviews`, and once more
/// while placing each one. Now a pass measures each group once and `placeSubviews`
/// reuses that, along with the row arrangement when the width has not moved.
///
/// The measurement is deliberately **not** kept across passes. The groups are
/// fixed-size — a lone frame is `ElasticLayout.tile` wide, a collapsed stack is
/// that plus its trailing peek, an open burst is its frames at `tileInOpenBurst`
/// with gaps — but leaning on a burst changes one group from the second shape to
/// the third **without adding or removing a subview**. A size cached across passes
/// would still be the collapsed one, and the open burst would lay out on top of
/// its neighbour. Cheap and right beats cheaper and occasionally wrong.
struct ElasticWrapLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    struct Cache {
        var sizes: [CGSize]
        /// Rows as last arranged, and the width they were arranged for.
        var rows: [Row]
        var arrangedWidth: CGFloat?
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: [], rows: [], arrangedWidth: nil)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache(sizes: [], rows: [], arrangedWidth: nil)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        refresh(&cache, subviews: subviews)
        let rows = arrange(width: proposal.width ?? .infinity, cache: &cache)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // `sizeThatFits` runs first in an ordinary pass and has already measured;
        // this only measures if it somehow did not.
        if cache.sizes.count != subviews.count {
            refresh(&cache, subviews: subviews)
        }
        var y = bounds.minY
        for row in arrange(width: bounds.width, cache: &cache) {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    /// One measurement of every group, for this pass.
    private func refresh(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.rows = []
        cache.arrangedWidth = nil
    }

    /// Rows for `width`, reusing the last arrangement when the width has not moved.
    private func arrange(width: CGFloat, cache: inout Cache) -> [Row] {
        if let arrangedWidth = cache.arrangedWidth, arrangedWidth == width {
            return cache.rows
        }

        var rows: [Row] = []
        var row = Row()
        for index in cache.sizes.indices {
            let size = cache.sizes[index]
            let needed = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }

        cache.rows = rows
        cache.arrangedWidth = width
        return rows
    }
}
