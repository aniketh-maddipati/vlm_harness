// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import AppKit
import SwiftUI

/// Sole owner of workspace `NSEvent` keyboard routing.
/// Uses local monitors (flagsChanged + keyDown/keyUp) because `.onKeyPress` /
/// `.keyboardShortcut` cannot express "second press of the same key".
/// ContentView keeps a separate monitor only for non-workspace / global chords.
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
            // Space release restores preview (Law 2).
            if event.keyCode == 49, !event.modifierFlags.contains(.command) {
                if shell.isTreatmentStageOpen, shell.treatmentPreviewMode == .original {
                    shell.treatmentPreviewMode = .current
                }
            }
            // ? release dismisses shortcuts glance (Law 2).
            let chars = event.charactersIgnoringModifiers ?? ""
            let shift = event.modifierFlags.contains(.shift)
            if chars == "?" || (shift && chars == "/") {
                shell.shortcutsGlanceHeld = false
            }
            return event
        }

        /// True while gathering / staged / multi-select / treatment — staging chords own the board.
        private var commandLayerActive: Bool {
            selection.isHandling || selection.staged != nil || !selection.isEmpty || shell.isTreatmentStageOpen
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command)
            let shift = flags.contains(.shift)
            let option = flags.contains(.option)
            let chars = event.charactersIgnoringModifiers ?? ""
            let lower = chars.lowercased()

            // Escape — workspace overlays / selection only (never dumps to Home).
            if event.keyCode == 53 {
                _ = shell.handleEscape(model: model)
                return nil
            }

            // Crop latch re-scopes decision keys (see .cursorrules — frame C).
            if shell.cropSession != nil {
                if event.keyCode == 36 || event.keyCode == 76, !event.isARepeat {
                    shell.applyCrop(model: model)
                    return nil
                }
                if !command && !event.isARepeat {
                    switch lower {
                    case "a":
                        shell.cropToggleAspectLock()
                        return nil
                    case "x":
                        shell.cropFlipOrientation()
                        return nil
                    default:
                        break
                    }
                }
            }

            // Key 4 — enter crop (Straighten section arms crop; no zoom jump).
            if !command && chars == "4", shell.isTreatmentStageOpen, shell.cropSession == nil {
                if let photoID = shell.selectedAssetID ?? selection.leader {
                    shell.enterCrop(for: photoID, model: model)
                }
                return nil
            }

            // ⌘Z undo round / last decision
            if command && !shift && !option && lower == "z" {
                shell.undoLastDecision(model: model)
                return nil
            }

            // ⌘⌥C — more treatment controls (never ⌘,)
            if command && option && !shift && lower == "c" {
                shell.showDetailedEdits = true
                return nil
            }

            // ⌘⇧A — apply the current treatment to every photo in the leader's set.
            if command && shift && !option && lower == "a", shell.isTreatmentStageOpen {
                let applied = shell.applyTreatmentToSet(model: model, presentation: presentation)
                if applied > 0 { LuminaHaptics.decision() } else { LuminaHaptics.light() }
                return nil
            }

            // ⌘1 Sources · ⌘2 Workbench · ⌘3 Story · ⌘R Read
            if command && !shift && !option {
                if chars == "1" {
                    shell.openShootSelection()
                    return nil
                }
                if chars == "2" {
                    shell.setWorkspaceStage(.workbench)
                    shell.isReadMode = false
                    return nil
                }
                if chars == "3" {
                    shell.setWorkspaceStage(.canvas)
                    shell.isReadMode = false
                    return nil
                }
                if lower == "r" {
                    shell.enterReadMode()
                    return nil
                }
            }

            // Arrow keys — ⇧ extends hand selection; plain moves focus / leader.
            if event.keyCode == 123 || event.keyCode == 124 { // ← →
                let delta = event.keyCode == 123 ? -1 : 1
                if shift {
                    let order = TablePhotographSelection.tableOrder(from: presentation.groups)
                    let focus = shell.selectedAssetID ?? selection.leader ?? model.cursor
                    guard let focus, let index = order.firstIndex(of: focus) else { return nil }
                    let next = min(max(index + delta, 0), order.count - 1)
                    let nextID = order[next]
                    shell.extendHandSelection(to: nextID, presentation: presentation)
                    if model.project != nil { model.setCursor(nextID) }
                    shell.loadDevelop(for: nextID, model: model)
                    return nil
                }
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

            // Hold-? — shortcuts glance (not ⌘/ modal sheet).
            if !command && (chars == "?" || (shift && chars == "/")) {
                shell.shortcutsGlanceHeld = true
                return nil
            }

            // Space — Edit: hold Original; otherwise 1:1 focus toggle (never bind ⌘Space)
            if event.keyCode == 49, !command {
                if shell.isTreatmentStageOpen {
                    shell.treatmentPreviewMode = .original
                    return nil
                }
                shell.toggleFocus()
                return nil
            }

            if event.keyCode == 36 || event.keyCode == 76 { // Return
                return handleReturn(event, command: command, shift: shift)
            }

            // ⌘⌫ / ⌘Delete — stage set aside
            if command && (event.keyCode == 51 || event.keyCode == 117) {
                return stage(.setAside)
            }

            // T opens treatment from workbench (even while gathering), or any stage when idle.
            if !command && lower == "t", (shell.workspaceStage == .workbench || !commandLayerActive) {
                shell.openTreatmentStage()
                return nil
            }

            // A — stage Develop proposal (decision key; swallows autorepeat — Law 3).
            if !command && lower == "a" {
                if shell.cropSession != nil { return nil }
                if event.isARepeat { return nil }
                if shell.isTreatmentStageOpen || !commandLayerActive {
                    Task { await shell.stageDevelopProposal(model: model, presentation: presentation) }
                    return nil
                }
            }

            // Legacy single-key routing when the command layer is idle (empty selection).
            if !command && !commandLayerActive {
                switch lower {
                case "e":
                    shell.toggleDetailedEdits()
                    return nil
                case "p", "s":
                    if event.isARepeat { return nil }
                    LuminaHaptics.decision()
                    if let photoID = shell.selectedAssetID ?? model.cursor {
                        shell.applyDecision(.keep, for: photoID, model: model)
                    }
                    return nil
                case "m":
                    if event.isARepeat { return nil }
                    LuminaHaptics.decision()
                    if let photoID = shell.selectedAssetID ?? model.cursor {
                        shell.applyDecision(.needsMe, for: photoID, model: model)
                    }
                    return nil
                case "x":
                    if shell.cropSession != nil { return nil }
                    if event.isARepeat { return nil }
                    LuminaHaptics.decision()
                    if let photoID = shell.selectedAssetID ?? model.cursor {
                        shell.applyDecision(.cut, for: photoID, model: model)
                    }
                    return nil
                case "g":
                    shell.openFinish()
                    return nil
                default:
                    break
                }
            }

            return event
        }

        private func handleReturn(_ event: NSEvent, command: Bool, shift: Bool) -> NSEvent? {
            // Auto-repeat defence — ignore held Return entirely.
            if event.isARepeat { return nil }

            // Confirm path: staged + fresh Return (keyUp seen) — ⌘ optional on second press.
            if selection.canConfirm(isARepeat: false), !shift {
                _ = shell.commitRound(selection, model: model)
                return nil
            }

            // ⇧⏎ — widen propagation or stage row adapt (decision key).
            if shift {
                if selection.staged?.isTreatStaging == true {
                    shell.widenPropagation(model: model)
                    return nil
                }
                if shell.isTreatmentStageOpen, !command {
                    guard let photoID = shell.selectedAssetID ?? selection.leader ?? model.cursor,
                          let groupID = presentation.selectedGroupID,
                          let photo = model.photo(with: photoID) else { return nil }
                    let recipe = model.appliedRecipe(for: photo).applying(shell.developOffsets)
                    shell.stageTreatAtRow(
                        model: model,
                        presentation: presentation,
                        recipe: recipe,
                        referencePhotoID: photoID,
                        referenceGroupID: groupID
                    )
                    return nil
                }
                if command {
                    return stage(.hold)
                }
                return nil
            }

            // Plain Return expands the active row when the command layer is idle.
            guard command else {
                if !commandLayerActive {
                    shell.toggleRowExpanded()
                    return nil
                }
                return event
            }

            // In treatment stage, ⌘↩ stages the recipe at row ring.
            if shell.isTreatmentStageOpen {
                if let photoID = selection.leader ?? shell.selectedAssetID ?? model.cursor,
                   let groupID = presentation.selectedGroupID,
                   let photo = model.photo(with: photoID) {
                    let recipe = model.appliedRecipe(for: photo).applying(shell.developOffsets)
                    shell.stageTreatAtRow(
                        model: model,
                        presentation: presentation,
                        recipe: recipe,
                        referencePhotoID: photoID,
                        referenceGroupID: groupID
                    )
                    return nil
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
