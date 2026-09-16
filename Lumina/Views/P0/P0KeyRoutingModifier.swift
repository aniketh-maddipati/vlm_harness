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

private struct P0KeyRoutingRepresentable: NSViewRepresentable {
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
        }

        func detach() {
            removeMonitors()
        }

        private func removeMonitors() {
            for monitor in monitors {
                NSEvent.removeMonitor(monitor)
            }
            monitors = []
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard !session.showLegacyShell else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command)
            let shift = flags.contains(.shift)
            let chars = event.charactersIgnoringModifiers ?? ""
            let lower = chars.lowercased()

            if event.keyCode == 53 {
                if P0EscLadder.handle(session: session) {
                    return nil
                }
                return event
            }

            if session.route == .grouping {
                if shift && !command && lower == "g" {
                    if event.isARepeat { return nil }
                    session.leaveGrouping()
                    return nil
                }
                return event
            }

            if !command && lower == "b", session.inspectingAssetID != nil {
                if !event.isARepeat {
                    session.setShowingBefore(true)
                }
                return nil
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

            if command && !shift && lower == "z" {
                if event.isARepeat { return nil }
                session.undoLast()
                return nil
            }

            if event.keyCode == 49, !command {
                if !event.isARepeat {
                    session.setHoldingLoupe(true)
                }
                return nil
            }

            if !command && lower == "j" {
                if !event.isARepeat {
                    session.setHoldingClipping(true)
                }
                return nil
            }

            if !command && lower == "k", session.inspectingAssetID == nil {
                if event.isARepeat { return nil }
                session.keepFocusedBurst()
                return nil
            }

            if event.keyCode == 48, session.inspectingAssetID == nil {
                if event.isARepeat { return nil }
                session.toggleKeptRailWalk()
                return nil
            }

            if command && !shift && lower == "g", session.inspectingAssetID == nil {
                if !event.isARepeat {
                    session.beginLookGlance()
                }
                return nil
            }

            if shift && !command && lower == "g", session.inspectingAssetID == nil {
                if event.isARepeat { return nil }
                session.enterGrouping()
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

        private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
            guard !session.showLegacyShell else { return event }

            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.keyCode == 49 {
                session.setHoldingLoupe(false)
                return nil
            }
            if chars == "j" {
                session.setHoldingClipping(false)
                return nil
            }
            if session.lookGlancing, chars == "g" || event.keyCode == 54 || event.keyCode == 55 {
                session.endLookGlance()
                return nil
            }
            if chars == "b", !event.modifierFlags.contains(.command), session.inspectingAssetID != nil {
                session.setShowingBefore(false)
                return nil
            }
            return event
        }
    }
}

private final class P0KeyRoutingView: NSView {
    weak var coordinator: P0KeyRoutingRepresentable.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            coordinator?.detach()
        }
    }
}
