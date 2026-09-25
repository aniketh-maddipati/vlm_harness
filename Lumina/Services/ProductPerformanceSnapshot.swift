import Foundation

/// The existing live-metrics wire format, encoded without bridging sample arrays
/// through Any/NSNumber. Full captures and sequential per-key sampling are retained.
nonisolated struct ProductPerformanceSnapshot: Encodable {
    nonisolated enum JSONValue: Encodable {
        case string(String)
        case number(Double)
        case boolean(Bool)
        case array([JSONValue])
        case object([String: JSONValue])
        case null

        init(any value: Any) throws {
            switch value {
            case let value as String: self = .string(value)
            case let value as Bool: self = .boolean(value)
            case let value as NSNumber:
                let number = value.doubleValue
                guard number.isFinite else { throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Nonfinite trace number")) }
                self = .number(number)
            case let value as [Any]: self = .array(try value.map(JSONValue.init(any:)))
            case let value as [String: Any]:
                self = .object(try value.mapValues(JSONValue.init(any:)))
            case is NSNull: self = .null
            default: throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported trace value"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .boolean(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

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
    let selectedImageTrace: JSONValue?
    let renderCounters: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pid, startedAt, snapshotAt, elapsedSeconds
        case snapshotNote, metrics, selectedImageTrace, renderCounters
    }

    init(pid: Int, startedAt: String, snapshotAt: String, elapsedSeconds: Double,
         metrics: [Metric], counters: DevelopRenderCounters.Snapshot,
         selectedImageTrace: JSONValue? = nil) {
        self.pid = pid
        self.startedAt = startedAt
        self.snapshotAt = snapshotAt
        self.elapsedSeconds = elapsedSeconds
        self.metrics = metrics
        self.selectedImageTrace = selectedImageTrace
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(pid, forKey: .pid)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(snapshotAt, forKey: .snapshotAt)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(snapshotNote, forKey: .snapshotNote)
        try container.encode(metrics, forKey: .metrics)
        try container.encodeIfPresent(selectedImageTrace, forKey: .selectedImageTrace)
        try container.encode(renderCounters, forKey: .renderCounters)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Default nonconforming-float policy throws, leaving the last good file
        // untouched because the recorder writes only after encoding succeeds.
        return try encoder.encode(self)
    }
}
