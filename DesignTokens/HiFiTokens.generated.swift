// HiFiTokens.generated.swift
// GENERATED from design/tokens.yaml — do not edit by hand.
// Re-run: python3 Scripts/harness/codegen/tokens_codegen.py
// tokens-hash: 8461f73252684583bcc5356f280d0710f039fab31d7f88e9003dc6aac43ee2e0
// version: 6.4-a7-cleanup
// contract: design/contract-v6.md

import CoreGraphics
import Foundation
import SwiftUI

enum HiFiTokens {
    enum Ring {
        static let selectionColor: String = "2E2E2C" // cite: D58, WG-hand, L1 — User hand / focus charcoal family (INK).
        static let selectionFocusWidth: CGFloat = 3.0 // cite: WG-hand, D58 — Resting-table focus ring.
        static let selectionWidth: CGFloat = 1.5 // cite: D58, WG-hand — Multi-select charcoal stroke.
        static let haloColor: String = "FFECCD" // cite: D57, D58, WG-ripple — Warm-white table proposal halo RGB.
        static let haloOpacity: Double = 0.95 // cite: D57, D58
        static let haloWidth: CGFloat = 1.5 // cite: D57, D58 — Plain shipped halo. PERSUADE target uses preview change + this stroke.
        static let secondOrderOpacity: Double = 0.45 // cite: WG-ripple, D57
        static let secondOrderWidth: CGFloat = 2.0 // cite: WG-ripple
        static let fallbackAHaloWidth: CGFloat = 2.5 // cite: D57 — Designated Fallback A (brighter ring). Debug-flag socket until spike seals.
        static let fallbackAHaloColor: String = "FFFFFF" // cite: D57
        static let fallbackBGrowth: Bool = false // cite: D57 — Rejected — must not ship.
        static let armedControlRingWidth: CGFloat = 2.0 // cite: D24, WG-chrome
        static let distinctSelectionAndHaloRequired: Bool = true // cite: D58, WG-hand

        // Color conveniences for UI call sites (hex strings above are source of truth).
        static let selection = SwiftUI.Color(hifiHex: selectionColor)
        static let halo = SwiftUI.Color(hifiHex: haloColor)
        static let fallbackA = SwiftUI.Color(hifiHex: fallbackAHaloColor)

        static func assertDistinctSelectionAndHalo() {
            assert(distinctSelectionAndHaloRequired, "selection/halo must stay distinct")
            assert(selection != halo, "selection ring and table halo must not share the same color")
        }
    }

    enum Color {
        static let ink: String = "2E2E2C" // cite: D58, WG-chrome
        static let parchment: String = "F2EFE9" // cite: WG-chrome, D58
        static let shell: String = "F6F4F0" // cite: WG-chrome
        static let tablePlate: String = "8D8C8A" // cite: WG-chrome
        static let subink: String = "8A857E" // cite: WG-chrome
        static let reject: String = "AD2111" // cite: L1 — Shape marks remain primary; color never sole channel.
        static let keep: String = "9CC355" // cite: L1
        static let selectionAccent: String = "0E9EE4" // cite: WG-hand — Not a substitute for charcoal selection ring on the table.
        static let porcelain: String = "FFFFFF" // cite: WG-chrome
        static let tableDark: String = "141312" // cite: WG-chrome
        static let onTable: String = "EFECE6" // cite: WG-chrome
        static let swimlaneFillOpacity: Double = 0.07 // cite: WG-gaps, D64, A6 — Socket only — lane plates shelved (A6). rgba(242,239,233,0.07) over table if a ruled experiment re-enters.
        static let rejectDimOpacity: Double = 0.45 // cite: L1, D59 — Rejects dim in place — recognizable, recoverable.
    }

