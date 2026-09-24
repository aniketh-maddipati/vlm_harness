import Foundation

/// The existing live-metrics wire format, encoded without bridging sample arrays
/// through Any/NSNumber. Full captures and sequential per-key sampling are retained.
nonisolated struct ProductPerformanceSnapshot: Encodable {
    nonisolated struct Metric: Encodable {
        let key: String
        let p50: Double
        let p95: Double
        let p99: Double
        let max: Double
        let samples: Int
        let totalRecorded: Int
        let coverage: String
        let mode: String
        let capturedValues: [Double]
    }

    let schemaVersion = 1
    let pid: Int
    let startedAt: String
    let snapshotAt: String
    let elapsedSeconds: Double
    let snapshotNote = "Live snapshot; coverage ends at this flush, not process exit. Keys are sampled sequentially."
    let metrics: [Metric]
    let renderCounters: [String: Int]

    init(pid: Int, startedAt: String, snapshotAt: String, elapsedSeconds: Double,
         metrics: [Metric], counters: DevelopRenderCounters.Snapshot) {
        self.pid = pid
        self.startedAt = startedAt
        self.snapshotAt = snapshotAt
        self.elapsedSeconds = elapsedSeconds
        self.metrics = metrics
        self.renderCounters = [
            "materializations": counters.interactiveMaterializations,
            "preparedSessions": counters.preparedSessionCreated,
            "preparedSessionHits": counters.preparedSessionHits,
            "graphRenders": counters.graphRenders,
            "gpuUploads": counters.gpuUploads,
            "presentSubmissions": counters.metalPresents,
            "cancellations": counters.cancellations
        ]
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Default nonconforming-float policy throws, leaving the last good file
        // untouched because the recorder writes only after encoding succeeds.
        return try encoder.encode(self)
    }
}
