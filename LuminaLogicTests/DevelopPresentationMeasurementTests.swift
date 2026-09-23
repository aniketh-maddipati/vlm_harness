import XCTest
@testable import Lumina

final class DevelopPresentationMeasurementTests: XCTestCase {
    func testSkippedDrawableIsNotZeroLatency() {
        XCTAssertNil(DevelopPresentationMeasurement.latencyMilliseconds(startedAt: 100, presentedAt: 0))
    }

    func testInvalidClockSamplesAreRejected() {
        XCTAssertNil(DevelopPresentationMeasurement.latencyMilliseconds(startedAt: 100, presentedAt: 99))
        XCTAssertNil(DevelopPresentationMeasurement.latencyMilliseconds(startedAt: .nan, presentedAt: 101))
        XCTAssertNil(DevelopPresentationMeasurement.latencyMilliseconds(startedAt: 100, presentedAt: .infinity))
    }

    func testPresentationUsesHostTimeRatherThanCallbackArrivalTime() {
        XCTAssertEqual(
            DevelopPresentationMeasurement.latencyMilliseconds(startedAt: 100, presentedAt: 100.025)!,
            25, accuracy: 0.0001
        )
    }
}
