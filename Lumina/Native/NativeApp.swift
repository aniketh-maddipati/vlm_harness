import SwiftUI
import AppKit
import LuminaCore
import LuminaUI

/// The switch for the native UI (LuminaKit). On with `-LuminaUITest YES` (the XCTests),
/// `-LuminaNative YES`, or `LUMINA_NATIVE=1`; otherwise the app shows the Claude Design page.
enum NativeUI {
    /// From this process's arguments and environment. Not `LaunchConfig()`: that is the empty
    /// configuration (no UI-test switch, no card), which left the app on the Claude Design page.
    static let config = LaunchConfig(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    static var enabled: Bool {
        config.uiTest || UserDefaults.standard.bool(forKey: "LuminaNative") || ProcessInfo.processInfo.environment["LUMINA_NATIVE"] == "1"
    }
}

/// One native window: its own model on the shared services. A second window (`debug.command`
/// `openSecondWindow`, R-72) opens the same shoot through the same store.
struct NativeRootView: View {
    @State private var model = NativeRootView.makeModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        AppShell(model: model)
            .frame(minWidth: 320, minHeight: 420)
            .onAppear { model.hooks.openSecondWindow = { NativeSecondWindow.open() } }
    }

    @MainActor static func makeModel() -> AppModel {
        AppModel.launch(config: NativeUI.config, services: NativeBackend.services(config: NativeUI.config))
    }
}

/// The services the app runs the native UI on. Today the package's defaults; the adapters over
/// Lumina/Sets/Core (ingest, verified copies, sidecars, export) and Lumina/Sets/Look (the Edit
/// look) replace them here, one protocol at a time.
enum NativeBackend {
    static func services(config: LaunchConfig) -> Services { .standard(config: config) }
}

@MainActor
enum NativeSecondWindow {
    private static var windows: [NSWindow] = []
    static func open() {
        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1100, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AppShell(model: NativeRootView.makeModel()).frame(minWidth: 320, minHeight: 420))
        w.orderFront(nil)
        windows.append(w)
    }
}
