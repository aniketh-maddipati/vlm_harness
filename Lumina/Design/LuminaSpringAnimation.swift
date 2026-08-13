import SwiftUI

/// SwiftUI bridge — maps owned `LuminaSpring` params to `Animation.spring`.
enum LuminaSpringAnimation {
    static func animation(durationMs: Double, curve: LuminaSpringCurve) -> Animation {
        animation(params: LuminaSpring.params(durationMs: durationMs, curve: curve))
    }

    static func animation(params: LuminaSpringParams) -> Animation {
        let mass = max(params.mass, 1e-9)
        let stiffness = params.stiffness
        let damping = params.damping
        let response = 2 * Double.pi / sqrt(stiffness / mass)
        let dampingFraction = damping / (2 * sqrt(stiffness * mass))
        return .spring(response: response, dampingFraction: dampingFraction)
    }

    /// D27 — transform / shadow / position: snap when reduced motion is on.
    static func transform(
        reduceMotion: Bool,
        durationMs: Double,
        curve: LuminaSpringCurve = .easeOut
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return animation(durationMs: durationMs, curve: curve)
    }

    /// D27 — dim and fidelity crossfades remain; critically damped under reduced motion.
    static func crossfade(reduceMotion: Bool, durationMs: Double) -> Animation? {
        if reduceMotion {
            return animation(params: LuminaSpring.paramsReducedMotion(durationMs: durationMs))
        }
        return animation(durationMs: durationMs, curve: .easeOut)
    }

    /// SPIKE B sealed place/return — reads `place_return` ms from HiFiTokens only.
    static func placeReturn(reduceMotion: Bool) -> Animation? {
        let ms = Double(HiFiTokens.Motion.placeReturnMs)
        return transform(reduceMotion: reduceMotion, durationMs: ms, curve: .easeOut)
    }
}
