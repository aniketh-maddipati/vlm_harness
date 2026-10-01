import SwiftUI
import AppKit
import LuminaCore

// WP-3. The Cull grid (README §2, LAYOUT_SIZING §5): scenes, each a header and justified rows.
// `CullGrid` knows where everything is; this view draws the items inside the visible rectangle
// (plus a margin), so 5,000 photos scroll like 100, and it keeps the current photo in view.

/// The grid's layout, computed once per (shoot, photos copied, width, tile height) and reused by
/// every render in between.
@MainActor
final class CullGridCache {
    private struct Key: Equatable { var shoot: String; var total: Int; var visible: Int; var config: CullGrid.Config }
    private var key: Key?
    private var grid: CullGrid?

    func grid(shoot: Shoot, visible: Int, config: CullGrid.Config, tileHeight: CGFloat) -> CullGrid {
        let k = Key(shoot: shoot.key, total: shoot.photos.count, visible: visible, config: config)
        if let grid, key == k { return grid }
        // The copy brought more photos and nothing else changed: only the end of the grid is built.
        var previous = key; previous?.visible = visible
        if previous != k || grid?.extend(shoot: shoot, visible: visible) != true {
            grid = CullGrid(shoot: shoot, visible: visible, config: config)
        }
        key = k
        let g = grid!
        // What the sizing tests read (R-56).
        Metrics.shared.tileH = Double(tileHeight); Metrics.shared.rows = g.metricRows
        return g
    }
}

/// Follows the scroll view under the grid: where it is, and moving it. Views redraw only when
/// `generation` changes, which happens when scrolling brings other items into the visible window.
@MainActor @Observable
final class CullScroller {
    private(set) var generation = 0
    @ObservationIgnored private weak var scrollView: NSScrollView?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastRange: Range<Int>?
    @ObservationIgnored var grid: CullGrid?
    @ObservationIgnored var viewport: CGFloat = 0

    /// Points drawn beyond the viewport on each side, so a scroll never shows an empty band.
    var overscan: CGFloat { max(200, viewport * 0.5) }

    var offset: CGFloat {
        guard let sv = scrollView else { return 0 }
        let b = sv.contentView.bounds
        if sv.documentView?.isFlipped ?? true { return max(0, b.minY) }
        return max(0, (sv.documentView?.bounds.height ?? b.maxY) - b.maxY)
    }

    /// What to draw now. Called from the view's body, so it always matches the layout in use.
    func visibleRange(in grid: CullGrid, viewport: CGFloat) -> Range<Int> {
        self.grid = grid; self.viewport = viewport
        let r = grid.range(offset: offset, viewport: viewport, overscan: overscan)
        lastRange = r
        return r
    }

    func attach(_ sv: NSScrollView?) {
        guard sv !== scrollView else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = sv; observer = nil
        guard let sv else { return }
        sv.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
        generation &+= 1
    }

    private func scrolled() {
        guard let grid else { return }
        if grid.range(offset: offset, viewport: viewport, overscan: overscan) != lastRange { generation &+= 1 }
    }

    /// Bring a photo's row into view by the smallest move; nothing happens when it already is.
    func show(_ photo: String?) {
        guard let grid, let sv = scrollView, let target = grid.offsetShowing(photo, offset: offset, viewport: viewport) else { return }
        let clip = sv.contentView
        let y = sv.documentView?.isFlipped ?? true ? target : max(0, (sv.documentView?.bounds.height ?? 0) - target - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y))
        sv.reflectScrolledClipView(clip)
        scrolled()
    }
}

/// Finds the NSScrollView SwiftUI put the grid in.
private struct ScrollViewFinder: NSViewRepresentable {
    let scroller: CullScroller
    final class Probe: NSView {
        var onMove: ((NSScrollView?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); report() }
        func report() { let sv = enclosingScrollView; DispatchQueue.main.async { [weak self] in self?.onMove?(sv) } }
    }
    func makeNSView(context: Context) -> Probe {
        let v = Probe(); v.onMove = { [scroller] sv in scroller.attach(sv) }; return v
    }
    func updateNSView(_ v: Probe, context: Context) { if v.enclosingScrollView != nil { v.report() } }
}

