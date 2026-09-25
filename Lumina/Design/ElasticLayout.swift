import CoreGraphics
import Foundation

/// Elastic v4 layout contract (`design_handoff_elastic_v4/README.md`, visual spec).
///
/// The one definition site for Elastic's numbers. Where an existing token already
/// carries the same meaning — reject dim, thumb radius, burst and scene gaps, focus
/// ring, workspace gutter — this defers to it; the rest are the design's own values
/// and live here, named for role, so no view ever hand-writes a size.
@MainActor
enum ElasticLayout {

    // MARK: - Page

    /// Header / shelf / receipt gutter.
    static let chromeGutter = HiFiTokens.Layout.chromeSpacingLg
    /// Table / focus / strip / peek gutter.
    static let tableGutter = HiFiTokens.Gap.workspaceMargin
    static let headerHeight = HiFiTokens.Elastic.headerHeight
    /// Prev / next page. The contract minimum, so the control is a settled target.
    static let pageControlHit = HiFiTokens.Hit.minimum
    static let headerGap = HiFiTokens.Gap.spacingMd
    static let hairline: CGFloat = 1
    static let hairlineOpacity: Double = 0.08

    // MARK: - Header

    static let wordmarkSize: CGFloat = 21
    static let headerTextSize: CGFloat = 12.5
    static let autoHeight: CGFloat = 36
    static let autoPadding: CGFloat = 14
    static let autoRadius: CGFloat = 9
    static let autoTextSize: CGFloat = 13.5
    static let autoSubSize = HiFiTokens.Typography.exifSize
    static let autoGap: CGFloat = 8
    static let autoDisabledOpacity: Double = 0.08
    static let subLabelOpacity: Double = 0.7

    // MARK: - Stitch

    /// Kept-set spine. Same plate as the table so the walk stays one costume.
    static let stitchPlate = tile
    static let stitchPlateAspect = tileAspect
    static let stitchPlateRadius = tileRadius
    static let stitchGap = frameGap
    static let stitchOrdinalSize = shelfLabelSize
    static let stitchBarHeight = setShelfHeight

    // MARK: - Set shelf

    static let setShelfHeight = HiFiTokens.Elastic.setShelfHeight
    static let shelfPaddingV: CGFloat = 8
    static let shelfGap = HiFiTokens.Gap.spacingXs
    static let shelfLabelWidth: CGFloat = 52
    static let shelfLabelSize = HiFiTokens.Typography.exifSize
    static let shelfLabelLineHeight: CGFloat = 1.4
    static let shelfTile = CGSize(width: 72, height: HiFiTokens.Elastic.filmstripTileHeight)
    static let shelfTileRadius = HiFiTokens.Grid.photoRadiusLarge
    static let exportHeight = HiFiTokens.Elastic.exportHeight
    static let exportPadding = HiFiTokens.Elastic.exportPadding
    static let exportRadius = HiFiTokens.Elastic.exportRadius
    static let exportTextSize: CGFloat = 15
    static let exportGap = HiFiTokens.Gap.spacingSm
    static let keyPillSize: CGFloat = 13
    static let keyPillPaddingH = HiFiTokens.Gap.spacingXs
    static let keyPillPaddingV: CGFloat = 2
    static let keyPillRadius: CGFloat = 5
    static let keyPillOpacity = HiFiTokens.Elastic.keyPillOpacity

    // MARK: - Export receipt

    static let receiptPaddingTop: CGFloat = 8
    static let receiptPaddingBottom = HiFiTokens.Gap.spacingSm
    static let receiptTextSize: CGFloat = 12
    static let receiptGap = HiFiTokens.Layout.chromeSpacingLg

    // MARK: - Time table

    static let tablePaddingTop = HiFiTokens.Gap.spacingLg
    static let tile: CGFloat = 168
    static let tileInOpenBurst: CGFloat = 128
    static let tileAspect: CGFloat = 3.0 / 2.0
    static let tileRadius = HiFiTokens.Grid.photoRadiusThumb
    static let chipRadius: CGFloat = 6
    static let overlayRadius: CGFloat = 14

