import SwiftUI

@main
struct LuminaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
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

                Button("Attempts Lens") {
                    NotificationCenter.default.post(name: .luminaSetLensAttempts, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Light Lens") {
                    NotificationCenter.default.post(name: .luminaSetLensLight, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

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
}
