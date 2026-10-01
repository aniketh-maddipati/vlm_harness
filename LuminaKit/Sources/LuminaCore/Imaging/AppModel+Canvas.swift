import Foundation
import CoreGraphics

// WP-4. The Edit canvas: moving between photos, zoom, focus, Before, Crop (R-41…R-46).

public extension AppModel {
    /// The canvas's own state (measured size, pointer, crop history).
    var canvas: CanvasState { feature(CanvasState.self) { CanvasState() } }
    /// The Edit photo's pictures (low-res, sharp) and their loading.
    var photoLoader: EditPhotoLoader { feature(EditPhotoLoader.self) { EditPhotoLoader() } }

    // MARK: moving

    /// Put `id` on the canvas (nil = no keepers left).
    func showEditPhoto(_ id: String?) {
        guard id != editCur else { return }
        // Leaving a photo mid-crop keeps the crop, as leaving a slider keeps its value.
        if edit.overlay == .crop { cropKeep() }
        editCur = id; edit.photo = .loading; edit.zoom = 1; edit.pan = .zero
        if !edit.beforeHeld { edit.before = false }
        canvas.stripScroll = 0
        if edit.overlay == .variations { variationsClose() }
        refreshOneToOne()
    }

    func editMove(_ d: Int) {
        let kept = keptIDs; guard !kept.isEmpty else { return }
        let i = kept.firstIndex(of: editCur ?? "") ?? 0, j = clamp(0, i + d, kept.count - 1)
        guard kept[j] != editCur else { return }
        let s = Perf.begin("PhotoSwitch"); showEditPhoto(kept[j]); Perf.end("PhotoSwitch", s)
        changed()
    }

    /// ↑ / ↓: the first keeper of the previous / next scene that has one.
    func editScene(_ d: Int) {
        guard let p = shoot.photo(editCur) else { return }
        let kept = keptIDs
        var s = p.scene + d
        while shoot.scenes.indices.contains(s) {
            if let first = kept.first(where: { shoot.photo($0)?.scene == s }) { showEditPhoto(first); changed(); return }
            s += d
        }
    }

    /// A filmstrip thumbnail was clicked.
    func editSelect(_ id: String) {
        guard keptIDs.contains(id), id != editCur else { return }
        let s = Perf.begin("PhotoSwitch"); showEditPhoto(id); Perf.end("PhotoSwitch", s)
        changed()
    }

    // MARK: geometry

    /// The canvas size: what the view measured, or (headless) what the window leaves for it.
    var canvasSize: CGSize {
        canvas.size ?? EditLayout.frames(window: windowSize, focus: edit.focus, controlsHidden: edit.controlsHidden, controlsCollapsed: edit.controlsCollapsed).canvas
    }

    /// The crop on screen: the draft while cropping, else the photo's kept crop.
    var editCrop: CropBox { CropBox(edit.overlay == .crop ? edit.cropDraft : currentLook) }

    /// The Edit photo's aspect ratio as shown: after its quarter turns and crop (R-41).
    var editAspect: Double? {
        guard let p = shoot.photo(editCur) else { return nil }
        return CropBox(currentLook).aspect(p.aspect)
    }

    /// The photo at Fit, in canvas coordinates.
    var editFitRect: CGRect? {
        guard let a = editAspect else { return nil }
        let c = canvasSize
        return EditLayout.photoRect(aspect: a, canvas: c, padding: EditLayout.padding(canvas: c))
    }

    /// The photo's pixel size after orientation: from the provider when it knows, else a 24 MP frame.
    func pixelSize(of p: Photo) -> CGSize {
        if let s = (services.images as? PixelSizing)?.pixelSize(for: p), s.width > 0, s.height > 0 { return s }
        let long = 6000.0
        return p.aspect >= 1 ? CGSize(width: long, height: long / p.aspect) : CGSize(width: long * p.aspect, height: long)
    }

