import Foundation

// WP-5. Edit keys that change settings or decisions (KEYMAP "Edit"; R-03, R-07, R-27, R-28).

public extension AppModel {
    /// Entering Edit: stay where Edit was left if that photo is still kept, else the first keeper.
    func enterEdit() {
        let kept = keptIDs
        if editCur == nil || !kept.contains(editCur!) { editCur = kept.first }
        edit.photo = .loading
        if breakpoints.editControlsStartCollapsed { edit.controlsCollapsed = true }
    }

    /// Leaving Edit: every pending edit is written (R-07), overlays close.
    func leaveEdit() {
        flushEdits()
        edit.overlay = nil; edit.focus = false; edit.before = false; edit.beforeHeld = false
        edit.typingKey = nil; edit.draggingKey = nil; edit.variationKey = nil; edit.cropDraft = nil
        edit.zoom = 1; edit.pan = .zero
    }

    /// WP-5: write whatever a drag or a debounce is still holding.
    func flushEdits() {}

    /// The setting keys act on: the one under the pointer, else the chosen one.
    var targetKey: String { edit.hoverKey ?? edit.activeKey }

    /// Set a slider value on the current photo.
    func setValue(_ key: String, _ value: Double?, coalesce: Bool = false) {
        guard let id = editCur else { return }
        let v = value.map { EditSetting.byKey[key]?.clamp($0) ?? $0 }
        edits.set(key, v, on: id, decisions: decisions, coalesce: coalesce)
        edits.tags[edits.key(for: id, decisions: decisions)] = currentLook.isEmpty ? nil : "Edited"
        changed()
    }

    func value(_ key: String) -> Double { currentLook[key] ?? EditSetting.byKey[key]?.def ?? 0 }

    /// , and .: one step (⇧: five). Temperature moves by 2 % per step.
    func nudge(_ d: Int, coarse: Bool) {
        guard let s = EditSetting.byKey[targetKey] else { return }
        let n = Double(d) * (coarse ? 5 : 1), v = value(s.key)
        setValue(s.key, s.log ? v * (1 + 0.02 * n) : v + s.step * n)
    }

    /// [ and ]: choose which setting nudges act on, within the open section.
    func pickSetting(_ d: Int) {
        let keys = EditSetting.of(edit.section).map(\.key).filter { edit.section != .colour || $0.hasPrefix(edit.colourAxis + "_") }
        guard !keys.isEmpty else { return }
        let i = keys.firstIndex(of: edit.activeKey) ?? 0
        edit.activeKey = keys[(i + d + keys.count) % keys.count]
        if let s = EditSetting.byKey[edit.activeKey] { say(s.label) }
    }

    func resetSetting() { setValue(targetKey, nil) }

    func resetAll() {
        guard let id = editCur else { return }
        edits.setLook([:], on: id, decisions: decisions); edits.tags[edits.key(for: id, decisions: decisions)] = nil; changed()
    }

    /// ⏎: mark done and go to the next photo; on the last, go to Save without saving (R-03).
    func editEnter() {
        guard let id = editCur else { return }
        edits.done.insert(edits.key(for: id, decisions: decisions))
        let kept = keptIDs
        if let i = kept.firstIndex(of: id), i + 1 < kept.count { showEditPhoto(kept[i + 1]) } else { go(.save) }
        changed()
    }

    /// X: Out, and on to the next keeper. Edit's ⌘Z brings it back; Cull's history is reset (R-08).
    func editOut() {
        guard let id = editCur else { return }
        let kept = keptIDs, i = kept.firstIndex(of: id) ?? 0
        edits.recordDecision(.init(id: id, before: decisions.keep[id], after: false), photo: id)
        decisions.set(id, keep: false); decisions.resetHistory()
        let rest = kept.filter { $0 != id }
        showEditPhoto(rest.isEmpty ? nil : rest[min(i, rest.count - 1)])
        changed()
    }

    func editUndo() {
        guard let e = edits.undo() else { return }
        if let d = e.decision { decisions.set(d.id, keep: d.before); decisions.resetHistory() }
        showEditPhoto(e.photo); changed()
    }
    func editRedo() {
        guard let e = edits.redo() else { return }
        if let d = e.decision { decisions.set(d.id, keep: d.after); decisions.resetHistory() }
        showEditPhoto(e.decision == nil ? e.photo : (keptIDs.first { $0 != e.photo } ?? nil)); changed()
    }

    // WP-5: the rest of the Edit keys.
    func auto() {}
    func sameAsLast() {}
    func pickWhite() {}
    func copySettings() {}
    func pasteSettings() {}
}
