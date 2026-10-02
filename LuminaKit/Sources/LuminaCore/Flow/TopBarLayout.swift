import Foundation
import CoreGraphics

// WP-1. The top bar's sizes (README "Global shell", LAYOUT_SIZING §3–§4) as one value, so the
// view has no numbers of its own and the fit at 320 wide (R-50) is tested without a window.

public struct TopBarLayout: Equatable, Sendable {
    /// 38 / 42 / 48 by window height, × S.
    public let height: CGFloat
    /// Left edge of the bar's content: the bar's padding, or just past the traffic lights.
    public let leading: CGFloat
    public let trailing: CGFloat
    /// Between the wordmark, the tabs and the shoot meta.
    public let gap: CGFloat
    /// One segment: 88 (72 under 760 wide, 60 under 560) × S. Narrower only when the window is
    /// so narrow that four segments don't fit beside the traffic lights.
    public let tabWidth: CGFloat
    public let tabHeight: CGFloat
    /// The track's padding around the segments.
    public let trackPadding: CGFloat
    public let trackRadius: CGFloat
    public let thumbRadius: CGFloat
    /// Between a tab's label and its ⌘ hint.
    public let hintGap: CGFloat
    /// Between "N keepers · S scenes" and the copy status, and the status' fixed slot.
    public let metaGap: CGFloat
    public let copySlot: CGFloat
    public let showsWordmark: Bool
    public let showsHints: Bool
    public let showsMeta: Bool

    /// A segment never gets narrower than this (its label is about 34pt wide at 13pt).
    public static let minTabWidth: CGFloat = 44
    /// Clear space kept after the traffic lights.
    public static let trafficLightGap: CGFloat = 10

    /// - `trafficLights`: the right edge of the window's close / minimise / zoom buttons in
    ///   points, 0 when the window has none (full screen, the snapshot tool).
    public init(window: CGSize, scale s: CGFloat, trafficLights: CGFloat = 0) {
        let bp = Breakpoints(window)
        height = LayoutScale.px(bp.topBarHeight, s)
        let pad = LayoutScale.px(bp.topBarPadding, s)
        leading = max(pad, trafficLights > 0 ? trafficLights.rounded(.up) + Self.trafficLightGap : 0)
        trailing = pad
        gap = LayoutScale.px(18, s)
        trackPadding = LayoutScale.px(2, s)
        trackRadius = LayoutScale.px(7, s)
        thumbRadius = LayoutScale.px(5, s)
        tabHeight = LayoutScale.px(24, s)
        hintGap = LayoutScale.px(5, s)
        metaGap = LayoutScale.px(12, s)
        copySlot = LayoutScale.px(118, s)
        showsWordmark = bp.showsWordmark
        showsHints = bp.showsTabHints
        showsMeta = bp.showsShootMeta
        // The wordmark and the meta only show on windows with room to spare; under 700 wide the
        // tabs have the bar to themselves and must fit whole (R-50).
        let room = window.width - leading - trailing - 2 * trackPadding
        let fit = (room / 4).rounded(.down)
        tabWidth = min(LayoutScale.px(bp.tabWidth, s), max(Self.minTabWidth, fit))
    }

    /// The whole control: four segments and the track's padding.
    public var tabsWidth: CGFloat { 4 * tabWidth + 2 * trackPadding }
    /// Where the sliding thumb sits for a step, from the first segment's left edge.
    public func thumbOffset(_ step: Step) -> CGFloat { CGFloat(step.index) * tabWidth }
}

// MARK: The meta's status slot

public extension AppModel {
    /// The words in the meta's fixed status slot. On Edit, the save status (Lumina Edit v19's
    /// top bar, `saveT`: "Saving…" / "All changes saved" / what went wrong), unless a card is
    /// still being copied: the copy's progress is never hidden. Elsewhere the copy status.
    /// "All changes saved" fits the 118pt slot where "All 117 copied and checked" doesn't, so the
    /// tabs, centred between the wordmark and the meta, sit where the prototype has them on Edit.
    var shellStatus: String {
        step == .edit && !shellIsCopying ? editSaveStatus : shellCopyStatus
    }
}
