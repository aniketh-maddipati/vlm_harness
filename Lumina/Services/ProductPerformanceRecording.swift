import AppKit
import SwiftUI

/// Opt-in local measurements, shared by Debug and Release. Does not drive UI,
/// change recipes, invoke AI, or reinterpret publication as presentation.
nonisolated final class ProductPerformanceRecording: @unchecked Sendable {
    static let shared = ProductPerformanceRecording()
    static let stateRoot: URL? = {
        guard DevelopPresentationMeasurement.enabled,
              let path = ProcessInfo.processInfo.environment["LUMINA_PERF_OUTPUT"],
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("state")
    }()

    private let queue = DispatchQueue(label: "lumina.performance.recording", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let started = Date()

    // Called once at launch. File serialization stays off the main thread.
    func start() {
        guard let stateRoot = Self.stateRoot else { return }
        let output = stateRoot.deletingLastPathComponent()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [started] in
            let keys = LatencyMetrics.recordedKeys()
            let rows: [ProductPerformanceSnapshot.Metric] = keys.compactMap { key in
                guard let reading = LatencyMetrics.reading(for: key) else { return nil }
                return ProductPerformanceSnapshot.Metric(
                    key: key, p50: reading.p50, p95: reading.p95,
                    p99: reading.p99, max: LatencyMetrics.percentile(key, 1) ?? 0,
                    samples: reading.window.sampleCount,
                    totalRecorded: reading.window.totalRecorded,
                    coverage: reading.window.coverage.rawValue,
                    mode: reading.window.mode.rawValue,
                    capturedValues: LatencyMetrics.capturedSamples(for: key)
                )
            }
            let counters = DevelopRenderCounters.snapshot()
            let payload = ProductPerformanceSnapshot(
                pid: Int(ProcessInfo.processInfo.processIdentifier),
                startedAt: ISO8601DateFormatter().string(from: started),
                snapshotAt: ISO8601DateFormatter().string(from: Date()),
                elapsedSeconds: Date().timeIntervalSince(started),
                metrics: rows,
                counters: counters,
                selectedImageTrace: try? ProductPerformanceSnapshot.JSONValue(
                    any: DevelopPresentationTrace.shared.snapshot()
                )
            )
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let data = try payload.encoded()
                try data.write(to: output.appendingPathComponent("live-metrics.json"), options: .atomic)
            } catch {
                // A missing file is an explicit recording failure, never an empty pass.
                NSLog("Performance recording failed: %@", error.localizedDescription)
            }
        }
        self.timer = timer
        timer.resume()
    }
}

/// Mounts the existing display-link instrument on the current product root.
/// Bounds notifications identify scroll activity in this window only. These
/// callbacks are presentation opportunities, not content acknowledgements.
@MainActor
struct ProductPerformanceDisplayProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) {}

    final class Host: NSView {
        private var configuredWindow = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            if !configuredWindow {
                window.setContentSize(NSSize(width: 1280, height: 800))
                configuredWindow = true
            }
            P0RenderInstruments.shared.attach(to: self)
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: nil)
        }

        @objc private func boundsChanged(_ notification: Notification) {
            guard let clip = notification.object as? NSClipView,
                  let window, clip.window === window else { return }
            P0RenderInstruments.shared.noteScrollActivity()
        }
    }
}
