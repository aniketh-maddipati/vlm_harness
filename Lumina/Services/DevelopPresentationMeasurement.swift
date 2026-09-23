import Foundation

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
