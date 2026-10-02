import Foundation

// WP-5. Edit keys that change settings or decisions (KEYMAP "Edit"; R-03, R-07, R-08, R-20,
// R-27, R-28). What the pointer does to a slider is in `AppModel+EditControls.swift`.

public extension AppModel {
    /// WP-5's own state: the copied settings, the last edit, the drag in progress.
    var editControls: EditControlState { feature(EditControlState.self) { EditControlState() } }

    /// Entering Edit: stay where Edit was left if that photo is still kept, else the first keeper.
    func enterEdit() {
        let kept = keptIDs
        if editCur == nil || !kept.contains(editCur!) { editCur = kept.first }
        edit.photo = .loading
        edit.hoverKey = nil; edit.typingKey = nil; edit.draggingKey = nil
        if breakpoints.editControlsStartCollapsed { edit.controlsCollapsed = true }
    }

    /// Leaving Edit: every pending edit is written (R-07), overlays close.
    func leaveEdit() {
        flushEdits()
        edit.overlay = nil; edit.focus = false; edit.before = false; edit.beforeHeld = false
        edit.typingKey = nil; edit.draggingKey = nil; edit.variationKey = nil; edit.cropDraft = nil
        edit.hoverKey = nil; edit.pickingWhite = false
        edit.zoom = 1; edit.pan = .zero
    }

    /// Write whatever a drag or a swipe is still holding: the drag ends where it is and the
    /// debounced `changed()` happens now (R-07: an edit made 50 ms before leaving is saved).
    func flushEdits() {
        if editControls.drag != nil { endDrag(cancel: false, announce: false) }
        editControls.swipe = nil
        writeEdits()
    }

    /// The setting keys act on: the one under the pointer, else the chosen one.
    var targetKey: String {
        if let h = edit.hoverKey, EditSetting.byKey[h] != nil { return h }
        return activeSettingKey
    }

    /// Set a slider value on the current photo (nil = back to its default).
    func setValue(_ key: String, _ value: Double?, coalesce: Bool = false) {
        guard let id = editCur else { return }
        let s = EditSetting.byKey[key]
        var l = edits.look(id, decisions: decisions)
        if let value, value.isFinite {
            let v = s.map { SliderScale.round($0, value) } ?? value
            l[key] = v == s?.def ? nil : v
        } else { l[key] = nil }
        commitLook(l, coalesce: coalesce)
    }

    /// The value of a setting on the Edit photo (its default when untouched).
    func value(_ key: String) -> Double { editLook[key] ?? EditSetting.byKey[key]?.def ?? 0 }

    /// , and .: one step (⇧: five). Temperature moves by 2 % per step.
    func nudge(_ d: Int, coarse: Bool) {
        guard editCur != nil else { return }
        if edit.hoverKey == nil { editControls.keyboardChoosing = true }
        nudgeSetting(targetKey, d, coarse: coarse)
    }

    /// [ and ]: choose which setting nudges act on, within the open section.
    func pickSetting(_ d: Int) {
        let keys = visibleSettings.map(\.key)
        guard !keys.isEmpty else { return }
        let i = keys.firstIndex(of: activeSettingKey) ?? 0
        edit.activeKey = keys[(i + d + keys.count) % keys.count]
        editControls.keyboardChoosing = true
        say(EditFormat.label(edit.activeKey))
    }

    func resetSetting() {
        guard editCur != nil else { return }
        let key = targetKey
        setValue(key, nil)
        say("\(EditFormat.label(key)) reset")
    }

    func resetAll() {
        guard editCur != nil else { return }
        if commitLook([:], remember: false) { say("As shot") }
    }

    /// ⏎: mark done and go to the next photo; on the last, go to Save without saving (R-03).
    func editEnter() {
        guard let id = editCur else { return }
        flushEdits()
        edits.done.insert(edits.key(for: id, decisions: decisions))
        let kept = keptIDs
        if let i = kept.firstIndex(of: id), i + 1 < kept.count { showEditPhoto(kept[i + 1]) } else { go(.save) }
        changed()
    }

