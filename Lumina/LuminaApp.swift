import SwiftUI

/// Lumina is the Claude Design page (design/handoff/lumina-cull), shipped unchanged inside a native
/// window. See AGENTS.md: the design folder is the authority; this app only supplies the Mac plumbing.
@main
struct LuminaApp: App {
    var body: some Scene {
        WindowGroup {
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
}
