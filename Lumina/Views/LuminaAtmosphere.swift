import SwiftUI

/// Ethereal visual system — photos are the only hard surface; chrome is weather.
enum LuminaAtmosphere {
    /// Void behind photons. Not "dark mode UI" — photographic black.
    static let void = Color.black

    /// Soft ink for non-browse planes (empty / import / finish).
    static let ink = Color(red: 0.07, green: 0.075, blue: 0.08)
    static let mist = Color.white.opacity(0.06)
    static let whisper = Color.white.opacity(0.55)
    static let breath = Color.white.opacity(0.28)
    static let affirm = Color(red: 0.82, green: 0.74, blue: 0.58) // warm stone, not traffic green

    static var emptyGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.095, blue: 0.10),
                Color(red: 0.05, green: 0.052, blue: 0.055),
                Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Motion {
        /// Tile / photon arrival.
        static let reveal = Animation.easeOut(duration: 0.55)
        /// Accept / auto-commit settle.
        static let settle = Animation.easeInOut(duration: 0.42)
        /// Chrome condenses after rip stillness.
        static let condense = Animation.easeInOut(duration: 0.38)
        /// Chrome dissolves when ripping.
        static let dissolve = Animation.easeOut(duration: 0.18)
        /// Publish bloom.
        static let bloom = Animation.easeInOut(duration: 0.7)
    }

    enum Typeface {
        static func brand(_ size: CGFloat = 44) -> Font {
            .system(size: size, weight: .light, design: .serif)
        }

        static func display(_ size: CGFloat = 28) -> Font {
            .system(size: size, weight: .regular, design: .serif)
        }

        static func body(_ size: CGFloat = 15) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func caption(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }
    }
}

/// Soft full-bleed atmosphere behind non-browse states.
struct LuminaAtmosphereBackdrop: View {
    var body: some View {
        ZStack {
            LuminaAtmosphere.emptyGradient.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }
}
