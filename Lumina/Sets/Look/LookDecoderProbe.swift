import CoreImage
import Foundation

/// The capability map (RAW 9 §1): what Core Image's RAW decoder offers for one body on this Mac,
/// measured once per body per shoot from one of its files and kept in the shoot's `Lumina.json`
/// header. `.version9` (macOS 27) is found by number, so this builds against the macOS 15 SDK
/// and simply reports `raw9: false` there.
nonisolated enum LookDecoderProbe {
    /// Develop a 512 px proof with every supported version and time it: `fastest` is what the
    /// Edit canvas uses. Runs at `.utility`; a version that fails to decode is left out.
    static func probe(url: URL, rules: LookRules, proofPx: Int = 512, timing: Bool = true) -> LookDecoderInfo {
        var info = LookDecoderInfo(sample: url.lastPathComponent)
        let versions = LookPipeline.supportedDecoderVersions(url: url)
        info.supported = versions
        info.raw9 = versions.contains(9)
        guard timing, !versions.isEmpty, let ctx = Self.proofContext else {
            info.fastest = versions.filter { $0 < 9 }.max() ?? versions.max()
            return info
        }
        var best: (Int, Double)?
        var ok: [Int] = []
        for v in versions {
            let t0 = Date()
            guard let dev = try? LookPipeline.develop(url: url, longEdge: proofPx, rules: rules, decoderVersion: v),
                  ctx.createCGImage(dev.image, from: dev.extent.integral) != nil else { continue }
            let ms = Date().timeIntervalSince(t0) * 1000
            info.developMs[String(v)] = (ms * 10).rounded() / 10
            ok.append(v)
            if best == nil || ms < best!.1 { best = (v, ms) }
        }
        info.supported = ok.isEmpty ? versions : ok
        info.raw9 = info.supported.contains(9)
        info.fastest = best?.0 ?? info.supported.filter { $0 < 9 }.max() ?? info.supported.max()
        return info
    }

    /// One small context for the proofs, made once.
    nonisolated(unsafe) private static var _ctx: CIContext?
    private static let lock = NSLock()
    private static var proofContext: CIContext? {
        lock.lock(); defer { lock.unlock() }
        if let c = _ctx { return c }
        let c = CIContext(options: [.cacheIntermediates: false, .name: "LookDecoderProbe"])
        _ctx = c
        return c
    }

    /// `ProcessInfo.ThermalState` → 0 … 3 for `LookRawPolicy`.
    static func thermalLevel(_ s: ProcessInfo.ThermalState) -> Int {
        switch s {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 2
        }
    }

    /// Slowed by the thermal state or Low Power Mode right now (RAW 9 §4).
    static var slowed: Bool {
        let p = ProcessInfo.processInfo
        return LookRawPolicy.slowed(thermalState: thermalLevel(p.thermalState), lowPower: p.isLowPowerModeEnabled)
    }
}
