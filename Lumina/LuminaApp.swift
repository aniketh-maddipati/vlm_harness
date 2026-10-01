import AppKit
import SwiftUI

/// Lumina is the Claude Design page (design/handoff/lumina-cull), shipped unchanged inside a native
/// window. See AGENTS.md: the design folder is the authority; this app only supplies the Mac plumbing.
@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(LuminaAppDelegate.self) private var delegate
    @ObservedObject private var menu = SetsMenuModel.shared

    var body: some Scene {
        WindowGroup {
            // The native rebuild (LuminaKit, design/handoff/lumina-app) runs behind a switch until
            // it reaches parity; the Claude Design page stays the default. See Lumina/Native.
            if NativeUI.enabled {
                NativeRootView()
            } else {
                SetsRootView()
                    .frame(minWidth: SetsWindowSize.minimum.width, minHeight: SetsWindowSize.minimum.height)
                    .ignoresSafeArea()
            }
        }
        .defaultSize(SetsWindowSize.initial)
        .commands { LuminaCommands(menu: menu) }
    }
}

/// The menu bar (design/handoff/lumina-cull/MENUS.md). Every item reaches the page through
/// `window.luminaCommand(name)`, which presses the key the page already handles. Items whose
/// shortcut is a plain key (P, F, Space, Z, …) carry no key equivalent here: a menu would take
/// those keys before the page and break hold-to-show and key repeat. The page keeps handling them.
struct LuminaCommands: Commands {
    @ObservedObject var menu: SetsMenuModel

    private func send(_ name: String) { SetsMenuModel.command(name) }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Lumina") { SetsMenuModel.showAbout() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { send("settings") }.keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…") { send("open") }.keyboardShortcut("o", modifiers: .command)
            Menu("Open Recent") {
                ForEach(menu.recents) { r in
                    Button(r.title) { SetsMenuModel.reopen(r.id) }
                }
            }
            .disabled(menu.recents.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Shoot") { SetsMenuModel.closeShoot() }.keyboardShortcut("w", modifiers: .command)
            Button("Save Keepers") { send("save") }.keyboardShortcut(.return, modifiers: .command)
            Button("Show in Finder") { send("finder") }.keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Remove Working Files…") { SetsMenuModel.removeWorkingFiles() }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { send("undo") }.keyboardShortcut("z", modifiers: .command)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Keep Row") { send("keepRow") }.keyboardShortcut("a", modifiers: .command)
        }
        CommandMenu("Photo") {
            Button("Keep  P") { send("keep") }
            Button("Flag  F") { send("flag") }
            Button("Keep Sharpest of Stack  ⇧P") { send("keepStack") }
            Button("Flag Stack  ⇧F") { send("flagStack") }
            Divider()
            Button("Open Stack  ⏎") { send("openStack") }
            Button("Close Stack  esc") { send("closeStack") }
        }
        CommandGroup(before: .toolbar) {
            Button("Open") { send("stepOpen") }.keyboardShortcut("1", modifiers: .command)
            Button("Cull") { send("stepCull") }.keyboardShortcut("2", modifiers: .command)
            Button("Save") { send("stepSave") }.keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Large View  Space") { send("large") }
            Button("Zoom 100%  Z") { SetsMenuModel.zoom() }
            Button("Unseen Rows Only  ⇧U") { send("unseen") }
            Divider()
            Button("Smaller Tiles  −") { send("smaller") }
            Button("Larger Tiles  +") { send("larger") }
            Button("Hide Key Bar  H") { send("keyBar") }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Lumina FAQ") { send("faq") }
            Button("Keyboard Shortcuts  ?") { send("shortcuts") }
            Button("Contact on X") { SetsMenuModel.openLink("https://x.com/aniketh745") }
        }
    }
}

/// What the menu bar needs from the window: recent shoots, and a way to reach the page.
@MainActor
final class SetsMenuModel: ObservableObject {
    struct Recent: Identifiable, Equatable { let id: String; let title: String }

    static let shared = SetsMenuModel()
    @Published var recents: [Recent] = []
    weak var controller: SetsWindowController?

    static func command(_ name: String) { shared.controller?.command(name) }
    static func reopen(_ id: String) { shared.controller?.reopen(id) }
    static func closeShoot() { shared.controller?.closeShoot() }
    static func removeWorkingFiles() { shared.controller?.confirmRemoveWorkingFiles() }
    /// Z is a hold key in the page (100% while held): the menu toggles it on and off instead.
    static func zoom() { shared.controller?.toggleZoom() }

    static func openLink(_ s: String) { if let url = URL(string: s) { NSWorkspace.shared.open(url) } }

    static func showAbout() {
        let credits = NSAttributedString(string: "© 2026 Aniketh Maddipati\nHelp ▸ Lumina FAQ",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()])
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Lumina", .credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Quit asks when there are keepers whose sidecars aren't written yet (MENUS.md).
@MainActor
final class LuminaAppDelegate: NSObject, NSApplicationDelegate {
    private var asked = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if asked { return .terminateNow }
        guard let c = SetsMenuModel.shared.controller else { return .terminateNow }
        c.unsavedKeepers { n in
            guard n > 0 else { sender.reply(toApplicationShouldTerminate: true); return }
            let alert = NSAlert()
            alert.messageText = n == 1 ? "1 keeper isn't saved yet" : "\(n) keepers aren't saved yet"
            alert.informativeText = "Their sidecars aren't written. Your decisions stay for next time."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            let quit = alert.runModal() == .alertFirstButtonReturn
            self.asked = quit
            sender.reply(toApplicationShouldTerminate: quit)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