    /// X: Out, and on to the next keeper. Edit's ⌘Z brings it back; Cull's history is reset (R-08).
    func editOut() {
        guard let id = editCur else { return }
        flushEdits()
        let kept = keptIDs, i = kept.firstIndex(of: id) ?? 0
        edits.recordDecision(.init(id: id, before: decisions.keep[id], after: false), photo: id)
        decisions.set(id, keep: false); decisions.resetHistory()
        editControls.autoUndo = nil
        let rest = kept.filter { $0 != id }
        showEditPhoto(rest.isEmpty ? nil : rest[min(i, rest.count - 1)])
        changed()
        say("Rejected \(shoot.photo(id)?.file ?? id). ⌘Z brings it back.")
    }

    /// ⌘Z: the last edit, or the last Out made here. Never a Cull decision (R-27).
    func editUndo() {
        flushEdits()
        guard let e = edits.undo() else { say("Nothing to undo"); return }
        let from = editCur
        if let d = e.decision {
            decisions.set(d.id, keep: d.before); decisions.resetHistory()
            showEditPhoto(e.photo)
        } else {
            retag(e.key)
            if keptIDs.contains(e.photo) { showEditPhoto(e.photo) }
        }
        // An undone crop changes what 1:1 is on a canvas that may be zoomed (R-46).
        refitZoom()
        editControls.autoUndo = nil
        changed()
        say(editCur != from && editCur != nil ? "Undone on \(shoot.photo(editCur)?.file ?? ""). Moved there so you can see it." : "Undone")
    }

    func editRedo() {
        flushEdits()
        guard let e = edits.redo() else { say("Nothing to redo"); return }
        let from = editCur
        if let d = e.decision {
            let kept = keptIDs, i = kept.firstIndex(of: d.id) ?? 0
            decisions.set(d.id, keep: d.after); decisions.resetHistory()
            if d.after != true, editCur == d.id || editCur == nil {
                let rest = kept.filter { $0 != d.id }
                showEditPhoto(rest.isEmpty ? nil : rest[min(i, rest.count - 1)])
            }
        } else {
            retag(e.key)
            if keptIDs.contains(e.photo) { showEditPhoto(e.photo) }
        }
        refitZoom()
        editControls.autoUndo = nil
        changed()
        say(editCur != from && editCur != nil ? "Redone on \(shoot.photo(editCur)?.file ?? "")." : "Redone")
    }

    /// A: exposure and white balance for this photo. Pressing A again undoes it.
    func auto() {
        guard let id = editCur, let p = shoot.photo(id) else { return }
        let c = editControls, k = edits.key(for: id, decisions: decisions), now = editLook
        if let a = c.autoUndo, a.key == k, a.applied == now {
            if commitLook(a.before, remember: false) { say("Auto undone") }
            return
        }
        guard commitLook(now.merging(AutoLook.make(for: p)) { _, new in new }, tag: EditTag.auto) else { return }
        c.autoUndo = .init(key: k, before: now, applied: editLook)
        say("Auto applied. Press A again to undo.")
    }

    /// =: the last edit made, on this photo (its own crop stays).
    func sameAsLast() {
        guard editCur != nil else { return }
        guard let last = editControls.lastLook else { say("Nothing to repeat yet. Edit a photo first."); return }
        if commitLook(last.merging(cropOnly(editLook)) { _, own in own }) { say("Same as last") }
    }

    /// W: the next click on the photo sets white balance (`pickWhite(at:)`). W again switches it off.
    func pickWhite() {
        guard editCur != nil else { return }
        edit.pickingWhite.toggle()
        say(edit.pickingWhite ? "Click something that should be neutral grey." : "Picker off")
    }

    /// ⌘C: this photo's settings, without its crop.
    func copySettings() {
        guard editCur != nil else { return }
        let c = settingsOnly(editLook)
        editControls.clipboard = c
        say("Copied \(c.count) \(c.count == 1 ? "setting" : "settings")")
    }

