import SwiftUI

/// Compatibility bridge for legacy import / export surfaces.
/// New shell views must use `LuminaTokens` directly.
enum LuminaAtmosphere {
    static let void = LuminaTokens.Surface.inspectionMatte
    static let ink = LuminaTokens.Ink.primary
    static let mist = LuminaTokens.Surface.mist
    static let whisper = LuminaTokens.Ink.secondary
    static let breath = LuminaTokens.Ink.tertiary
    static let affirm = LuminaTokens.Status.selection

    static var emptyGradient: LinearGradient {
        LinearGradient(
            colors: [
                LuminaTokens.Surface.porcelain,
                LuminaTokens.Surface.mist,
                LuminaTokens.Surface.secondary
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Motion {
        static let reveal = LuminaTokens.Motion.photo
        static let settle = LuminaTokens.Motion.route
        static let condense = LuminaTokens.Motion.control
        static let dissolve = LuminaTokens.Motion.control
        static let bloom = LuminaTokens.Motion.route
    }

    enum Typeface {
        static func brand(_ size: CGFloat = 44) -> Font { LuminaTokens.Typeface.brand(size) }
        static func display(_ size: CGFloat = 28) -> Font { LuminaTokens.Typeface.title(size) }
        static func body(_ size: CGFloat = 15) -> Font { LuminaTokens.Typeface.control(size) }
        static func caption(_ size: CGFloat = 12) -> Font { LuminaTokens.Typeface.meta(size) }
    }
}

struct LuminaAtmosphereBackdrop: View {
    var body: some View {
        LuminaTokens.Surface.porcelain.ignoresSafeArea()
    }
}