    enum Grid {
        static let burstGap: CGFloat = 3.0 // cite: D49, WG-gaps
        static let sceneGap: CGFloat = 20.0 // cite: D49, WG-gaps — Approximate same-scene gap; quantized, not interpolated at rest.
        static let seamGap: String? = nil // cite: WG-gaps — Shelved — must not ship a third gap vocabulary.
        static let elasticityStepsPx: [CGFloat] = [210.0, 140.0, 96.0, 64.0] // cite: D49, D57 — Distant-first periphery compression steps.
        static let nearRowMateMin: CGFloat = 120.0 // cite: D57
        static let nearRowMateMax: CGFloat = 140.0 // cite: D57
        static let stripEvidenceHeight: CGFloat = 90.0 // cite: D57 — 90 px evidence strip for PERSUADE judgement.
        static let photoRadiusLarge: CGFloat = 4.0 // cite: WG-chrome
        static let photoRadiusThumb: CGFloat = 3.0 // cite: WG-chrome
        static let densitySnap: String = "named_steps_only" // cite: D49 — Pinch density snaps; nothing interpolates at rest. Named step list OPEN.
    }

    enum Typography {
        static let editorialFamily: String = "Iowan Old Style" // cite: WG-chrome — Fallback Georgia / system serif.
        static let monoFamily: String = "ui-monospace, Menlo, monospace" // cite: WG-chrome
        static let sansSystem: String = "SF Pro / system" // cite: WG-chrome
        static let exifSize: CGFloat = 11.5 // cite: WG-chrome
        static let chipSize: CGFloat = 11.0 // cite: D41, WG-fidelity
        static let footerSize: CGFloat = 11.5 // cite: WG-chrome
        static let groupHeadingTracking: CGFloat = -0.3 // cite: WG-chrome
    }

    enum Motion {
        static let warmInCrossfade: TimeInterval = 0.12 // cite: D57, D43 — Adapted preview warm-in; change itself must be visible.
        static let warmInCrossfadeMs: Int = 120 // cite: D57, D43 — Adapted preview warm-in; change itself must be visible.
        static let fidelityCrossfade: TimeInterval = 0.12 // cite: D43, D57
        static let fidelityCrossfadeMs: Int = 120 // cite: D43, D57
        static let bannerIn: TimeInterval = 0.12 // cite: WG-ripple
        static let bannerInMs: Int = 120 // cite: WG-ripple
        static let shelfIn: TimeInterval = 0.12 // cite: WG-chrome
        static let shelfInMs: Int = 120 // cite: WG-chrome
        static let photoBirth: TimeInterval = 0.34 // cite: D27, WG-photos — Opacity only at birth.
        static let photoBirthMs: Int = 340 // cite: D27, WG-photos — Opacity only at birth.
        static let lift: TimeInterval = 0.1 // cite: L1
        static let liftMs: Int = 100 // cite: L1
        static let travel: TimeInterval = 0.18 // cite: L1
        static let travelMs: Int = 180 // cite: L1
        static let travelFast: TimeInterval = 0.09 // cite: L1
        static let travelFastMs: Int = 90 // cite: L1
        static let stage: TimeInterval = 0.14 // cite: WG-ripple
        static let stageMs: Int = 140 // cite: WG-ripple
        static let dockedChipGrab: TimeInterval = 0.1 // cite: WG-ripple
        static let dockedChipGrabMs: Int = 100 // cite: WG-ripple
        static let dockedChipCarry: TimeInterval = 0.18 // cite: WG-ripple
        static let dockedChipCarryMs: Int = 180 // cite: WG-ripple
        static let dockedChipPlace: TimeInterval = 0.14 // cite: WG-ripple
        static let dockedChipPlaceMs: Int = 140 // cite: WG-ripple
        static let reduceMotionKeyline: TimeInterval = 0.09 // cite: D27, L2
        static let reduceMotionKeylineMs: Int = 90 // cite: D27, L2
        static let chromeFadeOut: TimeInterval = 0.25 // cite: D27, WG-chrome — Chrome fade out; table hover hint out leg.
        static let chromeFadeOutMs: Int = 250 // cite: D27, WG-chrome — Chrome fade out; table hover hint out leg.
        static let placeReturn: TimeInterval = 0.2 // cite: D27, D28 — Place/return one spring ≤2% overshoot.
        static let placeReturnMs: Int = 200 // cite: D27, D28 — Place/return one spring ≤2% overshoot.
        static let springMaxOvershoot: Double = 0.02 // cite: D28
        static let springTrajectoryFrames: Int = 40 // cite: D28 — Transform-only observation window.
        static let springTrajectorySampleRateHz: Int = 120 // cite: D28
        static let springDeadStopEpsilon: Double = 0.001 // cite: D28
        static let springRetargetContinuityEpsilon: Double = 0.000001 // cite: D28
        static let springReducedMotionOvershoot: Double = 0.0 // cite: D27, D28
        static let handlingFeedbackFrames: Int = 1 // cite: L1 — One frame — no animation on handling feedback.
        static let settlePositiveSignal: String = "final_rung_crossfade_only" // cite: D43 — No chip invented.
        static let photoFocus: TimeInterval = 0.28 // cite: D27, WG-photos — Filmstrip focus chrome — scale/shadow only; not birth opacity (photo_birth).
        static let photoFocusMs: Int = 280 // cite: D27, WG-photos — Filmstrip focus chrome — scale/shadow only; not birth opacity (photo_birth).
        static let routeTransition: TimeInterval = 0.24 // cite: D27, WG-chrome — P0 contact sheet ↔ single-photo route.
        static let routeTransitionMs: Int = 240 // cite: D27, WG-chrome — P0 contact sheet ↔ single-photo route.
        static let selectionRing: TimeInterval = 0.32 // cite: D27, WG-hand — Legacy shell selection ring — W8 retires path.
        static let selectionRingMs: Int = 320 // cite: D27, WG-hand — Legacy shell selection ring — W8 retires path.
        static let developReveal: TimeInterval = 0.55 // cite: D27, WG-chrome — Legacy develop crossfade — W8 retires path.
        static let developRevealMs: Int = 550 // cite: D27, WG-chrome — Legacy develop crossfade — W8 retires path.
        static let fidelitySettle: TimeInterval = 0.22 // cite: D43, D57 — Legacy fidelity settle — W8 retires path.
        static let fidelitySettleMs: Int = 220 // cite: D43, D57 — Legacy fidelity settle — W8 retires path.
    }

