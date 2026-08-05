import AppKit
import SwiftUI

/// Semantic design tokens for Lumina's editorial porcelain workspace.
/// Visual grammar follows a restrained light-table aesthetic — photographs supply color.
enum LuminaTokens {

    enum Surface {
        /// Workspace canvas — always light, even under system Dark Mode.
        static let porcelain = Color(hex: "FFFFFF")
        /// Sidebar rails, recessed panels — warm grey field.
        static let rail = Color(hex: "F3F3F2")
        static let mist = Color(hex: "F3F3F2")
        /// Photo wells, inset regions — slightly deeper grey.
        static let well = Color(hex: "ECECEA")
        static let secondary = Color(hex: "ECECEA")
        /// Selected rows, elevated chips — white highlight on grey field.
        static let highlight = Color(hex: "FFFFFF")
        static let elevated = Color(hex: "FFFFFF")
        static let hover = Color(hex: "282828").opacity(0.08)
        static let focusMatte = Color(hex: "565654")
        static let inspectionMatte = Color(hex: "1B1B1A")
        static let focusScrim = Color(hex: "282828").opacity(0.10)
        /// Darkroom table (Direction A).
        static let table = Color(hex: "141312")
        static let tableMat = Color(hex: "232120")
        static let tableMatLifted = Color(hex: "33302E")
        static let tableHead = Color(hex: "0F0E0D")
        static let shelf = Color(hex: "0C0B0A").opacity(0.92)
        static let shelfOpaque = Color(hex: "0C0B0A")
        static let advanceFill = Color(hex: "F2EFE9")
        /// Treatment controls column.
        static let side = Color(hex: "F3F3F2")
    }

    enum Ink {
        static let primary = Color(hex: "282828")
        static let strongSecondary = Color(hex: "3C3836")
        static let secondary = Color(hex: "676767")
        static let tertiary = Color(hex: "969696")
        static let inspection = Color(hex: "E8E8E5")
        static let onTable = Color(hex: "EFECE6")
        static let onTableSecondary = Color(hex: "98938B")
        static let onAdvance = Color(hex: "141312")
    }

    enum Status {
        static let selection = Color(hex: "0E9EE4")
        static let keep = Color(hex: "9CC355")
        static let needsAttention = Color(hex: "B57614")
        static let reject = Color(hex: "AD2111")
        static let anchor = Color(hex: "282828")
    }

    enum Line {
        static let hairline = Color(hex: "282828").opacity(0.10)
        static let emphasis = Color(hex: "282828").opacity(0.18)
        static var hairlineWidth: CGFloat {
            1.0 / (NSScreen.main?.backingScaleFactor ?? 2)
        }
    }

    enum Depth {
        /// Reserved for transient Focus overlay separation only.
        static let focusShadow = Color(hex: "282828").opacity(0.06)
        static let focusShadowRadius: CGFloat = 24
        static let focusShadowY: CGFloat = 8
    }

    enum Radius {
        static let photographLarge: CGFloat = 4
        static let photographThumb: CGFloat = 3
        static let button: CGFloat = 999
        static let dock: CGFloat = 999
        static let panel: CGFloat = 999
        static let card: CGFloat = 0
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 52
        static let section: CGFloat = 44
        static let workspaceMargin: CGFloat = 28
    }

    enum HitTarget {
        static let minimum: CGFloat = 44
        static let decision: CGFloat = 48
        static let command: CGFloat = 64
        static let dockHeight: CGFloat = 56
        static let header: CGFloat = 54
        static let commandBar: CGFloat = 132
    }

    enum Typeface {
        private static let editorialName = "Iowan Old Style"

        /// Shoot titles and editorial group titles — Iowan Old Style when available.
        static func editorial(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if NSFont(name: editorialName, size: size) != nil {
                return .custom(editorialName, size: size).weight(weight)
            }
            return .system(size: size, weight: weight, design: .serif)
        }

        /// Legacy alias — maps to editorial serif scale.
        static func title(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            editorial(size, weight: weight)
        }

        static func brand(_ size: CGFloat = 28) -> Font {
            editorial(size)
        }

        /// Navigation, controls, group headings — SF Pro / system sans.
        static func navigation(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func control(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            navigation(size, weight: weight)
        }

        /// Large sans group headings with slightly negative tracking.
        static func groupHeading(_ size: CGFloat = 21) -> Font {
            navigation(size)
        }

        /// Body / editorial context — serif at ~1.6 line height (apply via lineSpacing in views).
        static func body(_ size: CGFloat = 17) -> Font {
            editorial(size)
        }

        static func meta(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
            navigation(size, weight: weight)
        }

        static func count(_ size: CGFloat = 13) -> Font {
            navigation(size).monospacedDigit()
        }

        /// Negative tracking for large sans headings (apply in views).
        static let groupHeadingTracking: CGFloat = -0.3
        static let bodyLineSpacing: CGFloat = 7
    }

    enum Motion {
        static let control = Animation.easeOut(duration: 0.18)
        static let photo = Animation.easeOut(duration: 0.28)
        static let selection = Animation.easeInOut(duration: 0.32)
        static let develop = Animation.easeInOut(duration: 0.55)
        static let route = Animation.easeOut(duration: 0.24)
        static let fidelity = Animation.easeOut(duration: 0.22)
        static let reveal = Animation.easeOut(duration: 0.34)

        /// Darkroom command-layer timings.
        static let handlingFeedback: Animation? = nil // 1 frame — no animation
        static let lift = Animation.easeOut(duration: 0.100)
        static let travel = Animation.easeOut(duration: 0.180)
        static let travelFast = Animation.easeOut(duration: 0.090)
        static let stage = Animation.easeInOut(duration: 0.140)
        static let shelfIn = Animation.easeOut(duration: 0.120)
        static let fidelityCrossfade = Animation.easeOut(duration: 0.120)
        static let reduceMotionKeyline = Animation.easeOut(duration: 0.090)
    }

    /// Rolling confirm cadence — 3 confirms inside 8 s shortens travel to 90 ms until 10 s idle.
    @MainActor
    @Observable
    final class FastRunTracker {
        private var confirmTimes: [Date] = []
        private var fastUntil: Date?

        var travelAnimation: Animation {
            if let fastUntil, Date() < fastUntil {
                return Motion.travelFast
            }
            return Motion.travel
        }

        func noteConfirm() {
            let now = Date()
            confirmTimes.append(now)
            confirmTimes = confirmTimes.filter { now.timeIntervalSince($0) <= 8 }
            if confirmTimes.count >= 3 {
                fastUntil = now.addingTimeInterval(10)
            }
        }

        func noteIdle(seconds: TimeInterval = 10) {
            guard let last = confirmTimes.last else { return }
            if Date().timeIntervalSince(last) >= seconds {
                fastUntil = nil
            }
        }
    }
}

// MARK: - Workspace appearance

/// Forces the porcelain editorial workspace to stay light regardless of system Dark Mode.
struct LuminaWorkspaceAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
    }
}

extension View {
    func luminaWorkspaceAppearance() -> some View {
        modifier(LuminaWorkspaceAppearance())
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
