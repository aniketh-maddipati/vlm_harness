import XCTest
@testable import Lumina

final class LuminaSpringTests: XCTestCase {

    func testStartsAtInitialValue() {
        let p = LuminaSpring.params(durationMs: 180, curve: .easeOut)
        XCTAssertEqual(LuminaSpring.value(at: 0, params: p, initialValue: 0.25), 0.25, accuracy: 1e-9)
    }

    func testConvergesTowardTarget() {
        let p = LuminaSpring.params(durationMs: 180, curve: .easeOut)
        let end = LuminaSpring.value(at: 2.0, params: p)
        XCTAssertEqual(end, 1.0, accuracy: 0.02)
    }

    func testRetargetPreservesState() {
        let p = LuminaSpring.params(durationMs: 200, curve: .easeOut)
        let mid = 0.1
        let before = LuminaSpring.trajectory(endTime: mid, params: p)
        let after = LuminaSpring.trajectory(
            endTime: 0.2,
            params: p,
            retargets: [LuminaSpringRetarget(time: mid, target: 0.5)]
        )
        let bridge = after.first(where: { abs($0.time - mid) < 1e-9 })!
        XCTAssertEqual(bridge.value, before.last!.value, accuracy: 1e-6)
        XCTAssertEqual(bridge.velocity, before.last!.velocity, accuracy: 1e-6)
    }

    func testReducedMotionDoesNotOvershoot() {
        let p = LuminaSpring.paramsReducedMotion(durationMs: 200)
        let samples = LuminaSpring.trajectory(endTime: 0.5, params: p)
        let peak = samples.map(\.value).max()!
        XCTAssertLessThanOrEqual(peak, 1.0 + 1e-6)
    }

    func testTrajectorySampleCount() {
        let p = LuminaSpring.params(durationMs: 180, curve: .easeOut)
        let hz = 120.0
        let horizon = 0.325
        let samples = LuminaSpring.trajectory(endTime: horizon, params: p, sampleRateHz: hz)
        let expected = Int(floor(horizon * hz)) + 1
        XCTAssertEqual(samples.count, expected)
    }
}
