import Foundation

/// Owned spring physics — pure `(t, params, retargets)` with no AppKit/SwiftUI dependency.
/// Interim stiffness/damping derives from token durations in `design/tokens.yaml` §motion.
public struct LuminaSpringParams: Equatable, Sendable {
    public let mass: Double
    public let stiffness: Double
    public let damping: Double

    public init(mass: Double, stiffness: Double, damping: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
    }
}

public struct LuminaSpringRetarget: Equatable, Sendable {
    public let time: Double
    public let target: Double

    public init(time: Double, target: Double) {
        self.time = time
        self.target = target
    }
}

public enum LuminaSpringCurve: Sendable {
    case easeOut
    case easeInOut
    case interactive

    var dampingFraction: Double {
        switch self {
        case .easeOut: return 0.92
        case .easeInOut: return 0.88
        case .interactive: return 0.86
        }
    }
}

public enum LuminaSpring {
    /// Matches F07 trajectory sample rate when a seal exists.
    public static let defaultSampleRateHz: Double = 120

    /// Derive spring constants from a token duration (ms) and curve family.
    public static func params(durationMs: Double, curve: LuminaSpringCurve, mass: Double = 1.0) -> LuminaSpringParams {
        let response = max(durationMs / 1000.0, 1.0 / 1000.0)
        let dampingFraction = curve.dampingFraction
        let stiffness = pow(2 * Double.pi / response, 2) * mass
        let damping = 4 * Double.pi * dampingFraction * mass / response
        return LuminaSpringParams(mass: mass, stiffness: stiffness, damping: damping)
    }

    /// Critically damped spring for reduced-motion overshoot = 0 seals.
    public static func paramsReducedMotion(durationMs: Double, mass: Double = 1.0) -> LuminaSpringParams {
        let response = max(durationMs / 1000.0, 1.0 / 1000.0)
        let stiffness = pow(2 * Double.pi / response, 2) * mass
        let damping = 2 * sqrt(stiffness * mass)
        return LuminaSpringParams(mass: mass, stiffness: stiffness, damping: damping)
    }

    public struct Sample: Equatable, Sendable {
        public let time: Double
        public let value: Double
        public let velocity: Double
    }

    /// Sample the spring from `t = 0` through `endTime` inclusive.
    public static func trajectory(
        endTime: Double,
        params: LuminaSpringParams,
        initialValue: Double = 0,
        initialVelocity: Double = 0,
        retargets: [LuminaSpringRetarget] = [],
        sampleRateHz: Double = defaultSampleRateHz
    ) -> [Sample] {
        let step = 1.0 / max(sampleRateHz, 1)
        let sortedRetargets = retargets.sorted { $0.time < $1.time }
        var samples: [Sample] = []
        var x = initialValue
        var v = initialVelocity
        var retargetIndex = 0
        while retargetIndex < sortedRetargets.count, sortedRetargets[retargetIndex].time <= 0 {
            retargetIndex += 1
        }
        var target = retargetIndex > 0 ? sortedRetargets[retargetIndex - 1].target : 1.0
        var t = 0.0

        while t <= endTime + step * 0.5 {
            samples.append(Sample(time: t, value: x, velocity: v))
            if t >= endTime { break }
            let dt = min(step, endTime - t)
            while retargetIndex < sortedRetargets.count, sortedRetargets[retargetIndex].time <= t + 1e-12 {
                target = sortedRetargets[retargetIndex].target
                retargetIndex += 1
            }
            (x, v) = integrateStep(x: x, v: v, target: target, params: params, dt: dt)
            t += dt
        }
        return samples
    }

    /// Value at an arbitrary time (integrates from zero).
    public static func value(
        at time: Double,
        params: LuminaSpringParams,
        initialValue: Double = 0,
        initialVelocity: Double = 0,
        retargets: [LuminaSpringRetarget] = []
    ) -> Double {
        guard time > 0 else { return initialValue }
        let samples = trajectory(
            endTime: time,
            params: params,
            initialValue: initialValue,
            initialVelocity: initialVelocity,
            retargets: retargets
        )
        return samples.last?.value ?? initialValue
    }

    /// Semi-implicit Euler step for `m x'' + c x' + k (x - target) = 0`.
    static func integrateStep(
        x: Double,
        v: Double,
        target: Double,
        params: LuminaSpringParams,
        dt: Double
    ) -> (Double, Double) {
        let m = max(params.mass, 1e-9)
        let k = params.stiffness
        let c = params.damping
        let acceleration = (-c * v - k * (x - target)) / m
        let vNext = v + acceleration * dt
        let xNext = x + vNext * dt
        return (xNext, vNext)
    }
}