    static let momentRadius = HiFiTokens.Elastic.momentRadius
    static let momentPaddingV: CGFloat = 14
    static let momentPaddingH: CGFloat = 12
    static let momentGap = HiFiTokens.Gap.spacingMd
    static let momentColumnWidth: CGFloat = 150
    static let momentColumnTop: CGFloat = 2
    static let momentTextSize = HiFiTokens.Typography.exifSize
    static let momentTimeSize: CGFloat = 15
    static let momentLineHeight: CGFloat = 1.6
    static let momentSecondaryOpacity: Double = 0.7
    static let gapLabelLeading: CGFloat = 12
    static let gapLabelSize = HiFiTokens.Typography.exifSize
    static let gapLabelOpacity: Double = 0.7

    /// Frame groups wrap with a burst gap between rows and a scene gap between groups.
    static let groupRowGap = HiFiTokens.Grid.burstGap
    static let groupGap = HiFiTokens.Grid.sceneGap
    static let frameGap = HiFiTokens.Grid.burstGap

    /// A collapsed burst: two cards peeking out behind the leader, badge on the edge.
    static let stackPadding: CGFloat = 14
    static let stackBack = CGSize(width: 6, height: -4)
    static let stackMiddle = CGSize(width: 3, height: -2)
    static let stackBackOpacity = HiFiTokens.Elastic.stackBackOpacity
    static let stackMiddleOpacity: Double = 0.4
    static let badgeHeight = HiFiTokens.Elastic.burstBadgeHeight
    static let badgeMinWidth = HiFiTokens.Hit.minimum
    static let badgePaddingH = HiFiTokens.Gap.spacingSm
    static let badgeRadius: CGFloat = 8
    static let badgeTop = HiFiTokens.Gap.spacingXs
    static let badgeTextSize: CGFloat = 13
    /// Collapsed: badge hangs past the stack edge; open: tucked inside the last frame.
    static let badgeOutsideStack = -HiFiTokens.Gap.spacingXs
    static let badgeInsideOpen = HiFiTokens.Gap.spacingXs

    static let markInset = HiFiTokens.Gap.spacingXs
    static let markSize = HiFiTokens.Elastic.markSize
    static let markTextSize: CGFloat = 13
    static let phoneGlyph = CGSize(
        width: HiFiTokens.Elastic.phoneGlyphWidth,
        height: HiFiTokens.Elastic.phoneGlyphHeight
    )
    static let phoneGlyphStroke = HiFiTokens.Elastic.phoneGlyphStroke
    static let phoneGlyphRadius: CGFloat = 2

    /// Vertical separation above each moment after the first, by how long the
    /// photographer stopped shooting. Quantized to three steps so the table stays
    /// legible rather than proportional to real elapsed time.
    enum Gap {
        static let short: CGFloat = 14
        static let medium = HiFiTokens.Elastic.gapMedium
        static let long = HiFiTokens.Elastic.gapLong

        static let labelThreshold = TimeInterval(HiFiTokens.Elastic.gapThresholdMediumMin) * 60
        static let longThreshold: TimeInterval = 25 * 60
        static let longestThreshold: TimeInterval = 60 * 60
    }

    /// Separation above a moment that follows `interval` of quiet (start to start).
    static func gapHeight(after interval: TimeInterval) -> CGFloat {
        if interval >= Gap.longestThreshold { return Gap.long }
        if interval >= Gap.longThreshold { return Gap.medium }
        return Gap.short
    }

