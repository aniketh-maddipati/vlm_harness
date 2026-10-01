import SwiftUI
import LuminaCore

// WP-0 contract: every font goes through here (× luminaScale, recorded for `debug.metrics`).
// A font made any other way is a review failure (ACCESSIBILITY_CONTRACT.md).

public enum LuminaFont {
    /// SF Pro Text at `size` pt × scale, tabular figures.
    public static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular, _ scale: CGFloat, id: String? = nil) -> Font {
        Metrics.shared.record(font: Double(size), id: id)
        return Font.system(size: LayoutScale.font(size, scale), weight: weight).monospacedDigit()
    }
    public static func body(_ scale: CGFloat, _ weight: Font.Weight = .regular, id: String? = nil) -> Font { ui(LuminaFontSize.body, weight, scale, id: id) }
    public static func small(_ scale: CGFloat, _ weight: Font.Weight = .regular, id: String? = nil) -> Font { ui(LuminaFontSize.small, weight, scale, id: id) }
    public static func caption(_ scale: CGFloat, _ weight: Font.Weight = .regular, id: String? = nil) -> Font { ui(LuminaFontSize.caption, weight, scale, id: id) }
    public static func hint(_ scale: CGFloat, id: String? = nil) -> Font { ui(LuminaFontSize.hint, .regular, scale, id: id) }

    /// Titles: Iowan Old Style, then Palatino, then Georgia.
    public static func display(_ size: CGFloat, _ scale: CGFloat, id: String? = nil) -> Font {
        Metrics.shared.record(font: Double(size), id: id)
        let pt = LayoutScale.font(size, scale)
        let family = LuminaFontSize.displayFamilies.first { NSFont(name: $0, size: pt) != nil } ?? "Georgia"
        return Font.custom(family, fixedSize: pt)
    }

    /// Key hints: SF Mono.
    public static func mono(_ size: CGFloat = LuminaFontSize.monoHint, _ scale: CGFloat, id: String? = nil) -> Font {
        Metrics.shared.record(font: Double(size), id: id)
        return Font.system(size: LayoutScale.font(size, scale), design: .monospaced)
    }
}

private struct LuminaScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
public extension EnvironmentValues {
    /// The UI scale S (LAYOUT_SIZING §3). Computed once per window by the shell.
    var luminaScale: CGFloat { get { self[LuminaScaleKey.self] } set { self[LuminaScaleKey.self] = newValue } }
}

public extension CGFloat {
    /// A chrome size in points × S, rounded to 1pt.
    func scaled(_ s: CGFloat) -> CGFloat { LayoutScale.px(self, s) }
}
public extension Int {
    func scaled(_ s: CGFloat) -> CGFloat { LayoutScale.px(CGFloat(self), s) }
}
public extension Double {
    func scaled(_ s: CGFloat) -> CGFloat { LayoutScale.px(CGFloat(self), s) }
}
