import SwiftUI

@main
struct LuminaApp: App {
    init() {
        #if DEBUG
        // UI-test mode: redirect state to an isolated directory and seed deterministic fixtures
        // before any scene appears. Compiled out of Release.
        UITestLaunch.runIfRequested()
        DevelopLabLauncher.runIfRequested()
        // W0 workbench: resolve the deep-link before any scene appears.
        WorkbenchLaunch.runIfRequested()
        #endif
        // E2 render instruments: off unless asked for, so an ordinary run is unchanged.
        if P0RenderInstruments.launchRequested {
            MainActor.assumeIsolated { P0RenderInstruments.shared.enable() }
            ProductPerformanceRecording.shared.start()
        }
        #if !LUMINA_SHIPPING_APP
        // Headless harnesses exit inside the runner.
        _ = RawHarnessRunner.runIfRequested()
        _ = RamTierHarnessRunner.runIfRequested()
        _ = P0EditHarnessRunner.runIfRequested()
        _ = P0EditLiveRunner.runIfRequested()
        _ = P0ScrollLiveRunner.runIfRequested()
        _ = RawBackendBenchmarkRunner.runIfRequested()
        // Capture-only lab exits inside the launcher; interactive lab continues into the scene.
        _ = DevelopLabLauncher.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // The design's page, shipped unchanged inside a native window (design/handoff/lumina-cull/BUILD-exact.md).
            SetsRootView()
                .frame(minWidth: SetsWindowSize.minimum.width, minHeight: SetsWindowSize.minimum.height)
                .ignoresSafeArea()
        }
        .defaultSize(SetsWindowSize.initial)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .luminaSetsUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let luminaImportRAW = Notification.Name("luminaImportRAW")
    static let luminaShowShortcuts = Notification.Name("lumina.showShortcuts")
    static let luminaGoHome = Notification.Name("lumina.goHome")
    static let luminaImportJPG = Notification.Name("luminaImportJPG")
    static let luminaSetLensAttempts = Notification.Name("lumina.setLensAttempts")
    static let luminaSetLensLight = Notification.Name("lumina.setLensLight")
    static let luminaScanBacklog = Notification.Name("lumina.scanBacklog")
    static let luminaOpenSources = Notification.Name("lumina.openSources")
    static let luminaOpenWorkbench = Notification.Name("lumina.openWorkbench")
    static let luminaOpenStory = Notification.Name("lumina.openStory")
    static let luminaEnterRead = Notification.Name("lumina.enterRead")
    static let luminaMoreTreatment = Notification.Name("lumina.moreTreatment")
}
