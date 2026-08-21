import Foundation
import os

/// Latency instrumentation for the Speed Contract.
///
/// Two storage modes live side by side:
///
/// - **Ring (default, unchanged).** Every key keeps at most `maxSamplesPerKey` samples.
///   A long run therefore reports the percentile of its *tail*. `SpeedContractHUD` reads
///   `p95(for:)` live off this path and `SessionCache` calls `resetSession()`; neither
///   changes behaviour, because a key is only ever promoted out of the ring by an explicit
///   `beginCapture(key:)`.
/// - **Capture (opt-in, unbounded).** After `beginCapture(key:)` the key's samples are kept
///   in full, so a percentile covers the whole run rather than the last `maxSamplesPerKey`
///   frames. Cost is trivial: a 60 s @ 120 Hz glide is ~7,200 samples = ~57.6 KB per key.
///
/// The reason both exist: a 60 s glide at 120 Hz produces ~7,200 `scroll.frame` samples.
/// Read through the ring, warm-up and early stutter — exactly where a new engine differs —
/// age out of the number entirely. See `docs/perf/e1-baseline.md`.
///
/// Honesty rule: a percentile is never emitted without the window it covers. `Reading`
/// cannot be constructed without a `Window`, so a report cannot silently omit one.
nonisolated enum LatencyMetrics {
    private static let log = OSLog(subsystem: "com.lumina.app", category: "Latency")
    private static let lock = NSLock()

    /// Bounded ring, per key. Default path.
    private static var samples: [String: [Double]] = [:]
    /// Unbounded capture buffer, per key. Populated only for keys in `captureKeys`.
    private static var captured: [String: [Double]] = [:]
    /// Keys currently accumulating into `captured`.
    private static var captureKeys: Set<String> = []
    /// Every sample the run produced, per key — including ones the ring dropped.
    private static var totalRecorded: [String: Int] = [:]

    private static let maxSamplesPerKey = 512

    static let navigationSLAms: Double = 50
    static let cacheHitSLAms: Double = 50
    static let fidelitySLAms: Double = 100
    static let developScrubSLAms: Double = 120

    // MARK: - Window declaration

    /// What a reported percentile actually covers.
    enum Coverage: String {
        /// Every sample the run produced is in the number.
        case fullRun = "full run"
        /// The ring dropped older samples; the number covers only the most recent ones.
        case tail
    }

    /// Which store the number came from.
    enum Mode: String {
        case capture
        case ring
    }

    /// The window a percentile covers. Carried by every emitted row.
    struct Window: Equatable {
        let key: String
        /// Samples the percentile was actually computed over.
        let sampleCount: Int
        /// Samples the run produced, whether or not they survived to be counted.
        let totalRecorded: Int
        let mode: Mode

        var coverage: Coverage { sampleCount >= totalRecorded ? .fullRun : .tail }

        var droppedCount: Int { max(0, totalRecorded - sampleCount) }

        /// `n=7203, full run` · `n=512, tail (of 7203 recorded)`
        var declaration: String {
            switch coverage {
            case .fullRun:
                return "n=\(sampleCount), full run"
            case .tail:
                return "n=\(sampleCount), tail (of \(totalRecorded) recorded)"
            }
        }
    }

    /// A percentile triple plus the window it covers. There is no initialiser that omits
    /// the window — that is the point.
    struct Reading {
        let key: String
        let p50: Double
        let p95: Double
        let p99: Double
        let window: Window

        /// Markdown table row: `| key | p50 | p95 | p99 | n=…, full run |`
        var row: String {
            String(
                format: "| `%@` | %.2f | %.2f | %.2f | %@ |",
                key, p50, p95, p99, window.declaration
            )
        }
    }

    // MARK: - Recording

    static func record(_ key: String, milliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        var bucket = samples[key, default: []]
        bucket.append(milliseconds)
        if bucket.count > maxSamplesPerKey { bucket.removeFirst(bucket.count - maxSamplesPerKey) }
        samples[key] = bucket
        totalRecorded[key, default: 0] += 1
        if captureKeys.contains(key) { captured[key, default: []].append(milliseconds) }

        os_signpost(.event, log: log, name: "latency", "%{public}s %.2fms", key, milliseconds)
        if milliseconds > sla(for: key) {
            os_signpost(.event, log: log, name: "SLO breach", "%{public}s %.2fms", key, milliseconds)
        }
    }

    static func measure<T>(_ key: String, _ work: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try work()
        record(key, milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return result
    }

    static func measureAsync<T>(_ key: String, _ work: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await work()
        record(key, milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return result
    }

    // MARK: - Capture mode

    /// Promote `key` out of the 512-sample ring for the rest of the run. Keys that never
    /// call this keep the previous behaviour exactly.
    static func beginCapture(key: String) {
        lock.lock()
        defer { lock.unlock() }
        captureKeys.insert(key)
        if captured[key] == nil { captured[key] = [] }
    }

    /// Stop accumulating for `key`. Samples already captured stay readable until
    /// `resetSession()` or `clearCapture(key:)`.
    static func endCapture(key: String) {
        lock.lock()
        defer { lock.unlock() }
        captureKeys.remove(key)
    }

    static func clearCapture(key: String) {
        lock.lock()
        defer { lock.unlock() }
        captureKeys.remove(key)
        captured.removeValue(forKey: key)
    }

    static func isCapturing(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return captureKeys.contains(key)
    }

    /// Every captured sample for `key`, in record order. Empty when the key is ring-backed.
    static func capturedSamples(for key: String) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return captured[key] ?? []
    }

    /// Worst-case capture cost in bytes, for the keys currently holding capture buffers.
    static func captureMemoryBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return captured.values.reduce(0) { $0 + $1.count * MemoryLayout<Double>.size }
    }

    // MARK: - Reading

    /// Capture buffer wins when one exists; otherwise the ring. Caller holds `lock`.
    private static func bucketLocked(_ key: String) -> [Double]? {
        if let capturedBucket = captured[key], !capturedBucket.isEmpty { return capturedBucket }
        return samples[key]
    }

    private static func percentileLocked(_ bucket: [Double], _ p: Double) -> Double {
        let sorted = bucket.sorted()
        let clamped = min(max(p, 0), 1)
        let idx = min(Int(Double(sorted.count - 1) * clamped), sorted.count - 1)
        return sorted[idx]
    }

    static func percentile(_ key: String, _ p: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let bucket = bucketLocked(key), !bucket.isEmpty else { return nil }
        return percentileLocked(bucket, p)
    }

    static func p50(for key: String) -> Double? { percentile(key, 0.50) }
    static func p95(for key: String) -> Double? { percentile(key, 0.95) }
    static func p99(for key: String) -> Double? { percentile(key, 0.99) }

    /// The window the current percentiles for `key` cover. `nil` when nothing was recorded.
    static func window(for key: String) -> Window? {
        lock.lock()
        defer { lock.unlock() }
        guard let bucket = bucketLocked(key), !bucket.isEmpty else { return nil }
        let isCapture = !(captured[key] ?? []).isEmpty
        return Window(
            key: key,
            sampleCount: bucket.count,
            totalRecorded: totalRecorded[key] ?? bucket.count,
            mode: isCapture ? .capture : .ring
        )
    }

    /// Percentiles bound to their window. Use this for anything that emits a table row.
    static func reading(for key: String) -> Reading? {
        lock.lock()
        defer { lock.unlock() }
        guard let bucket = bucketLocked(key), !bucket.isEmpty else { return nil }
        let isCapture = !(captured[key] ?? []).isEmpty
        let window = Window(
            key: key,
            sampleCount: bucket.count,
            totalRecorded: totalRecorded[key] ?? bucket.count,
            mode: isCapture ? .capture : .ring
        )
        return Reading(
            key: key,
            p50: percentileLocked(bucket, 0.50),
            p95: percentileLocked(bucket, 0.95),
            p99: percentileLocked(bucket, 0.99),
            window: window
        )
    }

    /// Keys that have recorded at least one sample this run.
    static func recordedKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Set(samples.keys).union(captured.keys).sorted()
    }

    static func sampleCount(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return samples[key]?.count ?? 0
    }

    static func sla(for key: String) -> Double {
        if key.hasPrefix("spine.input_to_photon") || key.hasPrefix("navigation") {
            return navigationSLAms
        }
        if key.hasPrefix("spine.paint_commit") { return navigationSLAms }
        if key.hasPrefix("spine.fidelity") { return fidelitySLAms }
        if key.hasPrefix("develop") { return developScrubSLAms }
        return key.hasPrefix("cache") ? cacheHitSLAms : navigationSLAms
    }

    /// Clears samples for a new session. Capture *registration* survives, so a harness that
    /// called `beginCapture` keeps capturing across a session boundary rather than silently
    /// falling back to the ring.
    static func resetSession() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        captured.removeAll()
        totalRecorded.removeAll()
        for key in captureKeys { captured[key] = [] }
    }
}
