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
        WorkbenchCapture.runIfRequested()
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
        let minimum = launchWindowMinimum()
        WindowGroup {
            Group {
                #if DEBUG
                if DevelopLabLauncher.shouldPresentLab {
                    DevelopLabView()
                } else {
                    P0RootView()
                }
                #else
                P0RootView()
                #endif
            }
            .frame(minWidth: minimum.width, minHeight: minimum.height)
            .luminaWorkspaceAppearance()
            .background {
                if P0RenderInstruments.launchRequested {
                    ProductPerformanceDisplayProbe()
                }
            }
            #if DEBUG
            .background {
                DevSplitWindowAnchor()
                    .frame(width: 0, height: 0)
            }
            #endif
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Shoot…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Home") {
                    NotificationCenter.default.post(name: .luminaGoHome, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Keyboard Shortcuts…") {
                    NotificationCenter.default.post(name: .luminaShowShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Shoot") {
                Button("Open Shoot…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

/// Product minimum, unless this playground launch asked to share the screen.
private func launchWindowMinimum() -> CGSize {
    #if DEBUG
    if let frame = DevSplitPlacement.liveTrailingFrame() {
        return CGSize(width: frame.width, height: EditRailLayout.minWindowHeight)
    }
    #endif
    return CGSize(width: EditRailLayout.minWindowWidth, height: EditRailLayout.minWindowHeight)
}

extension Notification.Name {
    static let luminaImportRAW = Notification.Name("luminaImportRAW")
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
