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
        /// The row's number within its scene (−1 for a header or the copy line).
        public var row: Int
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
    /// The ones among them Lumina suggests keeping (the "Keep n suggested" chip counts the undecided ones).
    public private(set) var sceneSuggested: [Int: [String]] = [:]
    private var itemOfPhoto: [String: Int] = [:]

    /// How many photos (from the start of the shoot) this grid shows.
    public private(set) var visible = 0

    public init(shoot: Shoot, visible: Int, config: Config) {
        self.config = config; self.visible = visible
        for (s, scene) in shoot.scenes.enumerated() {
            // What has been copied so far.
            let members = scene.ids.compactMap { id -> (Int, String)? in shoot.position(id).flatMap { $0 < visible ? ($0, id) : nil } }
            if !members.isEmpty { add(members, to: s, shoot: shoot) }
        }
        finish()
    }

    /// The same grid with more photos copied, without laying the whole shoot out again: rows
    /// that are already full stay as they are, and only the last row and what follows it is
    /// built. For a shoot whose scenes follow each other in photo order (`Shoot` from a card or
    /// an import); returns false, leaving the grid as it was, when that can't be done.
    public mutating func extend(shoot: Shoot, visible more: Int) -> Bool {
        guard more >= visible else { return false }
        guard more > visible else { return true }
        guard let lastRow = items.last(where: { $0.kind == .row }), shoot.scenes.indices.contains(lastRow.scene),
              let old = sceneIDs[lastRow.scene], !old.isEmpty else { return false }
        let s = lastRow.scene, scene = shoot.scenes[s]
        // The photos shown must be the first ones of the scene, and the new ones the next.
        guard scene.ids.count >= old.count, scene.ids[old.count - 1] == old.last else { return false }
        var fresh: [(Int, String)] = []
        for id in scene.ids[old.count...] { guard let p = shoot.position(id), p < more else { break }; fresh.append((p, id)) }
        var later: [(Int, [(Int, String)])] = []
        for n in (s + 1)..<max(s + 1, shoot.scenes.count) {
            var members: [(Int, String)] = []
            for id in shoot.scenes[n].ids { guard let p = shoot.position(id), p < more else { break }; members.append((p, id)) }
            if members.isEmpty { break }
            later.append((n, members))
        }
        guard fresh.count + later.reduce(0, { $0 + $1.1.count }) == more - visible else { return false }

        if items.last?.kind == .copyLine { items.removeLast() }
        if !fresh.isEmpty {
            // Take the scene's last row back and lay it out again with the new photos behind it.
            items.removeLast()
            add(lastRow.tiles.map { ($0.photo, $0.id) } + fresh, to: s, shoot: shoot, continuing: lastRow)
        }
        for (n, members) in later { add(members, to: n, shoot: shoot) }
        visible = more
        finish()
        return true
    }

    /// Bottom edge of the last header or row.
    private var cursor: CGFloat { items.last.map { $0.y + $0.height } ?? config.top }

    private mutating func add(_ members: [(Int, String)], to s: Int, shoot: Shoot, continuing row: Item? = nil) {
        var y: CGFloat, number = 0
        if let row {
            y = row.y; number = row.row
            sceneIDs[s, default: []] += members.dropFirst(row.tiles.count).map(\.1)
            sceneSuggested[s, default: []] += members.dropFirst(row.tiles.count).filter { shoot.photos[$0.0].suggested }.map(\.1)
        } else {
            y = items.isEmpty ? config.top : cursor + config.sceneGap
            sceneIDs[s] = members.map(\.1)
            sceneSuggested[s] = members.filter { shoot.photos[$0.0].suggested }.map(\.1)
            items.append(Item(id: "h\(s)", kind: .header, scene: s, row: -1, y: y, height: config.headerHeight, tiles: [], last: false))
            y += config.headerHeight + config.headerGap
        }
        let rows = CullLayout.rows(aspects: members.map { CGFloat(shoot.photos[$0.0].aspect) }, width: config.width,
                                   targetHeight: config.tileHeight, gap: config.gap)
        for (r, row) in rows.enumerated() {
            let tiles = row.tiles.map { Tile(photo: members[$0.index].0, id: members[$0.index].1, width: $0.width, contain: $0.contain) }
            for t in tiles { itemOfPhoto[t.id] = items.count }
            items.append(Item(id: "r\(s).\(number + r)", kind: .row, scene: s, row: number + r, y: y, height: row.height, tiles: tiles, last: row.last))
            y += row.height + config.gap
        }
    }

    private mutating func finish() {
        var y = cursor
        if config.copyLine > 0, !items.isEmpty {
            y += config.sceneGap
            items.append(Item(id: "copy", kind: .copyLine, scene: -1, row: -1, y: y, height: config.copyLine, tiles: [], last: false))
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
        if target <= config.top { target = 0 }                      // the first rows: all the way to the top
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
