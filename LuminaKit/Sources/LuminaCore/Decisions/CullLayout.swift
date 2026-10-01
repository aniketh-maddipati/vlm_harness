import Foundation
import CoreGraphics

// WP-3. The justified Cull grid (LAYOUT_SIZING §5, R-56).

public enum CullLayout {
    public struct Tile: Equatable, Sendable {
        public var index: Int
        public var width: CGFloat
        /// The photo is shown whole inside the box (very narrow strips) instead of filling it.
        public var contain: Bool
    }
    public struct Row: Equatable, Sendable {
        public var tiles: [Tile]
        public var height: CGFloat
        public var last: Bool
        public func width(gap: CGFloat) -> CGFloat { tiles.map(\.width).reduce(0, +) + gap * CGFloat(max(0, tiles.count - 1)) }
    }
    public static let rowScale: ClosedRange<CGFloat> = 0.8...1.25
    /// ⌘+ / ⌘−: ×1.25 per step, 64…320.
    public static let userStep: CGFloat = 1.25
    public static let userRange: ClosedRange<CGFloat> = 64...320

    /// tileH = clamp(80, 0.115 × gridHeight, 200).
    public static func tileHeight(gridHeight: CGFloat) -> CGFloat { clamp(80, (0.115 * gridHeight).rounded(), 200) }

    /// The box a photo gets, as width / height. Portraits fill their tile; only strips narrower
    /// than 1:2 get a wider box and are shown whole. Panoramas are capped at 1.8 and cropped.
    public static func box(_ aspect: CGFloat) -> (aspect: CGFloat, contain: Bool) {
        guard aspect.isFinite, aspect > 0 else { return (1.5, false) }
        if aspect >= 1 { return (min(aspect, 1.8), false) }
        if aspect >= 0.5 { return (aspect, false) }
        return (1.0, true)
    }

    /// Lay `aspects` out in rows of `width`. Every row but the last is scaled so its tiles fill
    /// the width exactly; the last stays at `targetHeight`, left-aligned. The scale stays within
    /// ×0.8…×1.25 whenever a break exists that allows it (always, once the grid is about five
    /// tile heights wide); on a narrower grid the closest break is taken, and a row is never
    /// wider than `width` whatever the mix of shapes (R-1C).
    public static func rows(aspects: [CGFloat], width: CGFloat, targetHeight: CGFloat, gap: CGFloat) -> [Row] {
        guard !aspects.isEmpty else { return [] }
        let width = max(width, 1), target = max(targetHeight, 1), gap = max(gap, 0)
        let boxes = aspects.map(box)
        var rows: [Row] = [], start = 0, sum: CGFloat = 0

        // The scale at which `count` tiles whose box aspects add up to `sum` fill the width.
        func fill(_ sum: CGFloat, _ count: Int) -> CGFloat { (width - gap * CGFloat(count - 1)) / (sum * target) }
        func close(_ end: Int, scale: CGFloat, last: Bool) {
            let tiles = (start..<end).map { Tile(index: $0, width: boxes[$0].aspect * target * scale, contain: boxes[$0].contain) }
            rows.append(Row(tiles: tiles, height: target * scale, last: last))
            start = end; sum = 0
        }
        // How far a scale is from 1, in octaves; anything outside the allowed range loses to anything inside.
        func cost(_ s: CGFloat) -> CGFloat { s <= 0 ? .infinity : abs(log2(s)) + (rowScale.contains(s) ? 0 : 100) }

        var i = 0
        while i < boxes.count {
            let count = i - start, with = fill(sum + boxes[i].aspect, count + 1)
            if with > 1 { sum += boxes[i].aspect; i += 1; continue }     // still short of the width at the target height
            // Tile i takes the row to the width or past it: break after it (shrink) or before it (grow).
            if count == 0 || cost(with) <= cost(fill(sum, count)) {
                close(i + 1, scale: with, last: false); i += 1
            } else {
                close(i, scale: fill(sum, count), last: false)             // tile i starts the next row
            }
        }
        if start < boxes.count { close(boxes.count, scale: min(1, max(fill(sum, boxes.count - start), 0.01)), last: true) }
        rows[rows.count - 1].last = true
        return rows
    }
}
