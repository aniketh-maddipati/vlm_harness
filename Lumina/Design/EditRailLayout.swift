import CoreGraphics
import Foundation

/// Edit chrome geometry — frame 6 / frame 12 (hi-fi H7).
/// Window + row metrics come from generated `HiFiTokens` (design/tokens.yaml).
enum EditRailLayout {
    static let minWindowWidth: CGFloat = HiFiTokens.Layout.minWindowWidth
    static let minWindowHeight: CGFloat = HiFiTokens.Layout.minWindowHeight
    static let rowHeight: CGFloat = HiFiTokens.Layout.editRailRowHeight
    static let rowCount = HiFiTokens.Layout.editRailRowCount
    static let railWidth: CGFloat = 324
    static let railPadding: CGFloat = 16
    static let storyStripWidthNormal: CGFloat = 80
    static let storyStripWidthCompact: CGFloat = 56
    /// Footer shortcuts + action buttons beneath the ten target rows.
    static let railFooterHeight: CGFloat = 118
    /// Chip row, auto edit, staging hints — yields before targets in compact mode.
    static let contextBlockHeight: CGFloat = 92

    /// Ten control families from the copy contract (four sections).
    static let rowLabels: [String] = [
        "Exposure", "Contrast", "Highlights", "Shadows",
        "Temp", "Tint", "Vibrance", "Saturation",
        "Detail", "Straighten"
    ]

    static func isCompact(windowHeight: CGFloat) -> Bool {
        windowHeight <= minWindowHeight + 0.5
    }

    /// Histogram yields before any rail control at the min window (frame 12).
    static func showsHistogram(windowHeight: CGFloat) -> Bool {
        !isCompact(windowHeight: windowHeight)
    }

    static func storyStripWidth(compact: Bool) -> CGFloat {
        compact ? storyStripWidthCompact : storyStripWidthNormal
    }

    /// Fixed target rail — never scales down (frame 12).
    static var targetsHeight: CGFloat {
        CGFloat(rowCount) * rowHeight
    }

    static func railColumnHeight(contextVisible: Bool) -> CGFloat {
        targetsHeight + railFooterHeight + (contextVisible ? contextBlockHeight : 0)
    }

    /// Straighten is the last row — fully on-screen when the rail fits.
    static func straightenRowFits(windowHeight: CGFloat, contextVisible: Bool) -> Bool {
        let rail = railColumnHeight(contextVisible: contextVisible)
        let histogram: CGFloat = showsHistogram(windowHeight: windowHeight) ? HiFiTokens.Histogram.height + 8 : 0
        return windowHeight >= rail + histogram + 40
    }
}
