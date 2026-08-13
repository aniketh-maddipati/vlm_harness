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
}
