#if DEBUG
import Foundation
import os.signpost

/// os_signpost regions for every acceptance number (CP0 trace parsing).
/// DEBUG/harness only — Release has no acceptance signpost emitters.
enum AcceptanceSignposts {
    static let log = OSLog(subsystem: "app.lumina.harness", category: "acceptance")

    enum Name: String {
        case open = "lumina.accept.open"
        case crossfade = "lumina.accept.crossfade"
        case settle = "lumina.accept.settle"
        case grab = "lumina.accept.grab"
        case halo = "lumina.accept.halo"
        case sliderToPhoton = "lumina.accept.slider_to_photon"
    }

    struct Region {
        let name: Name
        let id: OSSignpostID
        let startedAt: Date
        var layoutPasses: Int = 0
    }

    static func begin(_ name: Name) -> Region {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "acceptance", signpostID: id, "%{public}s", name.rawValue)
        // Also emit a parseable stderr line for headless ledger extraction on CI.
        fputs("signpost begin \(name.rawValue) id=\(String(describing: id))\n", stderr)
        return Region(name: name, id: id, startedAt: HarnessFakeClock.now)
    }

    static func end(_ region: Region, overshootPct: Double = 0) {
        let ms = HarnessFakeClock.now.timeIntervalSince(region.startedAt) * 1000.0
        os_signpost(.end, log: log, name: "acceptance", signpostID: region.id, "%{public}s", region.name.rawValue)
        fputs(
            "signpost end   \(region.name.rawValue) id=\(String(describing: region.id)) duration_ms=\(String(format: "%.3f", ms)) layout_passes=\(region.layoutPasses) overshoot_pct=\(overshootPct)\n",
            stderr
        )
    }
}
#endif
