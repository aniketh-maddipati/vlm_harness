import SwiftUI
import AppKit
import LuminaCore

// WP-1. Keys reach the model through one local event monitor per window; views never read keys.
// NSEvent → KeyEvent → `model.windowKey` (→ `model.handle` → KeyRouter). The rules about what
// the app takes and what it leaves to a text field or to AppKit are in
// `LuminaCore/Flow/AppModel+WindowInput.swift`, where they are tested without a window.

/// What the shell knows about its window that the views lay out around.
@MainActor @Observable
final class ShellChrome {
    /// Right edge of the close / minimise / zoom buttons in window points; 0 when there are none
    /// (full screen, a borderless window).
    var trafficLights: CGFloat = 0
}

@MainActor
final class KeyMonitor {
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private(set) weak var window: NSWindow?
    private weak var model: AppModel?
    private weak var chrome: ShellChrome?

    /// Take over `w` for `model`: keys, blur, the resize hook, the traffic-light inset. Safe to
    /// call again; a second call for the same window only makes sure the monitor is in.
    func attach(_ w: NSWindow, model: AppModel, chrome: ShellChrome) {
        if window === w, self.model === model { install(); return }
        detach()
        window = w; self.model = model; self.chrome = chrome
        install()

        let nc = NotificationCenter.default
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (KeyMonitor) -> Void) {
            observers.append(nc.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        // The window lost the keyboard: held keys are forgotten and Variations closes (R-24).
        on(NSWindow.didResignKeyNotification) { $0.blurred() }
        // No monitor outlives its window (a second window must not hear the first one's keys).
        on(NSWindow.willCloseNotification) { $0.detach() }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
            on(name) { $0.refreshChrome() }
        }
        on(NSWindow.didBecomeKeyNotification) { $0.releaseDebugField() }

        model.hooks.resize = { [weak w] size in if let w { WindowChrome.setContentSize(size, of: w) } }
        // The shell's own part of a blur (`debug.command` {"blur":true} calls `windowBlurred()` itself).
        model.hooks.blur = { [weak model] in model?.dropHover(false) }
        refreshChrome()
        if let size = model.config.window { WindowChrome.setContentSize(size, of: w) }
        releaseDebugField()
    }

    /// AppKit gives a new window's first text field the keyboard. In UI-test builds that is the
    /// hidden `debug.command` field, which then swallowed every key the tests typed. Only that
    /// field is released, now and once SwiftUI has settled; a click on it (how the tests send a
    /// command) still focuses it, and a real text field keeps the keyboard.
    func releaseDebugField() {
        func release() {
            guard let w = window, let editor = w.firstResponder as? NSTextView, isDebugField(editor), editor.string.isEmpty else { return }
            w.makeFirstResponder(nil)
        }
        release()
        for delay in [0.05, 0.3] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { release() } } }
    }

    /// The field editor is editing the debug.command hook: by its identifier, or by its size (it
    /// is laid out 1 x 1; AppKit reports it a few points wide), since SwiftUI doesn't always pass
    /// the identifier down to the NSTextField.
    private func isDebugField(_ editor: NSTextView) -> Bool {
        guard model?.config.uiTest == true, let field = editor.delegate as? NSTextField else { return false }
        return field.accessibilityIdentifier() == AccessibilityID.Debug.command || field.frame.width <= 4
    }

    /// Stop listening: the window closed or the shell went away.
    func detach() {
        remove()
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        window = nil; model = nil; chrome = nil
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { self?.take(event) ?? false } ? nil : event
        }
    }

    func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }

    /// True when Lumina took the event.
    private func take(_ event: NSEvent) -> Bool {
        // Only this window's keys: not another Lumina window's, not a sheet's or an open panel's.
        guard let model, let w = window, event.window === w, let key = Self.keyEvent(event) else { return false }
        // The hidden debug.command field has the keyboard but no command is being typed into it
        // (commands start with "{"): the key is the app's. SwiftUI hands that field the keyboard
        // whenever nothing else holds it, so releasing it once isn't enough.
        if let editor = w.firstResponder as? NSTextView, isDebugField(editor), editor.string.isEmpty,
           !(event.type == .keyDown && event.charactersIgnoringModifiers == "{") {
            w.makeFirstResponder(nil)
        }
        // A text field has the keyboard: it types (R-22). Only ⌘1–4, ⌘S, ⌘O still reach the app.
        let typing = w.firstResponder is NSText
        return model.windowKey(key, typing: typing) { w.makeFirstResponder(nil) }
    }

    private func blurred() {
        guard let model else { return }
        model.windowBlurred()
        model.hooks.blur?()
    }

    private func refreshChrome() {
        guard let w = window, let chrome else { return }
        let x = WindowChrome.trafficLights(w)
        if chrome.trafficLights != x { chrome.trafficLights = x }
    }

    static let named: [UInt16: String] = [36: "return", 76: "return", 53: "escape", 123: "left", 124: "right", 125: "down", 126: "up",
                                         48: "tab", 51: "delete", 117: "delete", 49: "space", 115: "home", 119: "end", 116: "pageup", 121: "pagedown"]
    /// The digit keys by position, so ⌘1…⌘4 work on layouts where the digits need ⇧ (AZERTY).
    /// The prototype matches them by position too (`event.code`).
    static let digits: [UInt16: String] = [18: "1", 19: "2", 20: "3", 21: "4"]

    static func keyEvent(_ e: NSEvent) -> KeyEvent? {
        guard e.type == .keyDown || e.type == .keyUp else { return nil }
        var m: KeyModifiers = []
        if e.modifierFlags.contains(.command) { m.insert(.command) }
        if e.modifierFlags.contains(.shift) { m.insert(.shift) }
        if e.modifierFlags.contains(.option) { m.insert(.option) }
        if e.modifierFlags.contains(.control) { m.insert(.control) }
        let digit = m.contains(.command) ? digits[e.keyCode] : nil
        guard let k = named[e.keyCode] ?? digit ?? e.charactersIgnoringModifiers, !k.isEmpty else { return nil }
        return KeyEvent(k, m, isRepeat: e.type == .keyDown && e.isARepeat, phase: e.type == .keyUp ? .up : .down)
    }
}

