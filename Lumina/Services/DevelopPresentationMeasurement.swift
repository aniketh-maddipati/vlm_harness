import Foundation
import QuartzCore

nonisolated struct DevelopSelectedImageIdentity: Codable, Sendable {
    let assetID: UUID
    let recipeFingerprint: String?
    let requestID: UUID?
    let generation: UInt64?
    let tier: String
    let provenance: String
    let inputID: UUID?
    let inputAt: Double?
    let requestedAt: Double?
    let publishedAt: Double?
}

nonisolated final class DevelopPresentationTrace: @unchecked Sendable {
    static let shared = DevelopPresentationTrace()
    static let capacity = 512
    let runID = UUID()
    private let enabled: Bool
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    private var total = 0
    private var latestInput: (asset: UUID, recipe: String, id: UUID, time: Double)?

    init(enabled: Bool = DevelopPresentationMeasurement.enabled) {
        self.enabled = enabled
    }

    func input(asset: UUID, recipe: String, startedAt: Double, action: String = "scrub") {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        let inputID = UUID()
        latestInput = (asset, recipe, inputID, startedAt)
        appendLocked(["stage": "session-input", "inputID": inputID.uuidString,
                      "assetID": asset.uuidString, "recipeFingerprint": recipe,
                      "at": startedAt, "action": action, "cohort": "session-callback"])
    }

    func inputIdentity(asset: UUID, recipe: String) -> (id: UUID, time: Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard let latestInput, latestInput.asset == asset, latestInput.recipe == recipe else { return nil }
        return (latestInput.id, latestInput.time)
    }

    func record(_ stage: String, identity: DevelopSelectedImageIdentity? = nil,
                at: Double = CACurrentMediaTime(), values: [String: Any] = [:]) {
        guard enabled else { return }
        var row = values
        row["stage"] = stage
        row["at"] = at
        if let identity, let data = try? JSONEncoder().encode(identity),
           let object = try? JSONSerialization.jsonObject(with: data) {
            row["selected"] = object
        }
        lock.lock()
        defer { lock.unlock() }
        appendLocked(row)
    }

    func release() {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        var row: [String: Any] = ["stage": "gesture-release-callback", "at": CACurrentMediaTime()]
        if let latestInput { row["inputID"] = latestInput.id.uuidString }
        appendLocked(row)
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return ["runID": runID.uuidString, "capacity": Self.capacity,
                "totalRecorded": total, "overwritten": max(0, total - rows.count), "events": rows]
    }

    private func appendLocked(_ row: [String: Any]) {
        total += 1
        if rows.count == Self.capacity { rows.removeFirst() }
        rows.append(row)
    }
}

/// Presentation acknowledgement only; does not infer recipe correctness or input
/// latency. Enabled by the existing explicit instrumentation launch argument.
nonisolated enum DevelopPresentationMeasurement {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--p0-instruments")
    static let latencyKey = "p0.develop.draw_to_drawable_presented"
    static let blankKey = "p0.develop.blank_drawable_presented"
    static let skippedKey = "p0.develop.drawable_not_presented"

    static func latencyMilliseconds(startedAt: Double, presentedAt: Double) -> Double? {
        guard startedAt.isFinite, presentedAt.isFinite,
              presentedAt > 0, presentedAt >= startedAt else { return nil }
        return (presentedAt - startedAt) * 1000
    }

    static func record(startedAt: Double, presentedAt: Double, blank: Bool) {
        guard let latency = latencyMilliseconds(startedAt: startedAt, presentedAt: presentedAt) else {
            LatencyMetrics.beginCapture(key: skippedKey)
            LatencyMetrics.record(skippedKey, milliseconds: 1)
            return
        }
        LatencyMetrics.beginCapture(key: latencyKey)
        LatencyMetrics.record(latencyKey, milliseconds: latency)
        if blank {
            LatencyMetrics.beginCapture(key: blankKey)
            LatencyMetrics.record(blankKey, milliseconds: 1)
        }
    }
}
