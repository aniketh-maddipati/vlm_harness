import AppKit
import SwiftUI

/// Headless Workbench verification captures — invoke with `--capture-workbench [outdir]`.
@MainActor
enum WorkbenchCapture {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--capture-workbench") else { return }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let outDir: URL
        if args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("DerivedData/workbench-captures", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        capture(
            name: "two-up",
            presentation: PresentationFixtures.twoUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1440, height: 900),
            setFraction: 0.38,
            showReceipt: false,
            to: outDir
        )
        capture(
            name: "four-up",
            presentation: PresentationFixtures.fourUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1440, height: 900),
            setFraction: 0.38,
            showReceipt: false,
            to: outDir
        )
        capture(
            name: "right-pane-enlarged",
            presentation: PresentationFixtures.fourUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1440, height: 900),
            setFraction: 0.38,
            showReceipt: false,
            to: outDir
        )
        capture(
            name: "floating-controls",
            presentation: PresentationFixtures.twoUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1440, height: 900),
            setFraction: 0.38,
            showReceipt: true,
            to: outDir
        )
        capture(
            name: "divider-resized",
            presentation: PresentationFixtures.twoUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1440, height: 900),
            setFraction: 0.48,
            showReceipt: false,
            to: outDir
        )
        capture(
            name: "constrained-1100",
            presentation: PresentationFixtures.twoUpComparison(),
            emerging: PresentationFixtures.emergingSetPreview(),
            size: CGSize(width: 1100, height: 700),
            setFraction: 0.38,
            showReceipt: false,
            to: outDir
        )

        fputs("Workbench captures written to \(outDir.path)\n", stderr)
        exit(0)
    }

    private static func capture(
        name: String,
        presentation: WorkspacePresentation,
        emerging: [AssetPresentation],
        size: CGSize,
        setFraction: Double,
        showReceipt: Bool,
        to directory: URL
    ) {
        IngestPreferences.workbenchSetFraction = setFraction
        let view = ContinuousWorkspaceView(
            presentation: presentation,
            emergingSet: emerging,
            workspaceStage: .constant(.workbench),
            isRowExpanded: .constant(true),
            treatmentPreviewMode: .constant(.current),
            developOffsets: .constant(.zero),
            showDetailedEdits: .constant(false),
            rowPreviewActive: .constant(false),
            decisionReceiptMessage: showReceipt ? "Added to set" : nil,
            onSelectGroup: { _ in },
            onSelectPhoto: { _, _ in },
            onLensChange: { _ in },
            onSendToSet: { _, _ in },
            onFold: { _, _ in },
            onHold: { _, _ in },
            onUndo: {},
            onFocusPhoto: { _ in },
            onPreviewEdits: {},
            onHome: {},
            onFinish: {}
        )
        .frame(width: size.width, height: size.height)
        .luminaWorkspaceAppearance()
        .background(LuminaTokens.Surface.porcelain)

        // Host in an offscreen window so ScrollView / LazyVStack actually lay out.
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("Failed to create bitmap for \(name)\n", stderr)
            window.close()
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("Failed to encode \(name)\n", stderr)
            window.close()
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        fputs("Wrote \(url.lastPathComponent)\n", stderr)
        window.close()
    }
}
