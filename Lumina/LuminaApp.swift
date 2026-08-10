import SwiftUI

@main
struct LuminaApp: App {
    init() {
        #if DEBUG
        // UI-test mode: redirect state to an isolated directory and seed deterministic fixtures
        // before any scene appears. Compiled out of Release.
        UITestLaunch.runIfRequested()
        #endif
        WorkbenchCapture.runIfRequested()
        // Headless harness exits inside the runner.
        _ = RawHarnessRunner.runIfRequested()
        // Capture-only lab exits inside the launcher; interactive lab continues into the scene.
        _ = DevelopLabLauncher.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if DevelopLabLauncher.shouldPresentLab {
                    DevelopLabView()
                } else {
                    P0RootView()
                }
            }
            .frame(minWidth: EditRailLayout.minWindowWidth, minHeight: EditRailLayout.minWindowHeight)
            .luminaWorkspaceAppearance()
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