    /// Set `edit.oneToOne` from the photo's real pixels (what the crop leaves of them) and the canvas.
    func refreshOneToOne() {
        guard let p = shoot.photo(editCur), let fit = editFitRect else { return }
        let box = CropBox(currentLook)
        var px = pixelSize(of: p)
        if box.turns % 2 == 1 { px = CGSize(width: px.height, height: px.width) }
        let k = CropBox.coverScale(angle: box.angle, aspect: box.frameAspect(p.aspect))
        px = CGSize(width: px.width * box.w / k, height: px.height * box.h / k)
        let o = EditLayout.oneToOne(pixels: px, fit: fit.size, backingScale: canvas.backingScale)
        if abs(o - edit.oneToOne) > 0.0005 { edit.oneToOne = o }
    }

    /// The view measured the canvas. A zoomed photo keeps its size on screen, the zoom stays in
    /// range and the photo stays in the canvas (R-43).
    func canvasResized(_ size: CGSize, backingScale: CGFloat) {
        let c = canvas, old = edit.oneToOne
        guard c.size != size || c.backingScale != backingScale else { refreshOneToOne(); return }
        c.size = size; c.backingScale = max(1, backingScale)
        refreshOneToOne()
        if abs(edit.zoom - 1) > 0.001, old > 0 {
            var z = EditLayout.clampZoom(edit.zoom * edit.oneToOne / old, oneToOne: edit.oneToOne)
            if abs(z - 1) < 0.02 { z = 1 }
            edit.zoom = z
        }
        clampPan()
    }

    private func clampPan() {
        guard let fit = editFitRect, abs(edit.zoom - 1) > 0.001 else { if edit.pan != .zero { edit.pan = .zero }; return }
        let c = canvasSize
        let p = EditLayout.clampPan(edit.pan, fit: fit.size, zoom: edit.zoom, canvas: c, padding: EditLayout.padding(canvas: c))
        if p != edit.pan { edit.pan = p }
    }

    // MARK: zoom

    /// Zoom to `z` (× Fit), keeping the photo under `anchor` (from the canvas centre) where it is.
    func zoom(to z: Double, anchor: CGPoint? = nil) {
        guard edit.overlay != .crop else { return }
        refreshOneToOne()
        let z0 = edit.zoom
        var z1 = EditLayout.clampZoom(z, oneToOne: edit.oneToOne)
        if abs(z1 - 1) < 0.02 { z1 = 1 }
        edit.zoom = z1
        edit.pan = z1 == 1 ? .zero : EditLayout.pan(edit.pan, anchor: anchor ?? .zero, from: z0, to: z1)
        clampPan()
    }

    /// Z (or a click on the photo): 1:1 at the pointer, again fits.
    func zoomToggle() { zoomToggle(at: canvas.pointer) }
    func zoomToggle(at anchor: CGPoint?) {
        guard editCur != nil, edit.overlay != .crop else { return }
        refreshOneToOne()
        if abs(edit.zoom - 1) > 0.001 { zoomFit(); say("Fit"); return }
        zoom(to: edit.oneToOne, anchor: anchor)
        say(abs(edit.zoom - 1) > 0.001 ? "1:1 · drag to look around · click or Z fits" : "This photo is already at 1:1")
    }
    func zoomStep(_ d: Int) {
        refreshOneToOne()
        zoom(to: EditLayout.zoomStop(from: edit.zoom, direction: d, oneToOne: edit.oneToOne), anchor: nil)
    }
    func zoomFit() { edit.zoom = 1; edit.pan = .zero }
    func setZoom(_ z: Double) { zoom(to: z, anchor: nil) }

    /// Drag on a zoomed photo.
    func panBy(_ d: CGSize) {
        guard abs(edit.zoom - 1) > 0.001 else { return }
        edit.pan = CGSize(width: edit.pan.width + d.width, height: edit.pan.height + d.height)
        clampPan()
    }

    func toggleFocus() { edit.focus.toggle() }

    /// \ held shows the original; a tap toggles it.
    func beforeHold(_ down: Bool) {
        if down { edit.beforeHeld = true; edit.before.toggle() } else { edit.beforeHeld = false }
    }

