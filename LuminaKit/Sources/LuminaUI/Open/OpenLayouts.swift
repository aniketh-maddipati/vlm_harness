import SwiftUI

// WP-2. Two small layouts for Open: a wrapping row (the card's name + button, the import buttons),
// and the form column's place in the window (LAYOUT_SIZING §5).

/// How narrow a child of `WrapRow` may get before it takes a line of its own; with it set, the
/// child also takes whatever width is left on its line (CSS `flex: 1; min-width`).
private struct WrapFlexKey: LayoutValueKey { static let defaultValue: CGFloat? = nil }

extension View {
    func wrapFlex(minWidth: CGFloat) -> some View { layoutValue(key: WrapFlexKey.self, value: minWidth) }
}

/// Children side by side, centred on their line, moving to the next line when they don't fit.
/// Nothing is ever wider than the row, so a long name wraps instead of pushing sideways (R-1B, R-50).
struct WrapRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Placed { var index: Int; var frame: CGRect }

    private func arrange(_ width: CGFloat?, _ subviews: Subviews) -> (size: CGSize, items: [Placed]) {
        let limit = width ?? .infinity
        // What each child asks for on a line: its minimum if it flexes, its natural width otherwise.
        let asks: [(basis: CGFloat, flex: Bool)] = subviews.map { v in
            if let m = v[WrapFlexKey.self] { return (min(m, limit), true) }
            return (min(v.sizeThatFits(.unspecified).width, limit), false)
        }
        var lines: [[Int]] = [[]], used: CGFloat = 0
        for i in subviews.indices {
            let w = asks[i].basis
            if !lines[lines.count - 1].isEmpty, used + spacing + w > limit + 0.5 { lines.append([]); used = 0 }
            used += (lines[lines.count - 1].isEmpty ? 0 : spacing) + w
            lines[lines.count - 1].append(i)
        }
        var items: [Placed] = [], y: CGFloat = 0, widest: CGFloat = 0
        for line in lines where !line.isEmpty {
            let fixed = line.reduce(CGFloat(0)) { $0 + asks[$1].basis } + spacing * CGFloat(line.count - 1)
            let flexing = line.filter { asks[$0].flex }
            // Left-over width goes to the flexing children; with no width limit they take their natural width.
            let extra: CGFloat = flexing.isEmpty ? 0 : limit.isFinite ? max(0, limit - fixed) / CGFloat(flexing.count) : 0
            var sizes: [CGSize] = []
            for i in line {
                var w = asks[i].basis + (asks[i].flex ? extra : 0)
                if asks[i].flex, !limit.isFinite { w = max(w, subviews[i].sizeThatFits(.unspecified).width) }
                let h = subviews[i].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
                sizes.append(CGSize(width: w, height: h))
            }
            let lineHeight = sizes.map(\.height).max() ?? 0
            var x: CGFloat = 0
            for (k, i) in line.enumerated() {
                items.append(Placed(index: i, frame: CGRect(x: x, y: y + (lineHeight - sizes[k].height) / 2, width: sizes[k].width, height: sizes[k].height)))
                x += sizes[k].width + spacing
            }
            widest = max(widest, x - spacing)
            y += lineHeight + lineSpacing
        }
        return (CGSize(width: limit.isFinite ? limit : widest, height: max(0, y - lineSpacing)), items)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for p in arrange(bounds.width, subviews).items {
            subviews[p.index].place(at: CGPoint(x: bounds.minX + p.frame.minX, y: bounds.minY + p.frame.minY), anchor: .topLeading,
                                    proposal: ProposedViewSize(width: p.frame.width, height: p.frame.height))
        }
    }
}

/// The form column in its scroll view: centred, `column` wide. When everything fits, the space
/// above is a third of what is free, between `top` and `maxTop` and never more than the space
/// below (R-57); when it doesn't fit, the column starts at `top` and the view scrolls.
struct FormColumn: Layout {
    var column: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var maxTop: CGFloat
    /// Height of the scroll view.
    var viewport: CGFloat

    private func contentHeight(_ subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(ProposedViewSize(width: column, height: nil)).height ?? 0
    }
    private func offset(_ h: CGFloat) -> CGFloat {
        let free = viewport - h
        guard free >= top + bottom else { return top }
        return min(maxTop, max(top, free / 3), free / 2)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = contentHeight(subviews), y = offset(h)
        return CGSize(width: proposal.width ?? column, height: max(viewport, y + h + bottom))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let v = subviews.first else { return }
        let h = contentHeight(subviews)
        v.place(at: CGPoint(x: bounds.midX - column / 2, y: bounds.minY + offset(h)), anchor: .topLeading, proposal: ProposedViewSize(width: column, height: h))
    }
}
