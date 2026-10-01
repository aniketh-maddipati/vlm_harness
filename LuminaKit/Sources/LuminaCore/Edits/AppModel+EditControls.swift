import Foundation
import CoreGraphics

// WP-5. What the pointer does in the controls column: sections, slider drags (one undo step, ⇧ and
// ⌥ slow them, snap to the default, Esc cancels), typed values (R-22), two-finger swipes, the white
// picker's click, and the words the header and the bottom bar show. The views only call these.

public extension AppModel {
    // MARK: sections

    /// The sliders on screen: the open section, and in Colour the eight colours of the open axis.
    var visibleSettings: [EditSetting] {
        EditSetting.of(edit.section).filter { edit.section != .colour || $0.key.hasPrefix(edit.colourAxis + "_") }
    }

    /// The setting [ ] chose, if it is on screen; else the first one that is.
    var activeSettingKey: String {
        let keys = visibleSettings.map(\.key)
        if keys.contains(edit.activeKey) { return edit.activeKey }
        if edit.section == .colour, let c = EditFormat.colour(of: edit.activeKey), keys.contains("\(edit.colourAxis)_\(c)") { return "\(edit.colourAxis)_\(c)" }
        return keys.first ?? edit.activeKey
    }

    func setSection(_ s: EditSection) {
        guard edit.section != s else { return }
        edit.section = s; edit.hoverKey = nil
        editControls.keyboardChoosing = false
        if let first = visibleSettings.first { edit.activeKey = first.key }
    }

    /// Colour's sub-tab: "hue", "sat" or "lum". The chosen colour stays chosen.
    func setColourAxis(_ axis: String) {
        guard EditSetting.colourAxes.contains(axis), edit.colourAxis != axis else { return }
        let colour = EditFormat.colour(of: edit.activeKey)
        edit.colourAxis = axis; edit.hoverKey = nil
        if edit.section == .colour { edit.activeKey = colour.map { "\(axis)_\($0)" } ?? visibleSettings.first?.key ?? edit.activeKey }
    }

    /// How many settings of a section differ from their defaults on this photo (the tab's dot).
    func changedCount(_ section: EditSection) -> Int {
        editLook.keys.reduce(0) { $0 + (EditSetting.byKey[$1]?.section == section ? 1 : 0) }
    }

    /// "Reset light": every setting of the open section back to its default, one undo step.
    func resetSection() {
        guard editCur != nil else { return }
        let s = edit.section
        if commitLook(editLook.filter { EditSetting.byKey[$0.key]?.section != s }) { say("\(s.rawValue.prefix(1).uppercased() + s.rawValue.dropFirst()) reset") }
    }

    // MARK: header and bottom bar

    /// "DSC03261", or "DSC03261 · burst ×3" when kept burst frames share the edit.
    var editTitle: String {
        guard let id = editCur, let p = shoot.photo(id) else { return "–" }
        let n = edits.sharedBy(id, decisions: decisions)
        return n > 1 ? "\(p.file) · burst ×\(n)" : p.file
    }

    /// "As shot", "Auto", "Matched to scene" or "Edited".
    var editTag: String {
        guard let id = editCur else { return "" }
        if editLook.isEmpty { return EditTag.asShot }
        let t = edits.tags[edits.key(for: id, decisions: decisions)]
        return t == EditTag.auto || t == EditTag.matched ? t! : EditTag.edited
    }

    var editIsFirst: Bool { editCur == nil || keptIDs.first == editCur }
    var editIsLast: Bool { editCur == nil || keptIDs.last == editCur }
    /// A again undoes Auto (the Auto button reads "Undo Auto").
    var autoCanUndo: Bool {
        guard let id = editCur, let a = editControls.autoUndo else { return false }
        return a.key == edits.key(for: id, decisions: decisions) && a.applied == editLook
    }

    /// The Next button. Unlike ⏎ it stays in Edit on the last photo and says where to go.
    func editNext() {
        if editIsLast { say("Last photo · Save when you’re ready (⌘S)") } else { editEnter() }
    }

    // MARK: dragging a slider

    /// Pointer down has become a drag on `key`'s row.
    func sliderDragBegan(_ key: String) {
        guard let id = editCur, let s = EditSetting.byKey[key] else { return }
        let c = editControls
        if c.drag != nil { endDrag(cancel: false, announce: false) }
        if edit.typingKey != nil { cancelTyping() }
        let v = value(key)
        c.drag = .init(key: key, photo: id, start: v, position: SliderScale.position(s, v), snapped: false, lastBefore: c.lastLook)
        c.keyboardChoosing = false; c.swipe = nil
        edit.draggingKey = key; edit.activeKey = key
        edits.beginCoalescing()
    }

