import AppKit
import SwiftUI

/// Semantic design tokens for Lumina's ethereal white-and-gray photographic workspace.
/// Views must consume these tokens — never scatter literal palette colors.
enum LuminaTokens {

    enum Surface {
        static let porcelain = Color(light: "FFFFFF", dark: "141413")
        static let mist = Color(light: "F6F6F4", dark: "1C1C1B")
        static let secondary = Color(light: "F0F0EE", dark: "242423")
        static let elevated = Color(light: "FAFAF9", dark: "1F1F1E")
        static let focusMatte = Color(light: "565654", dark: "1B1B1A")
        static let inspectionMatte = Color(hex: "1B1B1A")
    }

    enum Ink {
        static let primary = Color(light: "282828", dark: "E8E8E5")
        static let secondary = Color(light: "676767", dark: "A8A8A4")
        static let tertiary = Color(light: "969696", dark: "7A7A76")
        static let inspection = Color(hex: "E8E8E5")
    }

    enum Status {
        static let selection = Color(hex: "0E9EE4")
        static let keep = Color(hex: "9CC355")
        static let needsAttention = Color(hex: "B57614")
        static let reject = Color(hex: "AD2111")
        static let anchor = Color(light: "282828", dark: "E8E8E5")
    }

    enum Line {
        static let hairline = Color(
            light: Color(hex: "282828").opacity(0.10),
            dark: Color(hex: "E8E8E5").opacity(0.12)
        )
        static var hairlineWidth: CGFloat {
            1.0 / (NSScreen.main?.backingScaleFactor ?? 2)
        }
    }

    enum Depth {
        static let softShadow = Color(hex: "282828").opacity(0.08)
        static let softShadowRadius: CGFloat = 18
        static let softShadowY: CGFloat = 6
    }

    enum Radius {
        static let photographLarge: CGFloat = 20
        static let photographThumb: CGFloat = 12
        static let button: CGFloat = 12
        static let dock: CGFloat = 20
        static let panel: CGFloat = 18
        static let card: CGFloat = 18
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 36
        static let xxl: CGFloat = 56
        static let section: CGFloat = 48
    }

    enum HitTarget {
        static let minimum: CGFloat = 44
        static let decision: CGFloat = 56
        static let dockHeight: CGFloat = 72
    }

    enum Typeface {
        static func title(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func brand(_ size: CGFloat = 28) -> Font {
            .system(size: size, weight: .regular, design: .serif)
        }
        static func control(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        static func meta(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        static func count(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .medium, design: .default).monospacedDigit()
        }
    }

    enum Motion {
        static let control = Animation.easeOut(duration: 0.15)
        static let photo = Animation.easeOut(duration: 0.18)
        static let route = Animation.easeOut(duration: 0.20)
        static let fidelity = Animation.easeOut(duration: 0.16)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(light: String, dark: String) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
