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

    /// tileH = clamp(80, 0.115 × gridHeight, 200).
    public static func tileHeight(gridHeight: CGFloat) -> CGFloat { clamp(80, (0.115 * gridHeight).rounded(), 200) }

    /// The box a photo gets, as width / height. Portraits fill their tile; only strips narrower
    /// than 1:2 get a wider box and are shown whole.
    public static func box(_ aspect: CGFloat) -> (aspect: CGFloat, contain: Bool) {
        if aspect >= 1 { return (min(aspect, 1.8), false) }
        if aspect >= 0.5 { return (aspect, false) }
        return (1.0, true)
    }

    /// Lay `aspects` out in rows of `width`. Every row but the last is scaled (within ×0.8…×1.25)
    /// so its tiles fill the width exactly; the last stays at `targetHeight`, left-aligned.
    public static func rows(aspects: [CGFloat], width: CGFloat, targetHeight: CGFloat, gap: CGFloat) -> [Row] {
        var rows: [Row] = [], start = 0, sum: CGFloat = 0
        func close(_ end: Int, last: Bool) {
            let n = end - start; guard n > 0 else { return }
            let gaps = gap * CGFloat(n - 1)
            let scale = last ? 1 : clamp(rowScale.lowerBound, (width - gaps) / max(sum * targetHeight, 1), rowScale.upperBound)
            let tiles = (start..<end).map { i -> Tile in let b = box(aspects[i]); return Tile(index: i, width: b.aspect * targetHeight * scale, contain: b.contain) }
            rows.append(Row(tiles: tiles, height: targetHeight * scale, last: last))
        }
        for i in aspects.indices {
            sum += box(aspects[i]).aspect
            let n = i - start + 1, gaps = gap * CGFloat(n - 1)
            // Close the row once shrinking it to fit would stay within the scale range.
            if sum * targetHeight * rowScale.upperBound + gaps >= width, i < aspects.count - 1 || sum * targetHeight + gaps >= width {
                close(i + 1, last: false); start = i + 1; sum = 0
            }
        }
        close(aspects.count, last: true)
        if let l = rows.indices.last { rows[l].last = true }
        return rows
    }
}
