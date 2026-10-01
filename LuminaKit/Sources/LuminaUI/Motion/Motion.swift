import SwiftUI

// WP-1. Motion helpers (README "Motion", R-60, R-61). Durations and curves come from
// `LuminaMotion` (generated); reduced motion turns every one of them off. Pass the view's
// `@Environment(\.accessibilityReduceMotion)` as `reduce`.
//
// Nothing here repeats: every helper runs once and ends on the view's resting state (R-61).

public extension View {
    /// Fade in and out over 120 ms (panels, overlays).
    func luminaPanelFade(_ reduce: Bool) -> some View { transition(.luminaPanelFade(reduce)) }

    /// The saved card: fades in while rising 4pt over 180 ms; leaves with a plain fade.
    func luminaRise(_ reduce: Bool) -> some View { transition(.luminaRise(reduce)) }

    /// The "pop" a keep badge arrives with: scale 0.4 → 1.18 → 1 over 200 ms, fading in on the way up.
    /// Runs once when the view appears.
    func luminaPop(_ reduce: Bool) -> some View { modifier(LuminaPop(reduce: reduce, trigger: 0, onAppear: true)) }

    /// The same pop, replayed each time `trigger` changes (a badge that stays in the tree).
    func luminaPop<T: Equatable>(_ reduce: Bool, trigger: T) -> some View { modifier(LuminaPop(reduce: reduce, trigger: trigger, onAppear: false)) }

    /// A screen arriving after a step change: fades in over 160 ms, no slide (R-60). The screen
    /// it replaces is gone at once, so two screens are never on top of each other.
    /// `animated: false` shows it at once (the screen a window opens on).
    func luminaStepFade(_ reduce: Bool, animated: Bool = true) -> some View { modifier(LuminaFadeIn(animation: animated ? LuminaMotion.stepFade(reduce) : nil)) }

}

/// Run `body` with one of `LuminaMotion`'s animations; with reduced motion (a nil animation) the
/// change lands at once, even inside someone else's `withAnimation`.
public func luminaAnimate(_ animation: Animation?, _ body: () -> Void) {
    if let animation { withAnimation(animation, body) } else {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t, body)
    }
}

public extension AnyTransition {
    /// Panels and overlays: opacity over 120 ms.
    static func luminaPanelFade(_ reduce: Bool) -> AnyTransition { .opacity.animation(LuminaMotion.panelFade(reduce)) }

    /// The saved card: opacity plus a 4pt rise over 180 ms on the way in, opacity on the way out.
    static func luminaRise(_ reduce: Bool) -> AnyTransition {
        guard !reduce else { return .opacity.animation(nil) }
        return .asymmetric(insertion: .offset(y: LuminaMotion.savedCardRise).combined(with: .opacity), removal: .opacity)
            .animation(LuminaMotion.savedCard(reduce))
    }
}

/// The "pop" keyframes (tokens.json `keepPop`): [t, scale, opacity] = [0, 0.4, 0], [0.6, 1.18, 1], [1, 1, 1].
public enum LuminaPopCurve {
    public static let startScale: CGFloat = 0.4, peakScale: CGFloat = 1.18, peakAt = 0.6
    /// Scale and opacity at `t` (0…1 of the 200 ms), for views that draw the pop themselves.
    public static func value(at t: Double) -> (scale: CGFloat, opacity: Double) {
        let t = min(1, max(0, t))
        if t < peakAt {
            let u = easeOut(t / peakAt)
            return (startScale + (peakScale - startScale) * u, u)
        }
        return (peakScale + (1 - peakScale) * easeOut((t - peakAt) / (1 - peakAt)), 1)
    }
    static func easeOut(_ u: Double) -> Double { 1 - (1 - u) * (1 - u) }
}

private struct PopValue { var scale: CGFloat = 1; var opacity = 1.0 }

private struct LuminaPop<T: Equatable>: ViewModifier {
    let reduce: Bool
    let trigger: T
    let onAppear: Bool
    @State private var appeared = false

    func body(content: Content) -> some View {
        if reduce {
            content
        } else {
            // The resting value is the last keyframe, so the view is whole before and after.
            content.keyframeAnimator(initialValue: PopValue(), trigger: Key(appeared: appeared, trigger: trigger)) { view, v in
                view.scaleEffect(v.scale).opacity(v.opacity)
            } keyframes: { _ in
                let up = LuminaMotion.keepPopSeconds * LuminaPopCurve.peakAt, down = LuminaMotion.keepPopSeconds - up
                KeyframeTrack(\.scale) {
                    MoveKeyframe(LuminaPopCurve.startScale)
                    CubicKeyframe(LuminaPopCurve.peakScale, duration: up)
                    CubicKeyframe(1, duration: down)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: up)
                }
            }
            .onAppear { if onAppear { appeared = true } }
        }
    }

    private struct Key: Equatable { var appeared: Bool; var trigger: T }
}

private struct LuminaFadeIn: ViewModifier {
    let animation: Animation?
    @State private var shown: Bool

    init(animation: Animation?) { self.animation = animation; _shown = State(initialValue: animation == nil) }

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0)
            .onAppear { if !shown { withAnimation(animation) { shown = true } } }
    }
}
