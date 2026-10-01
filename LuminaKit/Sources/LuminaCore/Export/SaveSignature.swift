import Foundation

// WP-7. What a save covered: format # edits included # kept ids # each edited photo's look.
// Saving with an unchanged signature does nothing (R-34).

public enum SaveSignature {
    public static func make(fmt: SaveFormat, withEdits: Bool, kept: [String], looks: [String: Look]) -> String {
        var s = "\(fmt.rawValue)#\(withEdits ? 1 : 0)#\(kept.joined(separator: ","))"
        if withEdits {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            for id in kept { if let l = looks[id], !l.isEmpty, let d = try? enc.encode(l) { s += "#\(id)=" + String(decoding: d, as: UTF8.self) } }
        }
        return s
    }
}

/// The package's default exporter: records the job and writes nothing. The app swaps in the
/// real writers (`Lumina/Native/Backend`); tests read `jobs`.
public final class RecordingExporter: Exporter, @unchecked Sendable {
    private let lock = NSLock(); private var _jobs: [ExportJob] = []
    public init() {}
    public var jobs: [ExportJob] { lock.withLock { _jobs } }
    public func export(_ job: ExportJob) async -> ExportResult {
        lock.withLock { _jobs.append(job) }
        return ExportResult(written: job.items.count, reveal: job.destination)
    }
}