    enum Layout {
        static let minWindowWidth: CGFloat = 1280.0 // cite: D49, WG-chrome
        static let minWindowHeight: CGFloat = 800.0 // cite: D49, WG-chrome — Implied by 800 pt rail.
        static let histogramWidth: CGFloat = 252.0 // cite: WG-chrome
        static let histogramHeight: CGFloat = 64.0 // cite: WG-chrome
        static let editRailRowHeight: CGFloat = 46.0 // cite: WG-chrome, D49
        static let editRailRowCount: Int = 10 // cite: WG-chrome
        static let collapseOrder: [String] = ["context", "strip", "hero"] // cite: WG-chrome — Never targets.
        static let openCardMinTarget: CGFloat = 120.0 // cite: WG-chrome
        static let controlRowHeight: CGFloat = 50.0 // cite: D24
        static let thumbRest: CGFloat = 16.0 // cite: D24
        static let thumbArmed: CGFloat = 18.0 // cite: D24
        static let thumbAdjusting: CGFloat = 22.0 // cite: D24
    }

    enum Gap {
        static let burst: CGFloat = 3.0 // cite: D49, WG-gaps
        static let scene: CGFloat = 20.0 // cite: D49, WG-gaps — Approximate same-scene gap; quantized, not interpolated at rest.
        static let spacingXs: CGFloat = 6.0 // cite: WG-chrome
        static let spacingSm: CGFloat = 10.0 // cite: WG-chrome
        static let spacingMd: CGFloat = 16.0 // cite: WG-chrome
        static let spacingLg: CGFloat = 24.0 // cite: WG-chrome
        static let spacingXl: CGFloat = 32.0 // cite: WG-chrome
        static let workspaceMargin: CGFloat = 28.0 // cite: WG-chrome
    }

    enum Hit {
        static let minimum: CGFloat = 44.0 // cite: L1, WG-hand
        static let decision: CGFloat = 48.0 // cite: L1
        static let command: CGFloat = 64.0 // cite: L1
        static let cropHandle: CGFloat = 18.0 // cite: WG-crop
        static let cropMinimum: CGFloat = 44.0 // cite: WG-crop, L1
        static let dockHeight: CGFloat = 56.0 // cite: WG-chrome
        static let header: CGFloat = 54.0 // cite: WG-chrome
    }

