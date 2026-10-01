import Foundation

// WP-1. What the window does with a key and with a drop, as plain functions so the rules can be
// tested without a window. The shell's event monitor (`LuminaUI/Shell/KeyMonitor.swift`) and its
// drop target only translate AppKit into these calls.

public extension AppModel {
    /// A key event from the window's event monitor. Returns true when Lumina took the key (the
    /// monitor drops the event) and false when it belongs to someone else: the text field being
    /// typed in, or AppKit (menus, ⌘Q, ⌘W, Tab).
    ///
    /// - `typing`: a text field has the keyboard. It types (R-22): only ⌘1–4, ⌘S and ⌘O still
    ///   reach the app, and `endTyping` is called first so the field commits before the step changes.
    /// - A ⌘ or ⌃ chord nothing binds is never taken, whatever layer is open, so the menus keep
    ///   working under Crop, Help and Variations.
    /// - A held ⌘1–4 / ⌘S / ⌘O is taken and does nothing: it must not fall through to a menu item
    ///   with the same shortcut and act a second time (KEYMAP "Held repeats are ignored").
    @discardableResult
    func windowKey(_ key: KeyEvent, typing: Bool = false, endTyping: () -> Void = {}) -> Bool {
        let chord = !key.modifiers.isDisjoint(with: [.command, .control])
        if typing {
            guard let global = KeyRouter.binding(key, .global) else { return false }
            if global != .none { endTyping(); perform(global) }
            return true
        }
        let route = KeyRouter.route(key, layers: layers)
        // "Swallows every unbound single key" is about single keys: a chord the handling layer
        // doesn't bind goes on to the menus, and says nothing.
        if chord, KeyRouter.binding(key, route.handler) == nil { return false }
        handle(key)
        // macOS sends no key-up for a key released while ⌘ is down, so a chord is never "held".
        if key.modifiers.contains(.command) { heldKeys.remove(key.key) }
        if route.action == .typing { return false }
        // Nothing bound it and no layer owns the keyboard: AppKit's (Tab, Space on a focused button).
        if route.handler == .global, route.action == .none { return KeyRouter.binding(key, .global) != nil }
        return true
    }

    /// A drag carrying files entered (true) or left (false) the window: `shell.dropOverlay`.
    func dropHover(_ over: Bool) {
        if imports.dropTargeted != over { imports.dropTargeted = over }
    }

    /// The drop itself, on any step. The overlay always goes; file URLs are imported and the step
    /// stays where it is; a drop with no files in it (text, a web link) does nothing (R-17).
    func dropFiles(_ urls: [URL]) {
        dropHover(false)
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { importURLs(files) }
    }
}