    /// `+ 2 h 15 min` — shown only where a gap is wide enough to carry a label.
    static func gapLabel(for interval: TimeInterval) -> String? {
        guard interval >= Gap.labelThreshold else { return nil }
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "+ \(minutes) min" }
        if minutes == 0 { return "+ \(hours) h" }
        return "+ \(hours) h \(minutes) min"
    }

    // MARK: - Focus route

    static let photoPaddingTop = HiFiTokens.Gap.spacingLg
    static let photoPaddingBottom: CGFloat = 12
    static let photoRowGap = HiFiTokens.Gap.spacingMd
    static let photoRadius = HiFiTokens.Grid.photoRadiusLarge
    static let photoShadowY = HiFiTokens.Elastic.photoShadowY
    /// CSS blur is a diameter; SwiftUI's shadow radius is half of it.
    static let photoShadowRadius = HiFiTokens.Elastic.photoShadowBlur / 2
    static let photoShadowOpacity: Double = 0.35

    static let versionColumnWidth: CGFloat = 144
    static let versionGap: CGFloat = 8
    static let versionBadgeInset: CGFloat = 5
    static let versionBadgeHeight = HiFiTokens.Elastic.versionBadgeHeight
    static let versionBadgePaddingH: CGFloat = 7
    static let versionBadgeGap = HiFiTokens.Gap.spacingXs
    static let versionBadgeTextSize = HiFiTokens.Typography.exifSize
    static let versionUnauthoredOpacity: Double = 0.35

    static let statusPaddingTop = HiFiTokens.Gap.spacingXs
    static let statusPaddingBottom = HiFiTokens.Gap.spacingSm
    static let statusGap = HiFiTokens.Layout.chromeSpacingLg
    static let statusTextSize: CGFloat = 12.5
    static let statusTextOpacity: Double = 0.85
    static let histogramSize = CGSize(width: HiFiTokens.Elastic.histogramWidth, height: 30)
    static let histogramViewHeight = HiFiTokens.Elastic.histogramViewHeight
    static let histogramFillOpacity: Double = 0.75
    static let clipTickWidth = HiFiTokens.Elastic.clipTickWidth

    /// SVG user space: `viewBox="0 0 64 20"` drawn into a 96×30 box. One bin every
    /// two units with the bar on the odd unit, so the shape reads as bars, not a
    /// curve, at any display scale.
    static let histogramBinStride: CGFloat = 2
    static let histogramViewWidth = CGFloat(ImageStats.binCount) * histogramBinStride
    static let histogramBarOffset = histogramBinStride / 2
    /// `y = 20 − b / max × 19` — the tallest bin keeps one unit of headroom.
    static let histogramPeakInset: CGFloat = 1
    static let histogramPeakHeight = histogramViewHeight - histogramPeakInset
    /// The right tick sits flush inside the viewBox, the left one flush outside 0.
    static let clipTickRight = histogramViewWidth - clipTickWidth

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
    static let filmstripGap = HiFiTokens.Grid.burstGap
    static let filmstripFillOpacity = HiFiTokens.Elastic.stripFillOpacity
    static let stripLabelWidth = HiFiTokens.Elastic.stripLabelWidth
    static let stripLabelSize = HiFiTokens.Typography.chipSize
    static let stripLabelLineHeight = HiFiTokens.Elastic.stripLabelLineHeight
    static let stripLabelOpacity: Double = 0.8
    static let developDrawerWidth: CGFloat = 256

    // MARK: - Marks

    /// Rejected frames dim in place — still readable, never hidden.
    static let outOpacity = HiFiTokens.Color.rejectDimOpacity
    static let focusRingWidth = HiFiTokens.Ring.selectionFocusWidth
    static let focusRingHaloWidth = HiFiTokens.Ring.selectionWidth
    /// Outer edge of the halo: ink ring plus light halo.
    static let ringOuter = focusRingWidth + focusRingHaloWidth
    static let setOutlineWidth: CGFloat = 2
    /// `outline-offset: -1.5px` on a 2 px outline centres the stroke 0.5 px inside.
    static let setOutlineInset: CGFloat = focusRingHaloWidth - setOutlineWidth / 2
    /// Lead / trail of the focused burst — second-order stroke, never color alone.
    static let sequenceOutlineWidth = HiFiTokens.Ring.secondOrderWidth
    static let sequenceOutlineOpacity = HiFiTokens.Ring.secondOrderOpacity
    static let sequenceOutlineInset = setOutlineInset
    static let sequenceChipSize = HiFiTokens.Typography.chipSize
    static let sequenceChipPaddingH = HiFiTokens.Gap.spacingXs
    static let sequenceChipPaddingV = HiFiTokens.Ring.haloWidth

    // MARK: - Motion (`born` fade durations, ease-out)

    static let bornTableMs = HiFiTokens.Motion.photoBirthMs
    static let msPerSecond: Double = 1000

    // MARK: - Type

    static let systemLineHeight: CGFloat = 1.2

    // MARK: - Peek (hold ⇥)

    /// The bar pinned to the foot of the table while similar or the set is held:
    /// `padding: 12px 28px 16px`, rows 10 apart, `rgba(46,46,44,0.94)` under a
    /// `rgba(239,236,230,0.15)` rule.
    static let peekPaddingTop: CGFloat = 12
    static let peekPaddingBottom = HiFiTokens.Gap.spacingMd
    static let peekGap = HiFiTokens.Gap.spacingSm
    static let peekTitleGap = HiFiTokens.Gap.spacingMd
    static let peekTitleSize: CGFloat = 14
    static let peekSubSize: CGFloat = 12
    static let peekSubOpacity: Double = 0.7
    static let peekFillOpacity: Double = 0.94
    static let peekRuleOpacity: Double = 0.15
    /// Tiles: 150 in the set peek; in similar, 170 for a neighbour and 220 for the cursor.
    static let peekSetTile: CGFloat = 150
    static let peekRelatedTile: CGFloat = 170
    static let peekCursorTile = HiFiTokens.Elastic.peekCursorTileWidth
    static let peekTileRadius = HiFiTokens.Grid.photoRadiusLarge
    static let peekCaptionGap: CGFloat = 5
    static let peekCaptionSize = HiFiTokens.Typography.chipSize
    static let peekCaptionSpacing = HiFiTokens.Gap.spacingXs
    /// `min-width: 22px; height: 22px; padding: 0 6px` — the key that jumps to the tile.
    static let peekKeyBadgeHeight = HiFiTokens.Elastic.versionBadgeHeight
    static let peekKeyBadgeInset = HiFiTokens.Gap.spacingXs
    static let peekKeyBadgePaddingH = HiFiTokens.Gap.spacingXs
    static let peekKeyBadgeTextSize: CGFloat = 12.5
    static let bornPeekMs = HiFiTokens.Motion.bannerInMs
    /// Press and hold the photograph this long for before (`pressStart`, 200 ms).
    static let beforePressSeconds = HiFiTokens.Motion.beforePress

    /// Similar in the focus route: the neighbours share the band with the cursor at
    /// `flex: 1.6`, bottoms aligned, 14 apart, each under a 24-high key badge.
    static let relatedRowGap: CGFloat = 14
    static let relatedColumnGap = HiFiTokens.Gap.spacingXs
    static let relatedCursorGrow: CGFloat = 1.6
    static let relatedKeyBadgeHeight = HiFiTokens.Elastic.peekRelatedBadgeHeight
    static let relatedKeyBadgeTextSize: CGFloat = 13
    static let relatedCaptionPaddingH: CGFloat = 2
    static let bornRelatedMs = HiFiTokens.Motion.travelMs

    /// The strip while the set is held: `rgba(255,236,205,0.16)` behind the set order.
    static let stripSetFillOpacity: Double = 0.16

    /// The shelf as a drop target: `outline: 2px dashed ink; outline-offset: -2px`.
    static let shelfDropRingWidth: CGFloat = 2
    static let shelfDropRingInset: CGFloat = 2
    static let shelfDropRingDash: [CGFloat] = [6, 4]

    // MARK: - Develop drawer (`data-screen-label="Develop"`)

    /// `width 256; padding 12px 14px; radius 8; gap 6; rgba(46,46,44,0.35)`.
    static let drawerWidth = developDrawerWidth
    static let drawerFillOpacity: Double = 0.35
    static let drawerRadius: CGFloat = 8
    static let drawerPaddingV: CGFloat = 12
    static let drawerPaddingH: CGFloat = 14
    static let drawerGap: CGFloat = 6
    static let drawerTitleSize: CGFloat = 13
    static let drawerScopeSize: CGFloat = 12
    static let drawerScopeOpacity: Double = 0.7
    static let drawerTextSize = HiFiTokens.Typography.chipSize
    static let drawerLabelOpacity: Double = 0.85
    static let drawerMutedOpacity: Double = 0.6
    static let drawerSectionTop: CGFloat = 8
    /// Slider rows: `grid-template-columns: 78px 1fr 44px; gap 8; height 18`.
    static let drawerLabelWidth: CGFloat = 78
    static let drawerValueWidth = HiFiTokens.Elastic.drawerValueColumn
    static let drawerRowGap: CGFloat = 8
    static let drawerSliderHeight = HiFiTokens.Elastic.drawerSliderHeight
    static let drawerTrackHeight: CGFloat = 4
    static let drawerThumbSize: CGFloat = 12
    static let drawerTrackOpacity = HiFiTokens.Elastic.stackBackOpacity
    /// Chips: `height 24; padding 0 8; radius 6; gap 4`.
    static let chipHeight = HiFiTokens.Elastic.drawerChipHeight
    static let chipPaddingH: CGFloat = 8
    static let chipGap: CGFloat = 4
    static let chipFillOpacity = HiFiTokens.Elastic.drawerChipFillOpacity
    /// `auto · match · reset`: `height 32; radius 7; gap 6`.
    static let drawerButtonHeight = HiFiTokens.Elastic.drawerButtonHeight
    static let drawerButtonRadius: CGFloat = 7
    static let drawerButtonGap: CGFloat = 6
    static let drawerResetPaddingH = HiFiTokens.Gap.spacingSm
    static let drawerSourceSize: CGFloat = 10.5
    static let drawerSourceLineHeight = HiFiTokens.Elastic.stripLabelLineHeight
    static let bornDrawerMs = HiFiTokens.Motion.travelMs
    /// Ranges: exposure ±3 by 0.05; tone ±100 by 1; temperature 2000…12000 by 50;
    /// sharpness 0…100 by 1 (the engine's amount runs 0…150; the top is left alone);
    /// straighten ±10 by 0.1.
    static let exposureRange: Double = 3
    static let exposureStep: Double = 0.05
    static let toneRange = Double(HiFiTokens.Elastic.toneRange)
    static let temperatureMin: Double = 2000
    static let temperatureMax: Double = 12000
    static let temperatureStep = Double(HiFiTokens.Elastic.temperatureStep)
    static let sharpnessMax = Double(HiFiTokens.Elastic.toneRange)
    static let straightenRange = Double(HiFiTokens.Elastic.straightenRange)
    static let straightenStep = Double(HiFiTokens.Elastic.straightenStep)
    /// `R` — a quarter turn.
    static let quarterTurnDegrees: Double = 360 / 4
    static let sliderFineTravel = Double(HiFiTokens.Elastic.sliderFineTravel)

    // MARK: - Flags peek · inferred groups (`data-screen-label="Groups"`)

    /// `max-height: 38vh; padding: 12px 28px 6px; gap: 8` on `#6F6E6C`, under a
    /// `rgba(46,46,44,0.2)` rule; each row `padding: 8px 10px; radius 8; gap 14`.
    static let groupsMaxHeightFraction: CGFloat = 0.38
    static let groupsMaxHeight = HiFiTokens.Layout.minWindowHeight * groupsMaxHeightFraction
    static let groupsPaddingTop: CGFloat = 12
    static let groupsPaddingBottom = HiFiTokens.Gap.spacingXs
    static let groupsGap: CGFloat = 8
    static let groupsRuleOpacity = HiFiTokens.Elastic.groupsRuleOpacity
    static let groupsRowPaddingV: CGFloat = 8
    static let groupsRowPaddingH = HiFiTokens.Gap.spacingSm
    static let groupsRowRadius: CGFloat = 8
    static let groupsRowGap = relatedRowGap
    static let groupsRowOpacity = HiFiTokens.Elastic.stackBackOpacity
    static let groupsFocusRowOpacity = HiFiTokens.Elastic.groupsFocusRowOpacity
    static let groupsColumnWidth = HiFiTokens.Elastic.groupsColumnWidth
    static let groupsTextSize = HiFiTokens.Typography.exifSize
    static let groupsLineHeight = HiFiTokens.Elastic.stripLabelLineHeight
    static let groupsKindSize: CGFloat = 13
    static let groupsReasonOpacity: Double = 0.9
    static let groupsTakeOpacity: Double = 0.65
    /// Frames in a row: `96×64`, radius 3, 3 apart; untaken ones at half strength.
    static let groupsFrame = filmstripFocusedTile
    static let groupsFrameGap = HiFiTokens.Grid.burstGap
    static let groupsFrameRadius = HiFiTokens.Grid.photoRadiusThumb
    static let groupsUntakenOpacity = HiFiTokens.Elastic.groupsUntakenOpacity
    /// `sharpest` on a leader: `padding: 1px 5px; radius 4; rgba(46,46,44,0.85)`, 10 px.
    static let groupsTagSize = HiFiTokens.Elastic.groupsTagTextSize
    static let groupsTagPaddingH: CGFloat = 5
    static let groupsTagPaddingV: CGFloat = 1
    static let groupsTagRadius: CGFloat = 4
    static let groupsTagOpacity: Double = 0.85
    static let groupsTagInset: CGFloat = 4
    static let bornGroupsMs = HiFiTokens.Motion.routeTransitionMs

    /// `soft · clips · drift` on a table tile: salmon chip, `padding: 2px 6px`, radius 4, 10.5 px.
    static let flagChipSize: CGFloat = 10.5
    static let flagChipPaddingH = HiFiTokens.Gap.spacingXs
    static let flagChipPaddingV: CGFloat = 2
    static let flagChipRadius: CGFloat = 4
}