    enum Slider {
        static let valueEcho: String = "during_adjustment_only" // cite: D24, D48
        static let settleDisplay: String = "dark_value_on_rail" // cite: D24, D43
        static let resetGesture: String = "option_click_only" // cite: WG-chrome — Double-click means expand/return only.
        static let clippingGrammar: String = "hold_j_anytime" // cite: D42, D21, L2, A4 — Hold-J shows clipping anytime; release returns. Adjust-only trigger is a subset.
        static let clippingHoldKey: String = "J" // cite: D42, A4 — Completes R-5.2.
        static let hoverHandlers: String = "forbidden" // cite: D48
    }

    enum Grammar {
        static let decisionKeys: [String] = ["P", "X", "Return", "ShiftReturn", "A"] // cite: L1, D59, D60
        static let decisionKeysSwallowRepeat: Bool = true // cite: D60, L1
        static let travelKeysAutorepeat: Bool = true // cite: L1
        static let scopeRings: [String] = ["row", "scene", "shoot"] // cite: WG-scope
        static let postCommitFocus: String = "next_row_first_kept" // cite: D62
        static let developCriticalPath: String = "gated_on_taste_proof" // cite: D46
        static let adaptedPreviewSource: String = "proxy_linear" // cite: D57 — Never embedded JPEG for adapted previews.
        static let loupeOnStagedStrip: String = "adapted_preview" // cite: D57, L2
        static let exportStates: [String] = ["quiet_text", "quiet_outline", "dark_primary"] // cite: D61
        static let rejectsFileTouch: String = "post_export_trash_offer_only" // cite: D36
        static let hover: String = "deleted" // cite: D48
        static let networkEgress: String = "zero_ideal" // cite: D45, D51, D52 — Local-only on every build — beta, wave, launch. A7 withdrawn (A13, Batch 2); no TestFlight crash-reporting exception.
        static let betaTestflightCrashReporting: String = "withdrawn" // cite: D45, D66, A13 — A7 withdrawn (A13, Batch 2). betaDiagnostics must be null on every wave/beta build; F11.6 asserts. All builds direct-notarized + local-only.
        static let betaLicensing: String = "none" // cite: D52, D66, A8 — Wave builds free; R-I.3 post-test pre-launch.
        static let mvpTestFloor: String = "apple_silicon_macos_14_plus" // cite: D65, A1 — Intel never.
        static let cropMode: String = "work_state_latch" // cite: D23, D63, A2 — Fixed frame; photo slides beneath; rising grid; matte; non-destructive.
        static let cropKeys: [String] = ["R", "O"] // cite: D63, A2 — R frees aspect; O flips orientation. FLAG — Claude pick; validate wave-one.
        static let cropDecisionKeyRemap: String = "forbidden" // cite: D23, D63, A2 — A and X never remapped inside crop; keep global meanings.
        static let cropBanner: String = "Crop · ⏎ applies · Esc cancels" // cite: D63, A2
        static let pointerCullMarks: String = "persistent_on_focused_frame" // cite: D47, A3 — Always visible; never hover; ≥44pt; wear P/X; same-mark-clears parity.
        static let pointerCullMarkMinHit: CGFloat = 44.0 // cite: D47, A3, L1
    }

    // MARK: - Compatibility aliases (yaml-backed; do not hand-literal)

    enum SwimLane {
        /// Socket only — lane plates shelved (D64 / A6).
        static let fillOpacity: Double = Color.swimlaneFillOpacity
        static let parchment = SwiftUI.Color(hifiHex: Color.parchment)
        static var fill: SwiftUI.Color { parchment.opacity(fillOpacity) }
        /// Pre-yaml chrome inset retained until CP1 layout seal owns a token.
        static let headerInset = SwiftUI.Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255, opacity: 0.22)
    }

    enum Histogram {
        static let width: CGFloat = Layout.histogramWidth
        static let height: CGFloat = Layout.histogramHeight
    }

    enum Crop {
        static let handleSize: CGFloat = Hit.cropHandle
        static let minimumHit: CGFloat = Hit.cropMinimum
    }

    enum DockedChipDrag {
        static let grabDuration: TimeInterval = Motion.dockedChipGrab
        static let carryDuration: TimeInterval = Motion.dockedChipCarry
        static let placeDuration: TimeInterval = Motion.dockedChipPlace
    }

}

private extension SwiftUI.Color {
    init(hifiHex: String) {
        let cleaned = hifiHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
