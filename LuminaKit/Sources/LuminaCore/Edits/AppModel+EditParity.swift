import Foundation

// WP-5. The rest of the controls column, to the prototype (Lumina Edit v19): the histogram above
// the tools row and its clipping markers, the Curve section's graph (its points drag the three
// curve settings through the slider drag, so one drag is one undo step), the curve presets, and
// the footer's "Saving…" / "All changes saved". The views only call these.

/// One of the curve's three points, as the graph and the labels under it show it.
public struct CurveAnchor: Equatable, Sendable {
    public let key: String
    /// "Darks", "Mids", "Lights".
    public let label: String
    /// Where the point sits: x 0.25 / 0.5 / 0.75, y the curve there (0 bottom, 1 top).
    public let x: Double, y: Double
    public let value: Double
    /// "+12", "−3", "0".
    public let text: String
    /// The curve leaves the diagonal here (the value turns gold, a dashed line shows the move).
    public var changed: Bool { abs(y - x) > 0.004 }
}

public extension AppModel {
    // MARK: histogram

    /// The hint line's words for the two markers (prototype `loH`, `hiH`).
    static let shadowsClippingHint = "Shadows are clipping: detail is lost in the darkest areas."
    static let highlightsClippingHint = "Highlights are clipping: detail is lost in the brightest areas."

    /// The histogram sits above the tools row, except while cropping, in Curve (the graph has its
    /// own) and in windows under 860 × 620 (prototype `histOn`).
    var histogramShown: Bool {
        editCur != nil && edit.overlay != .crop && edit.section != .curve && windowSize.width >= 860 && windowSize.height >= 620
    }

    /// What the histogram draws: the one measured for this photo (the last look measured while a
    /// drag goes on), else the prototype's estimate from the look.
    var editHistogram: EditHistogram? {
        guard let id = editCur, let p = shoot.photo(id) else { return nil }
        if let h = editControls.histogram, h.photo == id { return h }
        return EditHistogram.estimate(editLook, brightness: AutoLook.brightness(p))
    }

    /// Changes when the histogram should be measured again: another photo, or another look at
    /// rest. Nothing is measured during a drag (rest renders only), so it holds still then.
    var histogramRequest: String {
        guard let id = editCur else { return "" }
        if edit.draggingKey != nil { return id + "|drag" }
        return id + "|" + editLook.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// Measure the Edit photo's histogram with its look, when the provider can. A result for a
    /// photo or look that is no longer on screen is dropped.
    func measureEditHistogram() async {
        guard let id = editCur, let p = shoot.photo(id), edit.draggingKey == nil,
              let provider = services.images as? any HistogramProviding else { return }
        let look = editLook
        if let h = editControls.histogram, h.photo == id, h.look == look { return }
        guard let bins = await provider.histogram(for: p, look: look.isEmpty ? nil : look), !Task.isCancelled else { return }
        guard editCur == id, editLook == look, var h = EditHistogram(bins: bins) else { return }
        h.photo = id; h.look = look
        editControls.histogram = h
    }

    /// The pointer is over something whose words go in the hint line (nil: it left).
    func setHintNote(_ text: String?) {
        if editControls.hintNote != text { editControls.hintNote = text }
    }

    /// The hint line: a marker's words, else the slider under the pointer's (none during a drag).
    var editHintText: String {
        guard edit.draggingKey == nil else { return "" }
        if let n = editControls.hintNote { return n }
        return edit.hoverKey.map(EditFormat.hint) ?? ""
    }

    // MARK: curve

    /// The three points with their labels and values.
    var curveAnchors: [CurveAnchor] {
        let look = editLook, f = ToneCurve.spline(ToneCurve.points(look))
        return ToneCurve.keys.indices.map { i -> CurveAnchor in
            let k = ToneCurve.keys[i], x = ToneCurve.xs[i], v = value(k)
            return CurveAnchor(key: k, label: ToneCurve.shortLabels[i], x: x, y: f(x), value: v, text: EditFormat.value(k, v))
        }
    }

    /// The curve the graph draws: `ToneCurve.samples + 1` outputs at even inputs, 0…1.
    var curveSamples: [Double] { ToneCurve.curve(editLook) }

    /// A point of the graph was pressed and has started to move: the slider drag of its setting.
    func curveDragBegan(_ key: String) {
        guard ToneCurve.keys.contains(key) else { return }
        sliderDragBegan(key)
    }

    /// The point moved by `dy`, a fraction of the graph's height, upwards positive. A point moves
    /// its setting by `dy × 200` (value / 200 is how far the point leaves the diagonal); ⇧ and ⌥
    /// slow it as on a slider, and it snaps to 0 as a slider snaps to its default.
    func curveDragMoved(by dy: Double, fine: Bool = false, finer: Bool = false) {
        guard let d = editControls.drag, ToneCurve.keys.contains(d.key), let s = EditSetting.byKey[d.key], dy.isFinite else { return }
        sliderDragMoved(by: dy * 200 / (s.max - s.min), fine: fine, finer: finer)
    }

    /// Pointer up (`cancel`: Esc puts the value back).
    func curveDragEnded(cancel: Bool = false) { sliderDragEnded(cancel: cancel) }

    /// "In 64 · Out 79" over the graph while one of its points is dragged (prototype `cvT`).
    var curveReadout: String? {
        guard let d = editControls.drag, let a = curveAnchors.first(where: { $0.key == d.key }) else { return nil }
        return "In \(Int((a.x * 255).rounded())) · Out \(Int((a.y * 255).rounded()))"
    }

    var curvePresetNames: [String] { ToneCurve.presets.map(\.name) }

    /// The chip that matches this photo's curve is lit.
    func curvePresetIsOn(_ name: String) -> Bool {
        guard editCur != nil, let p = ToneCurve.presets.first(where: { $0.name == name }) else { return false }
        return ToneCurve.keys.allSatisfy { value($0) == (p.look[$0] ?? 0) }
    }

    /// A preset's three values on this photo, one undo step.
    func applyCurvePreset(_ name: String) {
        guard editCur != nil, let p = ToneCurve.presets.first(where: { $0.name == name }) else { return }
        if editControls.drag != nil { endDrag(cancel: false, announce: false) }
        var l = editLook
        for k in ToneCurve.keys { l[k] = p.look[k] }
        if commitLook(l) { say("\(name) curve. ⌘Z undoes it.") }
    }

    // MARK: footer

    /// A write is still waiting or under way: the controls' debounce, or the store's (WP-8).
    var editWriteBusy: Bool {
        editControls.pendingWrite != nil || persistence.pending != nil || persistence.inFlight > 0
    }

    /// The footer's words (prototype `saveT`): what went wrong with storage, else "Saving…" while
    /// a change is being written and "All changes saved" after.
    var editSaveStatus: String {
        if edit.warning == Self.storageWarning { return "Couldn’t save. Keep this window open." }
        if edit.warning == Self.offlineWarning { return Self.offlineWarning }
        return editControls.saving ? "Saving…" : "All changes saved"
    }

    /// Something changed: "Saving…" for at least 0.7 s (prototype `markSaved`), and until the
    /// write has landed.
    func noteSaving() {
        let c = editControls
        if !c.saving { c.saving = true }
        c.savingClear?.cancel()
        c.savingClear = clock.after(0.7) { [weak self] in self?.settleSaving() }
    }
}

extension AppModel {
    func settleSaving() {
        let c = editControls
        c.savingClear = nil
        if editWriteBusy { c.savingClear = clock.after(0.25) { [weak self] in self?.settleSaving() }; return }
        if c.saving { c.saving = false }
    }
}