    /// A force click on the photo: Before while it is held.
    func beforePress(_ down: Bool) {
        guard editCur != nil, edit.overlay == nil, edit.before != down else { return }
        edit.before = down; edit.beforeHeld = down
    }

    // MARK: crop

    func cropOpen() {
        guard editCur != nil, edit.overlay == nil, let p = current else { return }
        let box = CropBox(currentLook)
        edit.overlay = .crop; edit.cropDraft = box.draft
        edit.zoom = 1; edit.pan = .zero; edit.before = false; edit.beforeHeld = false; edit.straightening = false
        edit.cropRatio = box.ratioName(aspect: p.aspect)
        let c = canvas; c.cropUndo = []; c.cropRedo = []; c.cropSwapped = false; c.lastCropKind = ""
        say("Drag a corner to crop. R turns it, ← → straighten. ⏎ keeps it, esc cancels.")
    }

    func cropCancel() {
        edit.overlay = nil; edit.cropDraft = nil; edit.straightening = false
        let c = canvas; c.cropUndo = []; c.cropRedo = []
        say("Crop cancelled")
    }

    func cropKeep() {
        defer { let c = canvas; c.cropUndo = []; c.cropRedo = [] }
        guard let id = editCur, let draft = edit.cropDraft else { edit.overlay = nil; edit.cropDraft = nil; edit.straightening = false; return }
        let before = currentLook
        var l = before.withoutCrop
        l.merge(CropBox(draft).keys) { _, new in new }
        edit.overlay = nil; edit.cropDraft = nil; edit.straightening = false
        guard l != before else { return }
        edits.setLook(l, on: id, decisions: decisions)
        edits.tags[edits.key(for: id, decisions: decisions)] = l.isEmpty ? nil : "Edited"
        refreshOneToOne()
        say(l.cropOnly.isEmpty ? "Crop removed. ⌘Z undoes it." : "Crop kept. ⌘Z undoes it.")
        changed()
    }

    /// One step of the crop's own history. Steps of the same `kind` within half a second are one.
    private func cropStep(_ kind: String, _ body: (inout CropBox, Double) -> Void) {
        guard edit.overlay == .crop, let draft = edit.cropDraft, let p = current else { return }
        let c = canvas, now = clock.now
        var box = CropBox(draft)
        let before = CanvasState.CropStep(draft: draft, ratio: edit.cropRatio, swapped: c.cropSwapped)
        body(&box, p.aspect)
        guard box.draft != draft || edit.cropRatio != before.ratio || c.cropSwapped != before.swapped else { return }
        if !(kind == c.lastCropKind && !kind.isEmpty && now.timeIntervalSince(c.lastCropAt) < 0.5 && !c.cropUndo.isEmpty) {
            c.cropUndo.append(before); if c.cropUndo.count > 60 { c.cropUndo.removeFirst() }
        }
        c.cropRedo = []; c.lastCropKind = kind; c.lastCropAt = now
        edit.cropDraft = box.draft
    }

    /// S: straighten by drawing along a horizon. Outside Crop it opens Crop first.
    func straighten() {
        if edit.overlay == nil { cropOpen() }
        guard edit.overlay == .crop else { return }
        edit.straightening.toggle()
        say(edit.straightening ? "Straighten · draw along a line that should be level or upright · esc cancels" : "Straighten off")
    }

    /// The line drawn in Straighten mode (screen direction, y down): the picture turns so the line
    /// becomes level or upright, whichever is nearer.
    func straightenAlong(dx: Double, dy: Double) {
        guard edit.overlay == .crop, hypot(dx, dy) > 8 else { edit.straightening = false; return }
        var a = atan2(dy, dx) * 180 / .pi
        a = a - 90 * (a / 90).rounded()
        cropStep("") { box, _ in box.angle = clamp(-45, ((box.angle - a) * 10).rounded() / 10, 45) }
        edit.straightening = false
        say(String(format: "Straightened %+.1f°", CropBox(edit.cropDraft).angle))
    }

    /// R / ⇧R in Crop: a quarter turn right / left.
    func cropRotate(_ d: Int) {
        cropStep("") { box, _ in box.turn(d) }
        say(d > 0 ? "Turned right" : "Turned left")
    }

