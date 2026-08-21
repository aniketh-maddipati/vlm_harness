#if DEBUG
import Darwin
import Foundation

/// Launch-to-photographs, measured the honest way: from the kernel's process start time, so
/// dyld, runtime init and scene construction are all inside the number — not from
/// `LuminaApp.init()`, which would quietly exclude everything before it.
///
/// The reading is recorded through the E1 `LatencyMetrics` capture mode, so it carries a
/// `Window` declaring its sample count and coverage like every other emitted row.
@MainActor
enum WorkbenchLaunchClock {
    /// E1 metric key for the boot measurement.
    static let key = "workbench.launchToPhotographs"

    private static var recorded = false

    /// Wall-clock seconds since this process was exec'd, via `KERN_PROC_PID`.
    /// Returns nil rather than guessing if the kernel will not answer.
    static func secondsSinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = mib.withUnsafeMutableBufferPointer { pointer -> Int32 in
            sysctl(pointer.baseAddress, u_int(pointer.count), &info, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        let startSeconds = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - startSeconds
    }

    /// Called the first time a photograph is actually on screen. Idempotent — only the first
    /// call is the launch, every later one is browsing.
    static func recordPhotographsVisible() {
        guard !recorded, let seconds = secondsSinceProcessStart() else { return }
        recorded = true
        LatencyMetrics.beginCapture(key: key)
        LatencyMetrics.record(key, milliseconds: seconds * 1000)
        let reading = LatencyMetrics.reading(for: key)
        WorkbenchTrace.log(
            "launch-to-photographs "
                + String(format: "%.0f ms", seconds * 1000)
                + " · " + (reading?.window.declaration ?? "n=1")
        )
    }

    /// Test seam — lets a second boot in the same process be measured again.
    static func reset() {
        recorded = false
        LatencyMetrics.clearCapture(key: key)
    }
}
#endif