struct CullGridView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @State private var scroller = CullScroller()

    var body: some View {
        GeometryReader { geo in
            let pad = LuminaSpacing.cullPadding.map { $0.scaled(s) }             // top, sides, bottom
            let tileH = model.cullTileHeight(gridHeight: geo.size.height)
            let visible = model.visiblePhotos.count
            let config = CullGrid.Config(
                width: max(40, geo.size.width - 2 * pad[1]), tileHeight: tileH, gap: LuminaSpacing.tileGap.scaled(s),
                sceneGap: LuminaSpacing.sceneGap.scaled(s), headerHeight: LuminaHeight.chip.scaled(s), headerGap: 8.scaled(s),
                top: pad[0], bottom: pad[2], copyLine: model.copying && visible < model.total ? 20.scaled(s) : 0)
            let grid = model.feature(CullGridCache.self) { CullGridCache() }.grid(shoot: model.shoot, visible: visible, config: config, tileHeight: tileH)

            ScrollView(.vertical) {
                CullGridContent(grid: grid, scroller: scroller, viewport: geo.size.height, side: pad[1])
                    .background(ScrollViewFinder(scroller: scroller))
            }
            .accessibilityIdentifier(AccessibilityID.Cull.grid)
            .onAppear { model.cullSession.gridHeight = geo.size.height; model.cullRestoreTileSize() }
            .onChange(of: geo.size.height) { _, h in model.cullSession.gridHeight = h }
            // Keep the current photo in view: when it changes (keys, undo, a click), when the
            // rows are laid out again (resize, tile size), and once the scroll view is known.
            .onChange(of: model.cullCur) { _, cur in follow(cur) }
            .onChange(of: config.width) { _, _ in follow(model.cullCur) }
            .onChange(of: config.tileHeight) { _, _ in follow(model.cullCur) }
            .onChange(of: scroller.generation == 0) { _, _ in follow(model.cullCur) }
        }
    }

    /// After this render has reached the scroll view, so the offsets are the new layout's.
    private func follow(_ id: String?) { DispatchQueue.main.async { scroller.show(id) } }
}

/// The scroll content: a fixed-size sheet with only the visible items on it.
private struct CullGridContent: View {
    let grid: CullGrid
    let scroller: CullScroller
    let viewport: CGFloat
    let side: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let _ = scroller.generation
        let range = scroller.visibleRange(in: grid, viewport: viewport)
        let keep = model.decisions.keep, cur = model.cullCur, photos = model.shoot.photos
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: grid.config.width + 2 * side, height: max(grid.contentHeight, 1))
            ForEach(grid.items[range]) { item in
                Group {
                    switch item.kind {
                    case .header:
                        CullSceneHeader(scene: item.scene, ids: grid.sceneIDs[item.scene] ?? [], suggested: grid.sceneSuggested[item.scene] ?? [], width: grid.config.width)
                    case .row:
                        HStack(spacing: grid.config.gap) {
                            ForEach(item.tiles, id: \.id) { t in
                                let p = photos[t.photo], k = keep[t.id]
                                CullTile(photo: p, width: t.width, height: item.height, contain: t.contain,
                                         state: k == true ? .kept : k == false ? .out : p.suggested ? .suggested : .undecided,
                                         current: t.id == cur, s: s, select: { model.select($0) })
                                    .equatable()
                            }
                        }
                    case .copyLine:
                        Text(CullCopy.copying(model.copied, of: model.total))
                            .font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary).lineLimit(1)
                    }
                }
                .frame(width: grid.config.width, height: item.height, alignment: .leading)
                .alignmentGuide(.top) { _ in -item.y }
                .alignmentGuide(.leading) { _ in -side }
            }
        }
        .frame(width: grid.config.width + 2 * side, height: max(grid.contentHeight, 1), alignment: .topLeading)
    }
}

/// "09:12 · 14 photos · 3 decided" and "Keep 5 suggested".
private struct CullSceneHeader: View {
    let scene: Int
    /// The scene's photos on screen, and the suggested ones among them.
    let ids: [String]
    let suggested: [String]
    let width: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let keep = model.decisions.keep
        let decided = ids.reduce(0) { $0 + (keep[$1] == nil ? 0 : 1) }
        let toKeep = suggested.reduce(0) { $0 + (keep[$1] == nil ? 1 : 0) }
        let title = model.shoot.scenes.indices.contains(scene) ? model.shoot.scenes[scene].header : ""
        // A narrow grid drops the decided count, then the photo count, so nothing is pushed sideways.
        let count: String? = width >= 380 * s ? CullCopy.sceneCount(photos: ids.count, decided: decided)
            : width >= 280 * s ? CullCopy.sceneCount(photos: ids.count, decided: 0) : nil
        HStack(alignment: .center, spacing: 12.scaled(s)) {
            Text(title).font(LuminaFont.caption(s, .semibold)).foregroundStyle(LuminaColor.textPrimary)
                .lineLimit(1).truncationMode(.tail)
                .accessibilityIdentifier(AccessibilityID.Cull.scene(scene))
            if let count {
                Text(count).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary).lineLimit(1)
                    .fixedSize().layoutPriority(1)
            }
            Spacer(minLength: 0)
            if toKeep > 0 {
                Button(CullCopy.keepSuggested(toKeep)) { model.keepSuggested(scene: scene) }
                    .buttonStyle(CullChipStyle())
                    .fixedSize().layoutPriority(2)
                    .help(CullCopy.keepSuggestedHelp)
                    .accessibilityIdentifier(AccessibilityID.Cull.keepSuggested(scene))
            }
        }
        .frame(maxWidth: .infinity, minHeight: LuminaHeight.chip.scaled(s), alignment: .leading)
    }
}

/// A chip: height 24, padding 0/10, radius 6, fill 0.08 (0.16 on hover).
struct CullChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration) }
    private struct Content: View {
        let configuration: Configuration
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textPrimary).lineLimit(1)
                .padding(.horizontal, 10.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
                .background(RoundedRectangle(cornerRadius: LuminaRadius.chip.scaled(s), style: .continuous).fill(hover ? LuminaColor.fill16 : LuminaColor.fill08))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}
