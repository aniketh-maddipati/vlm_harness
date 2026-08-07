import Foundation

/// Deterministic SplitMix64 PRNG. Given the same seed it produces the identical action stream,
/// which is what makes an explorer run exactly replayable from a recorded seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero fixed point.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform Int in `0..<upperBound`.
    mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    /// Pick one element deterministically.
    mutating func pick<T>(_ elements: [T]) -> T {
        elements[int(below: elements.count)]
    }
}
