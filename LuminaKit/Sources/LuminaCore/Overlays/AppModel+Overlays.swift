import Foundation

// WP-6. Variations, Help, the intro, the scene grid, the toast's lifetime and Esc unwinding
// (R-06, R-20…R-26). The grid's cells are `Variations.spec`; the words are `OverlayCopy`.

public extension AppModel {
    // MARK: Variations

    /// V down opens the grid on the setting under the pointer (or the section's main one).
    /// V up after a hold applies the highlighted cell; after a tap (under 280 ms) the grid
    /// stays open and nothing applies. Nothing happens if the grid closed in between (R-06, R-24).
    func variationsHold(_ down: Bool) {
        let o = overlays
        if down {
            guard step == .edit, edit.overlay == nil, variationsOpen() else { return }
            o.vDownAt = clock.now; o.held = true
        } else {
            guard let t0 = o.vDownAt else { return }
            o.vDownAt = nil; o.held = false
            guard variationsLive else { return }
            if clock.now.timeIntervalSince(t0) > Variations.tapThreshold { variationsApply() }
            else { edit.variationSticky = true; say(OverlayCopy.variationsTap) }
        }
    }

    /// The Variations tool button: opens the grid to stay (as a tap of V does), or closes it.
    func variationsToggle() {
        if edit.overlay == .variations { variationsClose(); return }
        guard step == .edit, edit.overlay == nil, variationsOpen() else { return }
        edit.variationSticky = true
    }

    /// ← → ↑ ↓. Ignored once a cell has been chosen and is waiting out its window.
    func variationsMove(dx: Int, dy: Int) {
        guard variationsLive, !overlays.applying, let spec = overlays.spec else { return }
        edit.variationIndex = spec.moved(from: edit.variationIndex, dx: dx, dy: dy)
    }

    /// The pointer is over a cell.
    func variationsSelect(_ index: Int) {
        guard variationsLive, !overlays.applying, let spec = overlays.spec, spec.cells.indices.contains(index) else { return }
        if edit.variationIndex != index { edit.variationIndex = index }
    }

    /// A cell was clicked: choose it and apply.
    func variationsPick(_ index: Int) {
        variationsSelect(index)
        if edit.variationIndex == index { variationsApply() }
    }

    /// Apply the highlighted cell (V released, ⏎, a click). It lands when the 120 ms window
    /// ends, and only if the grid is still open on the same photo: it can never reach a photo
    /// that came on screen in the meantime (R-06).
    func variationsApply() {
        let o = overlays
        guard variationsLive, !o.applying else { return }
        o.applying = true; o.held = false; o.vDownAt = nil
        let generation = o.generation, photo = editCur
        o.pendingApply = clock.after(Variations.applyWindow) { [weak self] in self?.variationsCommit(generation, photo) }
    }

    /// Esc, a fresh V, Cancel, and a photo change (WP-4 calls this from `showEditPhoto`):
    /// the grid goes and nothing changes.
    func variationsClose() {
        let byHand = step == .edit && edit.overlay == .variations && edit.variationPhoto != nil && edit.variationPhoto == editCur
        variationsDismiss()
        if byHand { say(OverlayCopy.variationsClosed) }
    }

    /// The photo or the step changed under the overlays (the overlay view calls this, so the
    /// grid closes even if the photo was switched without `showEditPhoto`).
    func overlaysSync() {
        if edit.overlay == .variations || overlays.spec != nil { _ = variationsLive }
    }

    private func variationsOpen() -> Bool {
        guard let id = editCur else { return false }
        if edit.photo == .failed { say(OverlayCopy.variationsNoPhoto); return false }
        // White balance is the target when the pointer is on Tint, or the white picker is on
        // and the pointer is on no setting. Temperature alone is cooler / now / warmer.
        let hover = edit.hoverKey, look = currentLook
        let whiteBalance = hover == "tint" || (hover == nil && (edit.pickingWhite || edit.overlay == .picker))
        guard let spec = Variations.spec(key: hover ?? EditSetting.main(edit.section), whiteBalance: whiteBalance, look: look)
                ?? Variations.spec(key: EditSetting.main(edit.section), look: look) else { return false }
        let o = overlays
        o.pendingApply?.cancel(); o.pendingApply = nil; o.applying = false; o.held = false; o.vDownAt = nil
        o.generation &+= 1; o.spec = spec
        // The grid shows the edit, so a peek at the original and the pointer tools end here.
        edit.before = false; edit.beforeHeld = false; edit.pickingWhite = false; edit.straightening = false
        edit.overlay = .variations
        edit.variationKey = spec.key; edit.variationIndex = spec.initial
        edit.variationSticky = false; edit.variationPhoto = id
        return true
    }

