import AppKit
import SwiftUI

/// Hi-fi pass design tokens — literal values from `design/hifi-reference.html` (hi-fi page CSS).
enum HiFiTokens {

    enum SwimLane {
        /// Faint full-width row lane — `background:rgba(242,239,233,0.07)` from hi-fi page CSS.
        static let fill = Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255, opacity: 0.07)
        /// Lane header inset — `box-shadow:inset 0 1.5px 0 rgba(242,239,233,0.22)`.
        static let headerInset = Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255, opacity: 0.22)
        /// PARCH anchor — `#F2EFE9`.
        static let parchment = Color(hex: "F2EFE9")
    }

    enum Histogram {
        static let width: CGFloat = 252
        static let height: CGFloat = 64
    }

    enum Crop {
        static let handleSize: CGFloat = 18
        static let minimumHit: CGFloat = 44
    }

    enum Ring {
        /// User selection — charcoal family (`#2E2E2C` / INK from hi-fi page).
        static let selection = Color(hex: "2E2E2C")
        /// Table proposal halo — warm-white (`rgba(255,236,205,…)` from hi-fi page).
        static let halo = Color(red: 255 / 255, green: 236 / 255, blue: 205 / 255)
        static let haloOpacity: Double = 0.95
        /// Plain shipped halo stroke.
        static let haloWidth: CGFloat = 1.5
        /// Second-order response halo — `halo2` ring in hi-fi page CSS.
        static let secondOrderOpacity: Double = 0.45
        static let secondOrderWidth: CGFloat = 2

        /// Contract: user selection and table halo must never share the same color.
        static func assertDistinctSelectionAndHalo() {
            assert(selection != halo, "selection ring and table halo must not share the same color")
        }
    }

    enum DockedChipDrag {
        /// Same grab / carry / place timings as comparison frames (`LuminaTokens.Motion`).
        static let grabDuration: TimeInterval = 0.100
        static let carryDuration: TimeInterval = 0.180
        static let placeDuration: TimeInterval = 0.140
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