/// The window's own chrome: full-size content, transparent hidden-title titlebar (no toolbar
/// gap, R-57), minimum 320×420.
@MainActor
enum WindowChrome {
    static let minSize = NSSize(width: 320, height: 420)

    static func configure(_ w: NSWindow) {
        if w.styleMask.contains(.titled) {
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.titlebarSeparatorStyle = .none
            // A native tab bar would sit on top of the step tabs.
            w.tabbingMode = .disallowed
        }
        w.contentMinSize = minSize
        w.backgroundColor = NSColor(srgbRed: 30 / 255, green: 29 / 255, blue: 27 / 255, alpha: 1)
    }

    /// Right edge of the standard window buttons in window points; 0 when the window has none.
    static func trafficLights(_ w: NSWindow) -> CGFloat {
        guard w.styleMask.contains(.titled), !w.styleMask.contains(.fullScreen) else { return 0 }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let edges = buttons.compactMap { w.standardWindowButton($0) }.filter { !$0.isHidden && $0.superview != nil }
            .map { $0.convert($0.bounds, to: nil).maxX }
        return edges.max() ?? 0
    }

    /// `debug.command` {"resize":[w,h]} and `LUMINA_WINDOW`: make the content exactly `size`
    /// points (never under the minimum), keeping the top-left corner where it is and the top
    /// bar on screen.
    static func setContentSize(_ size: CGSize, of w: NSWindow) {
        let size = CGSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))
        func frame(content: CGSize) -> NSRect {
            var f = w.frameRect(forContentRect: NSRect(origin: .zero, size: content))
            f.origin = CGPoint(x: w.frame.minX, y: w.frame.maxY - f.height)
            if let v = w.screen?.visibleFrame {
                if f.maxX > v.maxX { f.origin.x = max(v.minX, v.maxX - f.width) }
                if f.maxY > v.maxY || f.minY < v.minY { f.origin.y = v.maxY - f.height }
            }
            return f
        }
        w.setFrame(frame(content: size), display: true)
        // With a full-size content view the content is the whole frame, whatever
        // `frameRect(forContentRect:)` allowed for the titlebar: correct by what is left over.
        if let c = w.contentView?.frame.size, abs(c.width - size.width) > 0.5 || abs(c.height - size.height) > 0.5 {
            w.setFrame(frame(content: CGSize(width: 2 * size.width - c.width, height: 2 * size.height - c.height)), display: true)
        }
    }
}

/// Finds the hosting window, configures it (`WindowChrome.configure`) and hands it over.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(onWindow) }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class Probe: NSView {
        let onWindow: (NSWindow) -> Void
        private weak var seen: NSWindow?
        init(_ onWindow: @escaping (NSWindow) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("not in a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Not inside the view update that put us here.
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window, w !== self.seen else { return }
                self.seen = w
                WindowChrome.configure(w); self.onWindow(w)
            }
        }
    }
}

/// The empty parts of the top bar move the window, like a titlebar (the bar is taller than the
/// system's 28pt), and a double-click does what the user chose in System Settings.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class Handle: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            guard let w = window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": w.performMiniaturize(nil)
                case "None": break
                default: w.performZoom(nil)
                }
            } else {
                w.performDrag(with: event)
            }
        }
    }
}
