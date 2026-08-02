import Foundation
import os

/// Latency instrumentation for the Speed Contract.
nonisolated enum LatencyMetrics {
    private static let log = OSLog(subsystem: "com.lumina.app", category: "Latency")
    private static let lock = NSLock()
    private static var samples: [String: [Double]] = [:]
    private static let maxSamplesPerKey = 512

    static let navigationSLAms: Double = 50
    static let cacheHitSLAms: Double = 50
    static let fidelitySLAms: Double = 100
    static let developScrubSLAms: Double = 120

    static func record(_ key: String, milliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        var bucket = samples[key, default: []]
        bucket.append(milliseconds)
        if bucket.count > maxSamplesPerKey { bucket.removeFirst(bucket.count - maxSamplesPerKey) }
        samples[key] = bucket

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

    static func percentile(_ key: String, _ p: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let bucket = samples[key], !bucket.isEmpty else { return nil }
        let sorted = bucket.sorted()
        let clamped = min(max(p, 0), 1)
        let idx = min(Int(Double(sorted.count - 1) * clamped), sorted.count - 1)
        return sorted[idx]
    }

    static func p50(for key: String) -> Double? { percentile(key, 0.50) }
    static func p95(for key: String) -> Double? { percentile(key, 0.95) }
    static func p99(for key: String) -> Double? { percentile(key, 0.99) }

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

    static func resetSession() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
