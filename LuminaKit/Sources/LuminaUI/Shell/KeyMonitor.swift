import SwiftUI
import AppKit
import LuminaCore

// WP-1. Keys reach the model through one local event monitor per window; views never read keys.

@MainActor
final class KeyMonitor {
    private var monitor: Any?
    weak var window: NSWindow?

    func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak model] event in
            guard let self, let model, let w = self.window, event.window === w else { return event }
            // A text field has the keyboard: it types (R-22). Only ⌘1–4, ⌘S, ⌘O still reach the app.
            let typing = w.firstResponder is NSTextView
            guard let key = Self.keyEvent(event) else { return event }
            if typing {
                let r = KeyRouter.route(key, layers: [.textField])
                guard r.handler == .global else { return event }
                w.makeFirstResponder(nil)
            }
            let route = model.handle(key)
            // Unbound keys go on to AppKit (menus, ⌘Q, ⌘W); everything a layer took stops here.
            if route.action == .none, route.handler == .global || !key.modifiers.isDisjoint(with: [.command, .control]) { return event }
            return route.action == .typing ? event : nil
        }
    }
    func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }

    static let named: [UInt16: String] = [36: "return", 76: "return", 53: "escape", 123: "left", 124: "right", 125: "down", 126: "up",
                                         48: "tab", 51: "delete", 117: "delete", 49: "space", 115: "home", 119: "end", 116: "pageup", 121: "pagedown"]
    static func keyEvent(_ e: NSEvent) -> KeyEvent? {
        var m: KeyModifiers = []
        if e.modifierFlags.contains(.command) { m.insert(.command) }
        if e.modifierFlags.contains(.shift) { m.insert(.shift) }
        if e.modifierFlags.contains(.option) { m.insert(.option) }
        if e.modifierFlags.contains(.control) { m.insert(.control) }
        guard let k = named[e.keyCode] ?? e.charactersIgnoringModifiers, !k.isEmpty else { return nil }
        return KeyEvent(k, m, isRepeat: e.type == .keyDown && e.isARepeat, phase: e.type == .keyUp ? .up : .down)
    }
}

/// Finds the hosting window and configures it: full-size content, transparent hidden-title
/// titlebar (no toolbar gap, R-57), minimum 320×420.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { configure(w); onWindow(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
    private func configure(_ w: NSWindow) {
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.contentMinSize = NSSize(width: 320, height: 420)
        w.backgroundColor = NSColor(srgbRed: 30 / 255, green: 29 / 255, blue: 27 / 255, alpha: 1)
    }
}