    /// ← → in Crop: the straighten angle, in 0.1° steps, −45…45°.
    func cropAngle(_ d: Double) {
        cropStep("angle") { box, _ in box.angle = clamp(-45, ((box.angle + d) * 10).rounded() / 10, 45) }
    }

    /// Set the straighten angle (the angle control's drag).
    func setCropAngle(_ a: Double) {
        cropStep("angle") { box, _ in box.angle = clamp(-45, (a * 10).rounded() / 10, 45) }
    }

    /// ↑ ↓ in Crop: grow / shrink the box about its centre, proportions kept.
    func cropGrow(_ d: Int) {
        cropStep("grow") { box, _ in box.scale(by: d > 0 ? 1.05 : 1 / 1.05) }
    }

    /// ⌥ + arrows in Crop: move the box (1 % of the frame; ⇧ 5 %).
    func cropMove(dx: Int, dy: Int, coarse: Bool) {
        let step = coarse ? 0.05 : 0.01
        cropStep("move") { box, _ in box.x += Double(dx) * step; box.y += Double(dy) * step; box.clampIntoFrame() }
    }

    /// The ratio menu: Original, 1:1, 4:5, 3:2, 16:9, Free.
    func setCropRatio(_ name: String) {
        guard CropBox.ratios.contains(name) else { return }
        let c = canvas
        cropStep("") { box, a in
            edit.cropRatio = name
            if name == "Original" { c.cropSwapped = false; box.x = 0; box.y = 0; box.w = 1; box.h = 1; return }
            let fa = box.frameAspect(a)
            if let r = CropBox.target(name, frameAspect: fa, swapped: c.cropSwapped) { box.reshape(to: r, frameAspect: fa) }
        }
    }

    /// Portrait ↔ landscape for the chosen ratio.
    func cropSwapRatio() {
        guard edit.overlay == .crop else { return }
        guard ["4:5", "3:2", "16:9"].contains(edit.cropRatio) else { say("Pick a ratio like 4:5 or 16:9 first."); return }
        let c = canvas, name = edit.cropRatio
        cropStep("") { box, a in
            c.cropSwapped.toggle()
            let fa = box.frameAspect(a)
            if let r = CropBox.target(name, frameAspect: fa, swapped: c.cropSwapped) { box.reshape(to: r, frameAspect: fa) }
        }
    }

    /// The box was dragged (a corner or the whole box). `first` starts a new undo step.
    func setCropRect(x: Double, y: Double, w: Double, h: Double, first: Bool) {
        if first { canvas.lastCropKind = "" }
        cropStep("drag") { box, _ in box.w = w; box.h = h; box.x = x; box.y = y; box.clampIntoFrame() }
    }

    /// The width / height the box is held to while it is dragged; nil when Free.
    var cropLockedRatio: Double? {
        guard let p = current else { return nil }
        return CropBox.target(edit.cropRatio, frameAspect: CropBox(edit.cropDraft).frameAspect(p.aspect), swapped: canvas.cropSwapped)
    }

    func cropUndo() {
        guard edit.overlay == .crop, let draft = edit.cropDraft else { return }
        let c = canvas
        guard let last = c.cropUndo.popLast() else { say("Nothing to undo in this crop"); return }
        c.cropRedo.append(.init(draft: draft, ratio: edit.cropRatio, swapped: c.cropSwapped))
        edit.cropDraft = last.draft; edit.cropRatio = last.ratio; c.cropSwapped = last.swapped; c.lastCropKind = ""
        say("Crop step undone")
    }

    func cropRedo() {
        guard edit.overlay == .crop, let draft = edit.cropDraft else { return }
        let c = canvas
        guard let next = c.cropRedo.popLast() else { say("Nothing to redo in this crop"); return }
        c.cropUndo.append(.init(draft: draft, ratio: edit.cropRatio, swapped: c.cropSwapped))
        edit.cropDraft = next.draft; edit.cropRatio = next.ratio; c.cropSwapped = next.swapped; c.lastCropKind = ""
        say("Crop step redone")
    }
}
