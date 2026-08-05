import SwiftUI

@main
struct LuminaApp: App {
    init() {
        WorkbenchCapture.runIfRequested()
        // Capture-only lab exits inside the launcher; interactive lab continues into the scene.
        _ = DevelopLabLauncher.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if DevelopLabLauncher.shouldPresentLab {
                    DevelopLabView()
                } else {
                    ContentView()
                }
            }
            .frame(minWidth: 1100, minHeight: 700)
            .luminaWorkspaceAppearance()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Shoot…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Import Photos…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Home") {
                    NotificationCenter.default.post(name: .luminaGoHome, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Sources") {
                    NotificationCenter.default.post(name: .luminaOpenSources, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Workbench") {
                    NotificationCenter.default.post(name: .luminaOpenWorkbench, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Story") {
                    NotificationCenter.default.post(name: .luminaOpenStory, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Read") {
                    NotificationCenter.default.post(name: .luminaEnterRead, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Subject Lens") {
                    NotificationCenter.default.post(name: .luminaSetLensAttempts, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Time Lens") {
                    NotificationCenter.default.post(name: .luminaSetLensLight, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Divider()

                Button("More Treatment Controls") {
                    NotificationCenter.default.post(name: .luminaMoreTreatment, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Keyboard Shortcuts…") {
                    NotificationCenter.default.post(name: .luminaShowShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Source") {
                Button("Open Shoot…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                Button("Scan Backlog…") {
                    NotificationCenter.default.post(name: .luminaScanBacklog, object: nil)
                }
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