    /// ⌘V: the copied settings replace this photo's; its crop stays.
    func pasteSettings() {
        guard editCur != nil else { return }
        guard let clip = editControls.clipboard else { say("Copy an edit first"); return }
        if commitLook(clip.merging(cropOnly(editLook)) { _, own in own }) { say("Pasted") }
    }
}

/// The words the header shows next to the file name (`EditStore.tags` holds the last two).
public enum EditTag {
    public static let asShot = "As shot", auto = "Auto", matched = "Matched to scene", edited = "Edited"
}

extension AppModel {
    /// The look of the Edit photo, whatever step is on screen.
    var editLook: Look { editCur.map { edits.look($0, decisions: decisions) } ?? [:] }

    func settingsOnly(_ l: Look) -> Look { l.filter { !CropKey.all.contains($0.key) } }
    func cropOnly(_ l: Look) -> Look { l.filter { CropKey.all.contains($0.key) } }

    /// Every change the controls make to the Edit photo's look goes through here: stored without
    /// defaults, tagged, remembered for "=", written (a drag's writes are debounced).
    /// False when the photo can't be edited right now.
    @discardableResult
    func commitLook(_ new: Look, tag: String = EditTag.edited, coalesce: Bool = false, remember: Bool = true) -> Bool {
        guard let id = editCur else { return false }
        if edit.photo == .failed { say("This photo didn’t load. Retry first."); return false }
        let k = edits.key(for: id, decisions: decisions), clean = EditStore.clean(new)
        let c = editControls
        if c.autoUndo != nil { c.autoUndo = nil }
        let old = edits.looks[k] ?? [:]
        guard clean != old else { return true }
        edits.setLook(clean, on: id, decisions: decisions, coalesce: coalesce)
        // Reset all can take a crop away under a zoomed canvas: 1:1 and the pan limits move (R-43, R-46).
        if cropOnly(clean) != cropOnly(old) { refitZoom() }
        let t: String? = clean.isEmpty ? nil : tag
        if edits.tags[k] != t { edits.tags[k] = t }
        let settings = settingsOnly(clean)
        if remember, !settings.isEmpty { c.lastLook = settings }
        // The change should be seen: Before switches off.
        if edit.before, !edit.beforeHeld { edit.before = false }
        editChanged(coalesce: coalesce)
        return true
    }

    /// After undo or redo put a look back: "Auto" only describes the look Auto made.
    func retag(_ key: String) {
        let l = edits.looks[key] ?? [:]
        let t: String? = l.isEmpty ? nil : EditTag.edited
        if edits.tags[key] != t { edits.tags[key] = t }
    }

    /// `changed()` now, or within 250 ms while a drag is still moving the value.
    func editChanged(coalesce: Bool) {
        let c = editControls
        guard coalesce else { c.pendingWrite?.cancel(); c.pendingWrite = nil; c.dirty = false; changed(); return }
        c.dirty = true
        if c.pendingWrite == nil { c.pendingWrite = clock.after(0.25) { [weak self] in self?.writeEdits() } }
    }

    func writeEdits() {
        let c = editControls
        c.pendingWrite?.cancel(); c.pendingWrite = nil
        if c.dirty { c.dirty = false; changed() }
    }

    /// One nudge of `key`, and the toast that says where it landed.
    public func nudgeSetting(_ key: String, _ d: Int, coarse: Bool, coalesce: Bool = false) {
        guard let s = EditSetting.byKey[key] else { return }
        let n = coarse ? 5.0 : 1.0, v = value(key)
        setValue(key, s.log ? v * pow(1 + 0.02 * n, Double(d)) : v + s.step * n * Double(d), coalesce: coalesce)
        // A photo that didn't load isn't edited: `commitLook` said why, and that stays the message (R-44).
        guard edit.photo != .failed else { return }
        report(key)
    }

    /// "Exposure +0.15 EV", "Red saturation +12 · burst ×3".
    func report(_ key: String) {
        guard let id = editCur else { return }
        let n = edits.sharedBy(id, decisions: decisions)
        say("\(EditFormat.label(key)) \(EditFormat.value(key, value(key)))" + (n > 1 ? " · burst ×\(n)" : ""))
    }
}
