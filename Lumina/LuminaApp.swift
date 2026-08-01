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
                Button("Import Photos…") {
                    NotificationCenter.default.post(name: .luminaImportRAW, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let luminaImportRAW = Notification.Name("luminaImportRAW")
    static let luminaImportJPG = Notification.Name("luminaImportJPG")
}
