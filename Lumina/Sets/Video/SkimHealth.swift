import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What Skim's page reads every couple of seconds (`skimHealth`): the Mac's heat, Low Power Mode,
/// memory pressure and this app's own footprint, and the pace those ask for (VideoPolicy pacing).
/// The page decodes in WebKit's own process, so `footprintMB` is the app around it, not the decode.
final class SkimHealth: @unchecked Sendable {
    static let shared = SkimHealth()

    /// Stepping between pace levels: down at once, up one at a time after a quiet spell.
    struct Pacer: Equatable, Sendable {
        var level = 0
        var lastWorse: TimeInterval = 0
        mutating func step(asked: Int, now: TimeInterval) -> Int {
            if asked >= level, asked > 0 { lastWorse = now }
            let next = VideoPolicy.nextLevel(current: level, asked: asked, quietFor: now - lastWorse)
            if next < level { lastWorse = now }
            level = next
            return level
        }
    }

    private let lock = NSLock()
    private var pacer = Pacer()
    private var pressure: VideoPolicy.Pressure = .none
    private var pressureAt: TimeInterval = 0
    #if canImport(Darwin)
    private var source: DispatchSourceMemoryPressure?
    #endif

    private init() {
        #if canImport(Darwin)
        let s = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let e = s.data
            let p: VideoPolicy.Pressure = e.contains(.critical) ? .critical : e.contains(.warning) ? .warning : .none
            self.lock.lock(); self.pressure = p; self.pressureAt = Date().timeIntervalSince1970; self.lock.unlock()
        }
        s.resume(); source = s
        #endif
    }

    static func thermalLevel(_ s: ProcessInfo.ThermalState) -> Int {
        switch s { case .nominal: return 0; case .fair: return 1; case .serious: return 2; case .critical: return 3; @unknown default: return 2 }
    }

    /// This process's physical footprint in MB (what Activity Monitor calls Memory), nil if unreadable.
    static func footprintMB() -> Double? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : nil
        #else
        return nil
        #endif
    }

    /// One reading. `slowdown` is the page's own measure: recent decode time per frame over the
    /// first clips' (1.0 = as fast as at the start).
    func read(slowdown: Double) -> [String: Any] {
        let p = ProcessInfo.processInfo, now = Date().timeIntervalSince1970
        let thermal = Self.thermalLevel(p.thermalState), low = p.isLowPowerModeEnabled
        lock.lock()
        // A warning that nothing has repeated for a minute is over.
        if pressure != .none, now - pressureAt > 60 { pressure = .none }
        let pr = pressure
        let asked = VideoPolicy.askedLevel(thermalState: thermal, lowPower: low, pressure: pr, slowdown: slowdown)
        let level = pacer.step(asked: asked, now: now)
        lock.unlock()
        let budgets = VideoPolicy.budgets(physicalMemory: p.physicalMemory)
        let pace = VideoPolicy.pace(level: level, budgets: budgets, reason: Self.reason(thermal: thermal, low: low, pressure: pr, slowdown: slowdown, level: level))
        var out: [String: Any] = [
            "thermal": thermal, "lowPower": low, "pressure": pr.rawValue, "slowdown": slowdown,
            "level": pace.level, "duty": pace.dutyCycle, "reason": pace.reason ?? "",
            "memGB": Double(p.physicalMemory) / 1_073_741_824,
        ]
        if let f = Self.footprintMB() { out["footprintMB"] = f }
        return out
    }

    static func reason(thermal: Int, low: Bool, pressure: VideoPolicy.Pressure, slowdown: Double, level: Int) -> String? {
        guard level > 0 else { return nil }
        if pressure == .critical { return "memory is short" }
        if thermal >= 2 { return "Mac is hot" }
        if pressure == .warning { return "memory is tight" }
        if thermal == 1 { return "Mac is warm" }
        if low { return "Low Power Mode" }
        if slowdown >= VideoPolicy.slowdownRatio { return "decoding has slowed" }
        return "cooling down"
    }
}
