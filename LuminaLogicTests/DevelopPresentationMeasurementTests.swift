import XCTest
@testable import Lumina

final class DevelopPresentationMeasurementTests: XCTestCase {
    func testInputCorrelationRejectsOtherAssetAndRecipe() {
        let trace = DevelopPresentationTrace(enabled: true)
        let asset = UUID()
        trace.input(asset: asset, recipe: "first", startedAt: 100)
        XCTAssertEqual(trace.inputIdentity(asset: asset, recipe: "first")?.time, 100)
        XCTAssertNil(trace.inputIdentity(asset: UUID(), recipe: "first"))
        XCTAssertNil(trace.inputIdentity(asset: asset, recipe: "second"))
        trace.input(asset: asset, recipe: "second", startedAt: 101)
        XCTAssertNil(trace.inputIdentity(asset: asset, recipe: "first"))
    }

    func testTraceIsBoundedAndReportsOverwrittenEvents() {
        let trace = DevelopPresentationTrace(enabled: true)
        for index in 0..<(DevelopPresentationTrace.capacity + 3) {
            trace.record("test", at: Double(index))
        }
        let snapshot = trace.snapshot()
        XCTAssertEqual(snapshot["overwritten"] as? Int, 3)
        XCTAssertEqual((snapshot["events"] as? [[String: Any]])?.count, DevelopPresentationTrace.capacity)
        XCTAssertEqual((snapshot["events"] as? [[String: Any]])?.first?["at"] as? Double, 3)
    }

    func testDisabledTraceRetainsNoInputsOrEvents() {
        let trace = DevelopPresentationTrace(enabled: false)
        let asset = UUID()
        trace.input(asset: asset, recipe: "first", startedAt: 100)
        trace.record("test")
        trace.release()
        XCTAssertNil(trace.inputIdentity(asset: asset, recipe: "first"))
        XCTAssertEqual(trace.snapshot()["totalRecorded"] as? Int, 0)
    }

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
