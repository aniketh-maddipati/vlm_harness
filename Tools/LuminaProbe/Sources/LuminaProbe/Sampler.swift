import Darwin
import Foundation

/// Samples CPU and memory footprint of the probe process and the page's web content process.
/// Memory is phys_footprint — what Activity Monitor calls "Memory" and what jetsam counts.
@MainActor
final class ResourceSampler {
    struct Sample: Encodable { let t: Double; let pid: Int32; let who: String; let cpu: Double; let footprintMB: Double }
    struct Summary: Encodable { let who: String; let peakMB: Double; let lastMB: Double; let peakCPU: Double; let meanCPU: Double }

    private(set) var samples: [Sample] = []
    private var last: [Int32: (cpuNs: UInt64, wall: Double)] = [:]
    private var timer: Timer?
    private let started = Date()
    private let timebase: mach_timebase_info_data_t = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t }()

    func start(interval: TimeInterval, pids: @escaping @MainActor () -> [(Int32, String)]) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(pids()) }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick(_ pids: [(Int32, String)]) {
        let wall = Date().timeIntervalSince(started)
        for (pid, who) in pids where pid > 0 {
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard rc == 0 else { continue }
            let cpuNs = (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
            var cpu = 0.0
            if let prev = last[pid], wall > prev.wall {
                cpu = Double(cpuNs - min(cpuNs, prev.cpuNs)) / 1e9 / (wall - prev.wall) * 100
            }
            last[pid] = (cpuNs, wall)
            samples.append(Sample(t: wall, pid: pid, who: who, cpu: cpu, footprintMB: Double(info.ri_phys_footprint) / 1_048_576))
        }
    }

    func summary() -> [Summary] {
        Dictionary(grouping: samples, by: \.who).map { who, s in
            let cpus = s.dropFirst().map(\.cpu)
            return Summary(who: who, peakMB: s.map(\.footprintMB).max() ?? 0, lastMB: s.last?.footprintMB ?? 0,
                           peakCPU: cpus.max() ?? 0, meanCPU: cpus.isEmpty ? 0 : cpus.reduce(0, +) / Double(cpus.count))
        }.sorted { $0.who < $1.who }
    }
}
