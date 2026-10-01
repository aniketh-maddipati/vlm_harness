import Foundation
import CoreGraphics

// WP-3. The whole Cull grid as positions: scene headers and justified rows, top to bottom, each
// with its y and height. The view draws only the items inside the visible rectangle, so a
// 5,000-photo shoot costs the same per frame as a 100-photo one, and the scroll offset that
// brings a photo into view is known exactly instead of estimated.

public struct CullGrid: Sendable {
    /// Everything the layout depends on. Two equal values give the same grid for the same photos.
    public struct Config: Equatable, Sendable {
        /// Width the rows fill (the grid column minus its side padding).
        public var width: CGFloat
        public var tileHeight: CGFloat
        public var gap: CGFloat
        public var sceneGap: CGFloat
        public var headerHeight: CGFloat
        /// Space between a scene's header and its first row.
        public var headerGap: CGFloat
        public var top: CGFloat
        public var bottom: CGFloat
        /// Height of the "Copying n of N…" line under the last scene; 0 when it isn't shown.
        public var copyLine: CGFloat

        public init(width: CGFloat, tileHeight: CGFloat, gap: CGFloat = 6, sceneGap: CGFloat = 20, headerHeight: CGFloat = 24,
                    headerGap: CGFloat = 8, top: CGFloat = 16, bottom: CGFloat = 24, copyLine: CGFloat = 0) {
            self.width = width; self.tileHeight = tileHeight; self.gap = gap; self.sceneGap = sceneGap
            self.headerHeight = headerHeight; self.headerGap = headerGap; self.top = top; self.bottom = bottom; self.copyLine = copyLine
        }
    }

    public struct Tile: Equatable, Sendable {
        /// Index into `Shoot.photos`.
        public var photo: Int
        public var id: String
        public var width: CGFloat
        public var contain: Bool
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case header, row, copyLine }
        public var id: String
        public var kind: Kind
        /// Index into `Shoot.scenes` (−1 for the copy line).
        public var scene: Int
        public var y: CGFloat
        public var height: CGFloat
        public var tiles: [Tile]
        /// The scene's last row (left-aligned at the target height).
        public var last: Bool
    }

    public private(set) var items: [Item] = []
    public private(set) var contentHeight: CGFloat = 0
    public private(set) var config: Config
    /// Photos on screen, per scene index (for the header's counts).
    public private(set) var sceneIDs: [Int: [String]] = [:]
    private var itemOfPhoto: [String: Int] = [:]

    public init(shoot: Shoot, visible: Int, config: Config) {
        self.config = config
        var y = config.top, first = true
        for scene in shoot.scenes {
            // What has been copied so far; photos arrive in shoot order.
            let members = scene.ids.compactMap { id -> (Int, String)? in shoot.position(id).flatMap { $0 < visible ? ($0, id) : nil } }
            guard !members.isEmpty else { continue }
            sceneIDs[scene.index] = members.map(\.1)
            if !first { y += config.sceneGap }
            first = false
            items.append(Item(id: "h\(scene.index)", kind: .header, scene: scene.index, y: y, height: config.headerHeight, tiles: [], last: false))
            y += config.headerHeight + config.headerGap
            let rows = CullLayout.rows(aspects: members.map { CGFloat(shoot.photos[$0.0].aspect) }, width: config.width,
                                       targetHeight: config.tileHeight, gap: config.gap)
            for (r, row) in rows.enumerated() {
                let tiles = row.tiles.map { Tile(photo: members[$0.index].0, id: members[$0.index].1, width: $0.width, contain: $0.contain) }
                for t in tiles { itemOfPhoto[t.id] = items.count }
                items.append(Item(id: "r\(scene.index).\(r)", kind: .row, scene: scene.index, y: y, height: row.height, tiles: tiles, last: row.last))
                y += row.height + (r == rows.count - 1 ? 0 : config.gap)
            }
        }
        if config.copyLine > 0, !items.isEmpty {
            y += config.sceneGap
            items.append(Item(id: "copy", kind: .copyLine, scene: -1, y: y, height: config.copyLine, tiles: [], last: false))
            y += config.copyLine
        }
        contentHeight = items.isEmpty ? 0 : y + config.bottom
    }

    /// The row a photo is in.
    public func item(of photo: String?) -> Item? { photo.flatMap { itemOfPhoto[$0] }.map { items[$0] } }

    /// The items that intersect the viewport, plus `overscan` points above and below.
    public func range(offset: CGFloat, viewport: CGFloat, overscan: CGFloat) -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        let top = offset - overscan, bottom = offset + viewport + overscan
        // First item whose bottom edge is below `top`.
        var lo = 0, hi = items.count
        while lo < hi { let m = (lo + hi) / 2; if items[m].y + items[m].height <= top { lo = m + 1 } else { hi = m } }
        var end = lo
        while end < items.count, items[end].y < bottom { end += 1 }
        return lo..<end
    }

    /// The scroll offset that brings `photo`'s row into view, or nil when it already is: the
    /// smallest move, leaving the row 32pt clear of the edge (a scene's header comes along when
    /// its first row is scrolled to). Never animated and never further than needed, so the grid
    /// doesn't jump.
    public func offsetShowing(_ photo: String?, offset: CGFloat, viewport: CGFloat) -> CGFloat? {
        guard let item = item(of: photo), viewport > 0 else { return nil }
        let edge: CGFloat = 8, margin: CGFloat = 32, top = item.y, bottom = item.y + item.height
        var target: CGFloat
        if top < offset + edge || item.height + 2 * edge > viewport { target = top - margin }
        else if bottom > offset + viewport - edge { target = bottom + margin - viewport }
        else { return nil }
        // A row taller than the space keeps its top in view.
        target = min(target, top - min(edge, max(0, viewport - item.height) / 2))
        target = clamp(0, target, max(0, contentHeight - viewport))
        return abs(target - offset) < 0.5 ? nil : target
    }

    /// What `debug.metrics` reports for R-56.
    public var metricRows: [Metrics.Row] {
        items.filter { $0.kind == .row }.map { item in
            let w = item.tiles.reduce(0) { $0 + $1.width } + config.gap * CGFloat(max(0, item.tiles.count - 1))
            return Metrics.Row(scene: item.scene, width: Double(w), gridWidth: Double(config.width), last: item.last)
        }
    }
}
