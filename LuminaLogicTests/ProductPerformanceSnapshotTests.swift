import XCTest
@testable import Lumina

final class ProductPerformanceSnapshotTests: XCTestCase {
    func testFullWirePayloadMatchesLegacyIncludingCaptureOrderAndCounters() throws {
        let values: [Double] = [0, -0.0, 0.1, -1.0 / 3.0, 1e-200, 1e200]
            + (0..<4096).map { Double($0) / 7.0 }
        let count = 9_007_199_254_740_993
        let key = "capture\"\\\n雪"
        let metric = ProductPerformanceSnapshot.Metric(
            key: key, p50: 0.1, p95: 1.0 / 3.0, p99: 1e200, max: 1e200,
            samples: values.count, totalRecorded: count, coverage: "tail",
            mode: "capture", capturedValues: values)
        let ring = ProductPerformanceSnapshot.Metric(
            key: "ring", p50: 1, p95: 2, p99: 3, max: 4, samples: 512,
            totalRecorded: 600, coverage: "tail", mode: "ring", capturedValues: [])
        let counters = DevelopRenderCounters.Snapshot(
            preparedSessionCreated: 2, preparedSessionHits: 3,
            interactiveMaterializations: 1, graphRenders: 4, gpuUploads: 5,
            variantRenders: 99, metalPresents: 6, cancellations: 7)
        let snapshot = ProductPerformanceSnapshot(
            pid: 123, startedAt: "2026-09-24T07:17:55Z",
            snapshotAt: "2026-09-24T07:17:57Z", elapsedSeconds: 2.125,
            metrics: [metric, ring], counters: counters)
        let legacy: [String: Any] = [
            "schemaVersion": 1, "pid": 123, "startedAt": "2026-09-24T07:17:55Z",
            "snapshotAt": "2026-09-24T07:17:57Z", "elapsedSeconds": 2.125,
            "snapshotNote": "Live snapshot; coverage ends at this flush, not process exit. Keys are sampled sequentially.",
            "metrics": [
                ["key": key, "p50": 0.1, "p95": 1.0 / 3.0, "p99": 1e200,
                 "max": 1e200, "samples": values.count, "totalRecorded": count,
                 "coverage": "tail", "mode": "capture", "capturedValues": values],
                ["key": "ring", "p50": 1, "p95": 2, "p99": 3, "max": 4,
                 "samples": 512, "totalRecorded": 600, "coverage": "tail",
                 "mode": "ring", "capturedValues": [Double]()]
            ],
            "renderCounters": ["materializations": 1, "preparedSessions": 2,
                               "preparedSessionHits": 3, "graphRenders": 4,
                               "gpuUploads": 5, "presentSubmissions": 6, "cancellations": 7]
        ]
        let oldData = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        let newData = try snapshot.encoded()
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? NSDictionary)
        let new = try XCTUnwrap(JSONSerialization.jsonObject(with: newData) as? NSDictionary)
        XCTAssertEqual(new, old)
        let rows = try XCTUnwrap(new["metrics"] as? [[String: Any]])
        let roundTrip = try XCTUnwrap(rows[0]["capturedValues"] as? [Double])
        XCTAssertEqual(roundTrip, values)
        XCTAssertEqual((rows[0]["totalRecorded"] as? NSNumber)?.int64Value, Int64(count))
        // JSON numeric spelling and negative-zero sign are not wire requirements.
    }

    func testNonfiniteValuesRejectSnapshotBeforeAnyFileWrite() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            let metric = ProductPerformanceSnapshot.Metric(
                key: "bad", p50: 0, p95: 0, p99: 0, max: 0, samples: 1,
                totalRecorded: 1, coverage: "full run", mode: "capture",
                capturedValues: [value])
            let snapshot = ProductPerformanceSnapshot(
                pid: 123, startedAt: "start", snapshotAt: "end", elapsedSeconds: 1,
                metrics: [metric], counters: .init())
            XCTAssertThrowsError(try snapshot.encoded())
        }
    }

    func testEmptySnapshotPreservesEmptyMetricsArray() throws {
        let snapshot = ProductPerformanceSnapshot(
            pid: 123, startedAt: "start", snapshotAt: "end", elapsedSeconds: 0,
            metrics: [], counters: .init())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        XCTAssertEqual((object["metrics"] as? [Any])?.count, 0)
    }
}
