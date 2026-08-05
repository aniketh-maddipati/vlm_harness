import AppKit
import SwiftUI

/// Headless / windowed Develop Lab entry — `--develop-lab`.
@MainActor
enum DevelopLabLauncher {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--develop-lab") else { return false }

        // Capture mode writes layout PNGs without needing interactive session.
        if args.contains("--capture-develop-lab") {
            captureLayouts()
            return true
        }

        // Interactive lab window — replaces normal ContentView via App entry.
        return true
    }

    static var shouldPresentLab: Bool {
        ProcessInfo.processInfo.arguments.contains("--develop-lab")
    }

    private static func captureLayouts() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let outDir: URL
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--capture-develop-lab"),
           ProcessInfo.processInfo.arguments.indices.contains(idx + 1),
           !ProcessInfo.processInfo.arguments[idx + 1].hasPrefix("-") {
            outDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[idx + 1], isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/develop-lab", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for size in [CGSize(width: 1440, height: 900), CGSize(width: 1100, height: 700)] {
            let name = size.width == 1440 ? "lab-1440x900" : "lab-1100x700"
            let view = DevelopLabView()
                .frame(width: size.width, height: size.height)
                .luminaWorkspaceAppearance()
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()

            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                fputs("Failed lab capture \(name)\n", stderr)
                window.close()
                continue
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: outDir.appendingPathComponent("\(name).png"))
                fputs("Wrote \(name).png\n", stderr)
            }
            window.close()
        }
        fputs("Develop Lab captures → \(outDir.path)\n", stderr)
        exit(0)
    }
}
