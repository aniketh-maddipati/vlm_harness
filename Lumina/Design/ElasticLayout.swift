import CoreGraphics
import Foundation

/// Elastic v4 layout contract (`design_handoff_elastic_v4/README.md`).
///
/// The one definition site for Elastic's numbers. Where an existing token already
/// carries the same meaning — reject dim, thumb radius, scene gap, focus ring — this
/// defers to it; the rest are the design's own values and live here, named for role,
/// so no view ever hand-writes a size.
@MainActor
enum ElasticLayout {

    // MARK: - Time table

    static let tile: CGFloat = 168
    static let tileInOpenBurst: CGFloat = 128
    static let tileRadius = HiFiTokens.Grid.photoRadiusThumb
    static let chipRadius: CGFloat = 6
    static let overlayRadius: CGFloat = 14

    /// Vertical separation between moment rows, by how long the photographer
    /// stopped shooting. Quantized to three steps so the table stays legible
    /// rather than proportional to real elapsed time.
    enum Gap {
        static let short: CGFloat = 14
        static let medium = HiFiTokens.Elastic.gapMedium
        static let long = HiFiTokens.Elastic.gapLong

        static let mediumThreshold = TimeInterval(HiFiTokens.Elastic.gapThresholdMediumMin) * 60
        static let longThreshold: TimeInterval = 25 * 60
        static let longestThreshold: TimeInterval = 60 * 60
    }

    /// Separation to put after a moment that is followed by `interval` of quiet.
    static func gapHeight(after interval: TimeInterval) -> CGFloat {
        if interval >= Gap.longestThreshold { return Gap.long }
        if interval >= Gap.longThreshold { return Gap.medium }
        if interval >= Gap.mediumThreshold { return Gap.short }
        return 0
    }

    /// `+ 2 h 15 min` — shown only where a gap is wide enough to carry a label.
    static func gapLabel(for interval: TimeInterval) -> String? {
        guard interval >= Gap.mediumThreshold else { return nil }
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "+ \(minutes) min" }
        if minutes == 0 { return "+ \(hours) h" }
        return "+ \(hours) h \(minutes) min"
    }

    // MARK: - Focus route

    static let filmstripHeight: CGFloat = 92
    static let filmstripFocusedTile = CGSize(
        width: HiFiTokens.Elastic.filmstripFocusedWidth,
        height: HiFiTokens.Elastic.filmstripFocusedHeight
    )
    static let filmstripTile = CGSize(
        width: 72,
        height: HiFiTokens.Elastic.filmstripTileHeight
    )
    static let filmstripMomentGap = HiFiTokens.Grid.sceneGap
    static let versionColumnWidth: CGFloat = 168
    static let developDrawerWidth: CGFloat = 256

    // MARK: - Marks

    /// Rejected frames dim in place — still readable, never hidden.
    static let outOpacity = HiFiTokens.Color.rejectDimOpacity
    static let focusRingWidth = HiFiTokens.Ring.selectionFocusWidth
    static let focusRingHaloWidth = HiFiTokens.Ring.selectionWidth
    static let setOutlineWidth: CGFloat = 2

    // MARK: - Set shelf

    static let setShelfHeight = HiFiTokens.Elastic.setShelfHeight
}
