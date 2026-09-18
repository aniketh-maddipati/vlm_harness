#if !LUMINA_SHIPPING_APP
import AppKit
import CoreImage
import Foundation

/// Non-shipping decoder comparison seam. Production remains Apple-only;
/// unlinked candidates are reported explicitly rather than simulated.
@MainActor
enum RawBackendBenchmarkRunner {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--raw-backend-benchmark") else { return false }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let output: URL
        if let index = args.firstIndex(of: "--raw-backend-benchmark"),
           args.indices.contains(index + 1),
           !args[index + 1].hasPrefix("-") {
            output = URL(fileURLWithPath: args[index + 1])
        } else {
            output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/raw-backend-benchmark.json")
        }

        guard let root = DevelopLabFixtures.resolveRawDirectory(),
              let raw = DevelopLabFixtures.discoverRAWFiles(in: root, limit: 1).first else {
            write(
                [
                    "status": "blocked",
                    "reason": "no verified RAW fixture",
                    "backends": inventory(),
                ],
                to: output
            )
            exit(1)
        }

        let backend = AppleRawDecodeBackend()
        let context = DevelopRenderGraph.sharedContext
        var measurements: [[String: Any]] = []
        for scale in [0.25, 1.0] {
            let started = CFAbsoluteTimeGetCurrent()
            guard let filter = backend.makeFilter(imageURL: raw) else { continue }
            filter.isDraftModeEnabled = scale < 1
            filter.scaleFactor = Float(scale)
            guard let image = filter.outputImage,
                  context.createCGImage(
                    image,
                    from: image.extent.integral,
                    format: .RGBAh,
                    colorSpace: DevelopColorPolicy.workingColorSpace
                  ) != nil else { continue }
            measurements.append([
                "scale": scale,
                "milliseconds": (CFAbsoluteTimeGetCurrent() - started) * 1000,
                "width": Int(image.extent.width),
                "height": Int(image.extent.height),
            ])
        }

        let ok = measurements.count == 2
        write(
            [
                "status": ok ? "measured" : "failed",
                "fixture": raw.path,
                "productionBackend": backend.identifier,
                "backends": inventory(),
                "appleMeasurements": measurements,
            ],
            to: output
        )
        exit(ok ? 0 : 1)
    }

    private static func inventory() -> [[String: Any]] {
        RawDecodeBackendRegistry.benchmarkInventory.map {
            ["identifier": $0.identifier, "linked": $0.linked, "role": $0.role]
        }
    }

    private static func write(_ value: [String: Any], to output: URL) {
        try? FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: output, options: .atomic)
        }
    }
}
#endif