    /// The grid is open on the photo on screen. Anything else closes it.
    private var variationsLive: Bool {
        if step == .edit, edit.overlay == .variations, overlays.spec != nil, let p = edit.variationPhoto, p == editCur { return true }
        variationsDismiss(); return false
    }

    /// Close without a word.
    private func variationsDismiss() {
        let o = overlays
        o.pendingApply?.cancel(); o.pendingApply = nil
        o.applying = false; o.held = false; o.vDownAt = nil
        if o.spec != nil { o.spec = nil }
        if edit.overlay == .variations { edit.overlay = nil }
        edit.variationKey = nil; edit.variationPhoto = nil; edit.variationSticky = false; edit.variationIndex = 0
    }

    private func variationsCommit(_ generation: Int, _ photo: String?) {
        let o = overlays
        guard o.generation == generation, o.applying else { return }
        o.pendingApply = nil
        guard variationsLive, let spec = o.spec, let photo, editCur == photo, edit.variationPhoto == photo,
              spec.cells.indices.contains(edit.variationIndex) else { variationsDismiss(); return }
        let cell = spec.cells[edit.variationIndex]
        variationsDismiss()
        // One undo step: the first changed setting opens it, the rest fold into it.
        let look = currentLook
        var n = 0
        for key in cell.values.keys.sorted() {
            guard let v = cell.values[key], v != look[key] ?? EditSetting.byKey[key]?.def ?? 0 else { continue }
            setValue(key, v, coalesce: n > 0); n += 1
        }
        guard !cell.isNow, n > 0 else { say(OverlayCopy.variationsKept); return }
        switch spec.kind {
        case .grid: say("Temperature \(Variations.format("wb", value("wb"))) · tint \(Variations.signed(value("tint")))")
        case .three, .two: say("\(Variations.name(spec.key)) \(cell.label) · ⌘Z undoes")
        }
    }

    // MARK: Help

    func helpOpen() {
        guard step == .edit, edit.overlay == nil else { return }
        // Help takes the keyboard, so a held \ would never see its release.
        if edit.beforeHeld { edit.beforeHeld = false; edit.before = false }
        edit.overlay = .help
    }
    func helpClose() { if edit.overlay == .help { edit.overlay = nil } }

    // MARK: First-run intro

    /// Edit came on screen (the overlay view calls this; `enterEdit` belongs to WP-5): show the
    /// intro the first time there is a photo to edit, once per window, unless `LUMINA_INTRO=skip`.
    func introOpenIfFirstRun() {
        let o = overlays
        guard step == .edit, !config.skipIntro, !o.introOffered, edit.overlay == nil, editCur != nil else { return }
        o.introOffered = true
        guard o.introForced || !o.intro.seen else { return }
        edit.overlay = .intro
    }
    /// "Show the intro again" (in Help).
    func introShow() {
        guard step == .edit, edit.overlay == nil || edit.overlay == .help else { return }
        overlays.introOffered = true; edit.overlay = .intro
    }
    /// Esc, ⏎ or "Start editing": closed and remembered (`lumina.edit.intro.v1`).
    func introClose() {
        guard edit.overlay == .intro else { return }
        edit.overlay = nil; overlays.intro.seen = true
    }
    /// "All shortcuts" on the intro.
    func introToHelp() { introClose(); helpOpen() }

    // MARK: Scene grid

