import AppKit
import SwiftUI

/// Local-monitor ⌘ handling layer — flagsChanged + real key-down/key-up separation.
/// `.onKeyPress` / `.keyboardShortcut` cannot express "second press of the same key".
struct CommandHandlingModifier: ViewModifier {
    @Bindable var shell: LuminaShellModel
    @Bindable var model: ProjectViewModel
    var presentation: WorkspacePresentation

    func body(content: Content) -> some View {
        content.background(
            CommandHandlingRepresentable(
                shell: shell,
                model: model,
                presentation: presentation
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }
}

extension View {
    func commandHandling(shell: LuminaShellModel, model: ProjectViewModel, presentation: WorkspacePresentation) -> some View {
        modifier(CommandHandlingModifier(shell: shell, model: model, presentation: presentation))
    }
}

private struct CommandHandlingRepresentable: NSViewRepresentable {
    var shell: LuminaShellModel
    var model: ProjectViewModel
    var presentation: WorkspacePresentation

    func makeNSView(context: Context) -> CommandHandlingView {
        let view = CommandHandlingView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: CommandHandlingView, context: Context) {
        context.coordinator.shell = shell
        context.coordinator.model = model
        context.coordinator.presentation = presentation
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shell: shell, model: model, presentation: presentation)
    }

    @MainActor
    final class Coordinator {
        var shell: LuminaShellModel
        var model: ProjectViewModel
        var presentation: WorkspacePresentation
        private var monitors: [Any] = []
        private var commandWasDown = false
        private weak var view: CommandHandlingView?

        init(shell: LuminaShellModel, model: ProjectViewModel, presentation: WorkspacePresentation) {
            self.shell = shell
            self.model = model
            self.presentation = presentation
        }

        func attach(to view: CommandHandlingView) {
            self.view = view
            removeMonitors()
            let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event) ?? event
            }
            let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event) ?? event
            }
            let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyUp(event) ?? event
            }
            monitors = [flags, down, up].compactMap { $0 }
        }

        deinit {
            // Monitors removed when the view detaches — see CommandHandlingView.
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

        private var selection: WorkbenchSelection { shell.workbenchSelection }

        private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
            let commandDown = event.modifierFlags.contains(.command)
            if commandDown && !commandWasDown {
                commandWasDown = true
                selection.setHandling(true)
                LuminaHaptics.light()
            } else if !commandDown && commandWasDown {
                commandWasDown = false
                selection.setHandling(false)
            }
            return event
        }

        private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
            if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
                selection.noteReturnKeyUp()
            }
            return event
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command)
            let shift = flags.contains(.shift)
            let option = flags.contains(.option)
            let chars = event.charactersIgnoringModifiers ?? ""

            // Escape
            if event.keyCode == 53 {
                _ = shell.handleEscape()
                return nil
            }

            // ⌘Z undo round / last decision
            if command && !shift && !option && (chars.lowercased() == "z") {
                shell.undoLastDecision(model: model)
                return nil
            }

            // ⌘⌥C — more treatment controls (never ⌘,)
            if command && option && !shift && (chars.lowercased() == "c") {
                shell.showDetailedEdits = true
                return nil
            }

            // T opens treatment when workbench
            if !command && chars.lowercased() == "t", shell.workspaceStage == .workbench {
                shell.openTreatmentStage()
                return nil
            }

            // ⌘1 Sources · ⌘2 Workbench · ⌘3 Story
            if command && !shift && !option {
                if chars == "1" {
                    shell.openShootSelection()
                    return nil
                }
                if chars == "2" {
                    if shell.route != .workspace { shell.openWorkspace(lens: shell.lens) }
                    shell.setWorkspaceStage(.workbench)
                    shell.isReadMode = false
                    return nil
                }
                if chars == "3" {
                    if shell.route != .workspace { shell.openWorkspace(lens: shell.lens) }
                    shell.setWorkspaceStage(.canvas)
                    shell.isReadMode = false
                    return nil
                }
                if chars.lowercased() == "r", shell.workspaceStage == .canvas || shell.workspaceStage == .proof {
                    shell.enterReadMode()
                    return nil
                }
            }

            // Arrow keys
            if event.keyCode == 123 || event.keyCode == 124 { // ← →
                let delta = event.keyCode == 123 ? -1 : 1
                if !selection.isEmpty {
                    selection.moveLeader(delta)
                    if let leader = selection.leader {
                        shell.selectAsset(leader)
                        model.setCursor(leader)
                        shell.loadDevelop(for: leader, model: model)
                    }
                    return nil
                }
                shell.moveAlternative(delta: delta, presentation: presentation, model: model)
                return nil
            }
            if event.keyCode == 125 || event.keyCode == 126 { // ↓ ↑
                let delta = event.keyCode == 126 ? -1 : 1
                shell.moveAttempt(delta: delta, presentation: presentation, model: model)
                return nil
            }

            // Space — Edit: hold Original; Workbench: 1:1 focus toggle (no ⌘ — never bind ⌘Space)
            if event.keyCode == 49, !command {
                if shell.isTreatmentStageOpen {
                    shell.treatmentPreviewMode = .original
                    return nil
                }
                if shell.workspaceStage == .workbench {
                    shell.toggleFocus()
                    return nil
                }
                return event
            }

            if event.keyCode == 36 || event.keyCode == 76 { // Return
                return handleReturn(event, command: command, shift: shift)
            }

            // ⌘⌫ / ⌘Delete — stage set aside
            if command && (event.keyCode == 51 || event.keyCode == 117) {
                return stage(.setAside)
            }

            return event
        }

        private func handleReturn(_ event: NSEvent, command: Bool, shift: Bool) -> NSEvent? {
            // Auto-repeat defence — ignore held Return entirely.
            if event.isARepeat { return nil }

            // Confirm path: staged + fresh Return (keyUp seen) — ⌘ optional on second press.
            if selection.canConfirm(isARepeat: false) {
                _ = shell.commitRound(selection, model: model)
                return nil
            }

            // First press must hold ⌘
            guard command else { return event }

            if shift {
                return stage(.hold)
            }

            // In treatment stage, ⌘↩ stages the recipe across the selection.
            if shell.isTreatmentStageOpen {
                if let photoID = selection.leader ?? shell.selectedAssetID,
                   let photo = model.photo(with: photoID) {
                    let recipe = model.appliedRecipe(for: photo).applying(shell.developOffsets)
                    return stage(.treat(recipe))
                }
            }

            return stage(.advance)
        }

        private func stage(_ action: StagedAction) -> NSEvent? {
            // Empty selection cannot stage — light haptic only.
            guard selection.stage(action) else {
                LuminaHaptics.light()
                return nil
            }
            LuminaHaptics.decision()
            return nil
        }
    }
}

final class CommandHandlingView: NSView {
    fileprivate weak var coordinator: CommandHandlingRepresentable.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            coordinator?.detach()
        }
    }
}
