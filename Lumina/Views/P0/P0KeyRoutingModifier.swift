import AppKit
import SwiftUI

/// Sole owner of P0 live-path `NSEvent` keyboard routing (`LuminaApp` → `P0RootView`).
/// Decision keys swallow autorepeat; travel keys autorepeat. Esc resolves via `P0EscLadder`.
struct P0KeyRoutingModifier: ViewModifier {
    @Bindable var session: P0SessionModel

    func body(content: Content) -> some View {
        content.background(
            P0KeyRoutingRepresentable(session: session)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

extension View {
    func p0KeyRouting(session: P0SessionModel) -> some View {
        modifier(P0KeyRoutingModifier(session: session))
    }
}

struct P0KeyRoutingRepresentable: NSViewRepresentable {
    var session: P0SessionModel

    func makeNSView(context: Context) -> P0KeyRoutingView {
        let view = P0KeyRoutingView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: P0KeyRoutingView, context: Context) {
        context.coordinator.session = session
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator {
        var session: P0SessionModel
        private var monitors: [Any] = []
        private var resignObserver: NSObjectProtocol?
        private weak var view: P0KeyRoutingView?

        init(session: P0SessionModel) {
            self.session = session
        }

        func attach(to view: P0KeyRoutingView) {
            self.view = view
            removeMonitors()
            let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event) ?? event
            }
            let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyUp(event) ?? event
            }
            monitors = [down, up].compactMap { $0 }
            // A held key never comes back up for us once the app loses key status
            // (⌘⇥ is the common case), so every hold releases with the app.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.releaseHolds()
                }
            }
        }

        private func releaseHolds() {
            session.closePeek()
            session.setShowingBefore(false)
            session.setHoldingClipping(false)
        }

        func detach() {
            removeMonitors()
        }

        private func removeMonitors() {
            for monitor in monitors {
                NSEvent.removeMonitor(monitor)
            }
            monitors = []
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
            resignObserver = nil
        }

