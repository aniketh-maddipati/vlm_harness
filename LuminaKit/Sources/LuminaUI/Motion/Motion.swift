import SwiftUI

// WP-1. Motion helpers (README "Motion", R-60, R-61). Durations and curves come from
// `LuminaMotion` (generated); reduced motion turns every one of them off.

public extension View {
    /// Fade in and out over 120 ms (panels, overlays).
    func luminaPanelFade(_ reduce: Bool) -> some View { transition(.opacity.animation(LuminaMotion.panelFade(reduce))) }
}
