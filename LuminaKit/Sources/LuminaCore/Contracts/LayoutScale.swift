import Foundation
import CoreGraphics

// WP-0 contract: LAYOUT_SIZING.md §3–§5 as functions. Views take every size from here or from
// the tokens × scale; none hard-codes a point size.

public enum LayoutScale {
    /// S = clamp(1.0, min(width / 1280, height / 800), 1.5). The handoff's rule
    /// (LAYOUT_SIZING §3: from 1440x900, at most 1.25) left the chrome small and the screen empty
    /// on today's displays; ruled 2026-10-02: grow from 1280x800, up to 1.5.
    public static let base = CGSize(width: 1280, height: 800)
    public static let maximum: CGFloat = 1.5
    public static func scale(for size: CGSize) -> CGFloat {
        min(maximum, max(1.0, min(size.width / base.width, size.height / base.height)))
    }
    /// Fonts round to 0.5pt, everything else to 1pt.
    public static func font(_ pt: CGFloat, _ s: CGFloat) -> CGFloat { (pt * s * 2).rounded() / 2 }
    public static func px(_ pt: CGFloat, _ s: CGFloat) -> CGFloat { (pt * s).rounded() }
}

public func clamp<T: Comparable>(_ lo: T, _ v: T, _ hi: T) -> T { min(hi, max(lo, v)) }

/// Breakpoints (LAYOUT_SIZING §4), on the window content size in points, before scaling.
public struct Breakpoints: Equatable, Sendable {
    public var size: CGSize
    public init(_ size: CGSize) { self.size = size }
    public var topBarHeight: CGFloat { size.height < 760 ? 38 : size.height < 900 ? 42 : 48 }
    public var topBarPadding: CGFloat { size.width < 700 ? 10 : 20 }
    public var tabWidth: CGFloat { size.width < 560 ? 60 : size.width < 760 ? 72 : 88 }
    public var showsWordmark: Bool { size.width >= 700 }
    public var showsTabHints: Bool { size.width >= 760 }
    public var showsKeyHints: Bool { size.width >= 560 }
    public var showsShootMeta: Bool { size.width >= 900 }
    public var cullHasPreview: Bool { size.width >= 900 }
    public var editControlsBelow: Bool { size.width < 860 }
    public var editControlsStartCollapsed: Bool { size.height < 640 }
    /// Open and Save: clamp(560, 0.46 × width, 760) × S, never wider than the window allows.
    public func formColumn(_ s: CGFloat) -> CGFloat { min(clamp(560, 0.46 * size.width, 760) * s, size.width - 48 > 0 ? max(size.width - 48, 272) : size.width) }
    public var formTopPadding: CGFloat { size.height < 700 ? 24 : clamp(24, 0.07 * size.height, 72) }
    /// Cull preview column: clamp(300, 0.38 × width, 0.5 × width).
    public var cullPreviewWidth: CGFloat { clamp(300, 0.38 * size.width, 0.5 * size.width) }
    /// Edit controls column: clamp(252, 0.20 × width, 340) × S.
    public func editControlsWidth(_ s: CGFloat) -> CGFloat { clamp(252, 0.20 * size.width, 340) * s }
    /// Filmstrip thumbnails: clamp(32, 0.045 × height, 72).
    public var filmstripHeight: CGFloat { clamp(32, 0.045 * size.height, 72) }
}