    /// The pointer moved by `delta`, a fraction of the track's width, since the last call.
    /// ⇧ (`fine`) moves the thumb at a quarter of that, ⌥ (`finer`) at a tenth.
    func sliderDragMoved(by delta: Double, fine: Bool = false, finer: Bool = false) {
        let c = editControls
        guard var d = c.drag, let s = EditSetting.byKey[d.key], delta.isFinite else { return }
        guard d.photo == editCur else { endDrag(cancel: false, announce: false); return }
        d.position = min(1, max(0, d.position + delta * (finer ? 0.1 : fine ? 0.25 : 1)))
        d.snapped = abs(d.position - SliderScale.position(s, s.def)) < SliderScale.snapWithin
        c.drag = d
        setValue(d.key, d.snapped ? s.def : SliderScale.value(s, at: d.position), coalesce: true)
    }

    /// Pointer up. `cancel` (Esc) puts the value back where the drag found it, with no undo step.
    func sliderDragEnded(cancel: Bool = false) { endDrag(cancel: cancel, announce: true) }

    /// Esc while dragging: the drag is cancelled. False when nothing was being dragged.
    @discardableResult func cancelSliderDrag() -> Bool {
        guard editControls.drag != nil else { return false }
        endDrag(cancel: true, announce: true); return true
    }

    /// Double-click on a row.
    func resetSetting(_ key: String) {
        guard editCur != nil, EditSetting.byKey[key] != nil else { return }
        setValue(key, nil); say("\(EditFormat.label(key)) reset")
    }

    // MARK: two-finger swipe

    /// A horizontal two-finger swipe over `key`'s row moved by `dx` points (positive = towards
    /// the right end of the track). Every 16pt is one step; one swipe is one undo step.
    func sliderSwipe(_ key: String, by dx: Double) {
        let c = editControls
        guard editCur != nil, EditSetting.byKey[key] != nil, edit.typingKey == nil, c.drag == nil, dx.isFinite else { return }
        let now = clock.now
        var w = c.swipe ?? (key, 0, now, true)
        if w.key != key || now.timeIntervalSince(w.at) > 0.4 { w = (key, 0, now, true) }
        if w.first { edits.beginCoalescing(); w.first = false }
        w.at = now; w.sum += dx
        if abs(w.sum) >= 16 {
            let steps = Int(abs(w.sum) / 16)
            nudgeSetting(key, (w.sum > 0 ? 1 : -1) * steps, coarse: false, coalesce: true)
            w.sum -= Double(steps) * 16 * (w.sum > 0 ? 1 : -1)
        }
        c.swipe = w
    }

    // MARK: typing a value

    /// The number was clicked: shortcuts stop (R-22) and the field starts with this text.
    @discardableResult func beginTyping(_ key: String) -> String {
        guard editCur != nil, EditSetting.byKey[key] != nil else { return "" }
        if editControls.drag != nil { endDrag(cancel: false, announce: false) }
        edit.typingKey = key; edit.activeKey = key
        return EditFormat.editable(key, value(key))
    }

    /// ⏎ or the field lost the keyboard. Out of range clamps; junk changes nothing.
    func commitTyping(_ text: String) {
        guard let key = edit.typingKey else { return }
        edit.typingKey = nil
        guard let s = EditSetting.byKey[key], editCur != nil else { return }
        guard let n = EditFormat.parse(text) else { say("Type a number, like \(EditFormat.value(key, value(key)))."); return }
        setValue(key, n)
        if n > s.max || n < s.min { say("\(EditFormat.label(key)): \(n > s.max ? "max" : "min") \(EditFormat.value(key, value(key))). Set to the limit.") }
        else { report(key) }
    }

    /// Esc in the field: nothing changes.
    func cancelTyping() { edit.typingKey = nil }

    // MARK: white picker

    /// The canvas (WP-4) calls this when the photo is clicked while `edit.pickingWhite` is on.
    /// `point` is the click as fractions of the photo: (0, 0) top-left, (1, 1) bottom-right.
    /// Sets the temperature, clears the tint, and switches the picker off.
    func pickWhite(at point: CGPoint) {
        guard edit.pickingWhite, let id = editCur, let p = shoot.photo(id), let s = EditSetting.byKey["wb"] else { return }
        edit.pickingWhite = false
        // Stand-in until the backend samples the pixel (CONTRACT-REQUESTS/WP5.md): Auto's white
        // balance, a touch warmer towards the top of the frame, as the design prototype does.
        let y = min(1, max(0, point.y.isFinite ? Double(point.y) : 0.5))
        let base = AutoLook.make(for: p)["wb"] ?? s.def
        var l = editLook
        let wb = SliderScale.round(s, base * (1 + (0.5 - y) * 0.06))
        l["wb"] = wb; l["tint"] = nil
        if commitLook(l) { say("White set · \(EditFormat.value("wb", wb))") }
    }
}

extension AppModel {
    func endDrag(cancel: Bool, announce: Bool) {
        let c = editControls
        guard let d = c.drag else { return }
        let moved = value(d.key) != d.start
        if cancel, d.photo == editCur { setValue(d.key, d.start, coalesce: true); c.lastLook = d.lastBefore }
        c.drag = nil; edit.draggingKey = nil
        edits.endCoalescing()
        writeEdits()
        guard announce, d.photo == editCur else { return }
        if cancel { say("\(EditFormat.label(d.key)) unchanged") } else if moved { report(d.key) }
    }
}
