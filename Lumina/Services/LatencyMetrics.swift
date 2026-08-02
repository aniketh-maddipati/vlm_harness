import Foundation
import os

/// Lightweight latency instrumentation for Tier-0 SLA tracking (<50ms input response).
enum LatencyMetrics {
    private static let log = OSLog(subsystem: "com.lumina.app", category: "Latency")
    private static let lock = NSLock()
    private static var samples: [String: [Double]] = [:]
    private static let maxSamplesPerKey = 128

    static let navigationSLAms: Double = 50
    static let cacheHitSLAms: Double = 50
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

    static func p95(for key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let bucket = samples[key], !bucket.isEmpty else { return nil }
        let sorted = bucket.sorted()
        let idx = min(Int(Double(sorted.count - 1) * 0.95), sorted.count - 1)
        return sorted[idx]
    }

    static func sla(for key: String) -> Double {
        if key.hasPrefix("develop") { return developScrubSLAms }
        return key.hasPrefix("cache") ? cacheHitSLAms : navigationSLAms
    }
}