        func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command)
            let shift = flags.contains(.shift)
            let unmodified = flags.intersection([.command, .shift, .option, .control]).isEmpty
            let chars = event.charactersIgnoringModifiers ?? ""
            let lower = chars.lowercased()

            // Native export controls own ordinary navigation/activation keys.
            // Export command chords deliberately retain the app route below.
            if session.exportControlsFocused && !(command && !shift && lower == "e") { return event }

            if event.keyCode == 53 {
                if P0EscLadder.handle(session: session) {
                    return nil
                }
                return event
            }

            // Note floater owns typing while open; Esc already handled above.
            if session.noteFloaterOpen { return event }

            // ⌃⇥ — cycle chrome regions (Chat-2). Plain ⇥ stays the peek.
            if event.keyCode == P0VirtualKey.tab,
               flags.contains(.control),
               !command,
               session.route != .open {
                if event.isARepeat { return nil }
                session.cycleChromeRegion()
                return nil
            }

            // ⇥ — the one peek. Hold: similar; a pinned peek cycles on ⇥ and closes past
            // the end. Release is decided in `handleKeyUp`. ⌘⇥ belongs to the system.
            if event.keyCode == P0VirtualKey.tab, !command, session.route != .open {
                if event.isARepeat { return nil }
                if session.peek != nil, session.peekPinned {
                    session.cyclePeek(by: 1, wrap: false)
                } else if session.peek == nil {
                    session.openPeek(.related)
                }
                return nil
            }

            if session.peek != nil {
                switch event.keyCode {
                case 125:
                    session.cyclePeek(by: 1)
                    return nil
                case 126:
                    session.cyclePeek(by: -1)
                    return nil
                default:
                    break
                }
                if unmodified, chars.count == 1, let number = Int(chars), (1...9).contains(number) {
                    if event.isARepeat { return nil }
                    session.jumpInPeek(to: number)
                    return nil
                }
            }

            // ⇧ + arrows — extend selection from the anchor. Must precede the plain
            // arrow switch below, or shift-arrow would travel instead of extending.
            if shift, !command, [123, 124, 125, 126].contains(event.keyCode) {
                if event.isARepeat { return nil }
                let dx: Int
                let dy: Int
                switch event.keyCode {
                case 123: dx = -1; dy = 0
                case 124: dx = 1; dy = 0
                case 126: dx = 0; dy = -1
                default: dx = 0; dy = 1
                }
                session.extendSelection(dx: dx, dy: dy)
                return nil
            }

            if unmodified, chars == "]", !event.isARepeat {
                session.flipPage()
                return nil
            }

            if event.keyCode == P0VirtualKey.pageUp || event.keyCode == P0VirtualKey.pageDown {
                let step = event.keyCode == P0VirtualKey.pageDown ? 1 : -1
                if session.stitchOpen {
                    session.stepStitchFocus(step)
                    armTravel(event)
                    return nil
                }
                if session.route == .focus {
                    session.stepFramePage(step)
                    armTravel(event)
                    return nil
                }
                if session.route == .time {
                    session.requestMomentPage(step: step)
                    armTravel(event)
                    return nil
                }
            }

            switch event.keyCode {
            case 123:
                session.moveFocus(dx: -1, dy: 0, columns: session.densityColumns)
                armTravel(event)
                return nil
            case 124:
                session.moveFocus(dx: 1, dy: 0, columns: session.densityColumns)
                armTravel(event)
                return nil
            case 126:
                session.moveFocus(dx: 0, dy: -1, columns: session.densityColumns)
                armTravel(event)
                return nil
            case 125:
                session.moveFocus(dx: 0, dy: 1, columns: session.densityColumns)
                armTravel(event)
                return nil
            default:
                break
            }

            if event.keyCode == 36 || event.keyCode == 76 {
                if event.isARepeat { return nil }
                if session.inspectingAssetID == nil {
                    session.activateFocusedPhotograph()
                }
                return nil
            }

            if !command && (lower == "=" || lower == "+") {
                guard session.inspectingAssetID == nil else { return event }
                session.adjustDensity(-1)
                armZoom(event)
                return nil
            }

            if !command && (lower == "-" || lower == "_") {
                guard session.inspectingAssetID == nil else { return event }
                session.adjustDensity(1)
                armZoom(event)
                return nil
            }

            if !command && lower == "p" {
                if event.isARepeat { return nil }
                session.pressKeep()
                armMark(event)
                return nil
            }

            if !command && lower == "x" {
                if event.isARepeat { return nil }
                session.pressReject()
                armMark(event)
                return nil
            }

            // Chat-2: S toggles set membership (focused frame or selection). Recipe untouched.
            if unmodified, lower == "s", session.route != .open {
                if event.isARepeat { return nil }
                session.toggleSetMembershipFromKeyboard()
                armMark(event)
                return nil
            }

            // Chat-2: H toggles phone mark on the same target.
            if unmodified, lower == "h", session.route != .open {
                if event.isARepeat { return nil }
                session.togglePhoneFromKeyboard()
                return nil
            }

            // Chat-2: ⌘A selects every photograph.
            if command, !shift, lower == "a", session.route != .open {
                if event.isARepeat { return nil }
                session.selectAllPhotographs()
                return nil
            }

            if command && !shift && lower == "z" {
                if event.isARepeat { return nil }
                session.undoLast()
                return nil
            }

            if command,
               !shift,
               lower == "e" {
                if event.isARepeat { return nil }
                if event.modifierFlags.contains(.option) { session.exportSettingsVisible = true }
                else { session.chooseAndExportKept() }
                return nil
            }

            // Hold ␣ — before. Everything as shot while held; release returns. Never
            // mutates recipe or undo. In both routes: the headline says it on the table.
            if event.keyCode == P0VirtualKey.space, !command, session.route != .open {
                if !event.isARepeat {
                    session.setShowingBefore(true)
                }
                return nil
            }

            if !command && lower == "j" {
                if !event.isARepeat {
                    session.setHoldingClipping(true)
                }
                return nil
            }

            // Develop, in the focus route: A stages looks; R turns. The rail is always on.
            if unmodified, session.route == .focus, lower == "a" {
                if event.isARepeat { return nil }
                if let id = session.focusedAssetID {
                    session.stageAutoVariations(for: id)
                }
                return nil
            }

            if unmodified, session.route == .focus, session.hasStagedAutoVariations,
               chars.count == 1, let number = Int(chars), (1...3).contains(number) {
                if event.isARepeat { return nil }
                session.pickStagedVariation(at: number - 1)
                return nil
            }

            if unmodified, session.route == .focus, lower == "r" {
                if event.isARepeat { return nil }
                session.rotateFocusedPhotograph()
                return nil
            }

            // Chat-4: [ ] cycle Develop groups on the always-on rail.
            if unmodified, session.route == .focus,
               chars == "[" || chars == "]" {
                if event.isARepeat { return nil }
                session.cycleDevelopGroup(by: chars == "]" ? 1 : -1)
                return nil
            }

            // MARK: Chat-4 — note floater (below Chat-2 blocks)
            if unmodified, lower == "n", session.route == .focus {
                if event.isARepeat { return nil }
                session.toggleNoteFloater()
                return nil
            }

            // G inside the flags peek takes the inferred picks — one command, one ⌘Z.
            if unmodified, lower == "g", session.peek == .flags {
                if event.isARepeat { return nil }
                session.takeInferredPicks()
                return nil
            }

            if !command && lower == "k", session.inspectingAssetID == nil {
                if event.isARepeat { return nil }
                session.keepFocusedBurst()
                return nil
            }

            return event
        }

        // Instrumentation only. Each helper is called *after* the state mutation it times,
        // so the next presented frame is the first that can carry the change. None of them
        // inspects or consumes the event: routing ownership is unchanged.
        private func armTravel(_ event: NSEvent) {
            P0RenderInstruments.shared.arm(P0RenderInstruments.Key.keyTravel, event: event)
        }

        private func armMark(_ event: NSEvent) {
            P0RenderInstruments.shared.arm(P0RenderInstruments.Key.keyMark, event: event)
        }

        private func armZoom(_ event: NSEvent) {
            P0RenderInstruments.shared.arm(P0RenderInstruments.Key.zoomGesture, event: event)
        }

        func handleKeyUp(_ event: NSEvent) -> NSEvent? {
            if session.exportControlsFocused && !event.modifierFlags.contains(.command) { return event }
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌃⇥ region cycle — do not treat the release as peek pin/hold.
            if event.keyCode == P0VirtualKey.tab, flags.contains(.control) {
                return nil
            }
            if event.keyCode == P0VirtualKey.tab {
                session.releasePeekKey()
                return nil
            }
            if event.keyCode == P0VirtualKey.space {
                session.setShowingBefore(false)
                return nil
            }
            if chars == "j" {
                session.setHoldingClipping(false)
                return nil
            }
            return event
        }
    }
}

final class P0KeyRoutingView: NSView {
    weak var coordinator: P0KeyRoutingRepresentable.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            coordinator?.detach()
        }
    }
}