    /// The kept photos of the current photo's scene (one per shared edit), at most 30 around it.
    var sceneGrid: (title: String, subtitle: String, ids: [String])? {
        guard let p = shoot.photo(editCur), shoot.scenes.indices.contains(p.scene) else { return nil }
        var seen = Set<String>(), all: [String] = []
        let mine = edits.key(for: p.id, decisions: decisions)
        for id in keptIDs where shoot.photo(id)?.scene == p.scene {
            let k = edits.key(for: id, decisions: decisions)
            if seen.insert(k).inserted { all.append(k == mine ? p.id : id) }
        }
        let limit = 30, i = all.firstIndex(of: p.id) ?? 0
        let from = max(0, min(all.count - limit, i - limit / 2)), ids = Array(all[from..<min(all.count, from + limit)])
        let hm = shoot.scenes[p.scene].header
        return ("Scene \(hm) · \(all.count) \(all.count == 1 ? "photo" : "photos")",
                (all.count > limit ? "\(ids.count) shown · " : "") + OverlayCopy.sceneGridHint, ids)
    }
    func sceneGridOpen() {
        guard step == .edit, editCur != nil, edit.overlay == nil else { return }
        edit.before = false; edit.beforeHeld = false; edit.pickingWhite = false
        edit.overlay = .sceneGrid
    }
    func sceneGridClose() { if edit.overlay == .sceneGrid { edit.overlay = nil } }
    /// A photo in the scene grid was clicked: open it.
    func sceneGridPick(_ id: String) {
        guard edit.overlay == .sceneGrid, keptIDs.contains(id) else { return }
        edit.overlay = nil
        if id != editCur { showEditPhoto(id); changed() }
    }

    // MARK: Picker

    /// The white picker's chip was clicked (Esc does the same through `editEscape`).
    func pickerCancel() {
        guard edit.pickingWhite || edit.overlay == .picker else { return }
        edit.pickingWhite = false
        if edit.overlay == .picker { edit.overlay = nil }
        say(OverlayCopy.pickerOff)
    }

    // MARK: Esc

    /// Esc backs out one layer at a time, in KEYMAP's order: focus → zoom → before → scene grid
    /// → picker (R-25). So that three presses always reach normal, a press never leaves more
    /// than two layers open: with four or more up at once, the innermost tools go with it.
    func editEscape() {
        var open = escapeLayers
        guard !open.isEmpty else { return }
        escapeClose(open.removeFirst(), quiet: false)
        while open.count > 2 { escapeClose(open.removeLast(), quiet: true) }
    }

    /// How many Esc presses the current state needs to be back to normal (0…3).
    var escapeDepth: Int { min(3, escapeLayers.count) }

    private var escapeLayers: [EscapeLayer] {
        var l: [EscapeLayer] = []
        if edit.focus || edit.controlsHidden { l.append(.focus) }
        if abs(edit.zoom - 1) > 0.001 { l.append(.zoom) }
        if edit.before { l.append(.before) }
        if edit.overlay == .sceneGrid { l.append(.sceneGrid) }
        if edit.overlay == .picker || edit.pickingWhite { l.append(.picker) }
        if edit.straightening, edit.overlay != .crop { l.append(.straighten) }
        return l
    }

    private func escapeClose(_ layer: EscapeLayer, quiet: Bool) {
        switch layer {
        case .focus: edit.focus = false; edit.controlsHidden = false
        case .zoom: zoomFit()
        case .before: edit.before = false; edit.beforeHeld = false
        case .sceneGrid: edit.overlay = nil
        case .picker:
            edit.pickingWhite = false
            if edit.overlay == .picker { edit.overlay = nil }
            if !quiet { say(OverlayCopy.pickerOff) }
        case .straighten:
            edit.straightening = false
            if !quiet { say(OverlayCopy.straightenCancelled) }
        }
    }

    // MARK: Toast

    /// A toast went up (the overlay view calls this): it comes down 3.5 s after it was said,
    /// unless a newer one has replaced it. Edit only; Cull keeps its message line.
    func toastScheduleExpiry() {
        let o = overlays
        o.toastTimer?.cancel(); o.toastTimer = nil
        guard let t = toast else { return }
        let rest = clamp(0, OverlayCopy.toastSeconds - clock.now.timeIntervalSince(t.at), OverlayCopy.toastSeconds)
        o.toastTimer = clock.after(rest) { [weak self] in
            guard let self, self.step == .edit, self.toast == t else { return }
            self.toast = nil
        }
    }

    // MARK: Window

    /// The window lost focus: Variations closes with nothing applied, held keys are forgotten (R-24).
    func windowBlurred() {
        variationsDismiss(); edit.beforeHeld = false; heldKeys.removeAll()
    }

    func releaseAllKeys() {
        for k in heldKeys { handle(KeyEvent(k, phase: .up)) }
        heldKeys.removeAll()
    }
}

private enum EscapeLayer { case focus, zoom, before, sceneGrid, picker, straighten }
