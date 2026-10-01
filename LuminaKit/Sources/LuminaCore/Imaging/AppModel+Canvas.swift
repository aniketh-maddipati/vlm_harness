import Foundation
import CoreGraphics

// WP-4. The Edit canvas: moving between photos, zoom, focus, Before, Crop (R-41…R-46).

public extension AppModel {
    /// Put `id` on the canvas (nil = no keepers left).
    func showEditPhoto(_ id: String?) {
        guard id != editCur else { return }
        editCur = id; edit.photo = .loading; edit.zoom = 1; edit.pan = .zero
        if edit.overlay == .variations { variationsClose() }
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

    /// Z: 1:1, again fits.
    func zoomToggle() { edit.zoom = edit.zoom > 1.001 ? 1 : EditLayout.clampZoom(edit.oneToOne, oneToOne: edit.oneToOne); edit.pan = .zero }
    func zoomStep(_ d: Int) { setZoom(edit.zoom * (d > 0 ? 1.25 : 0.8)) }
    func zoomFit() { edit.zoom = 1; edit.pan = .zero }
    func setZoom(_ z: Double) { edit.zoom = EditLayout.clampZoom(z, oneToOne: edit.oneToOne); if edit.zoom <= 1 { edit.pan = .zero } }

    func toggleFocus() { edit.focus.toggle() }

    /// \ held shows the original; a tap toggles it.
    func beforeHold(_ down: Bool) {
        if down { edit.beforeHeld = true; edit.before.toggle() } else { edit.beforeHeld = false }
    }

    func cropOpen() {
        guard editCur != nil, edit.overlay == nil else { return }
        edit.overlay = .crop; edit.cropDraft = currentLook.filter { CropKey.all.contains($0.key) }
    }
    func cropCancel() { edit.overlay = nil; edit.cropDraft = nil; edit.straightening = false; say("Crop cancelled") }
    func cropKeep() {
        guard let id = editCur, let draft = edit.cropDraft else { edit.overlay = nil; return }
        var l = currentLook.filter { !CropKey.all.contains($0.key) }
        l.merge(draft) { _, new in new }
        edits.setLook(l, on: id, decisions: decisions)
        edit.overlay = nil; edit.cropDraft = nil; edit.straightening = false; changed()
    }

    // WP-4: the crop tools.
    func straighten() {}
    func cropRotate(_ d: Int) {}
    func cropAngle(_ d: Double) {}
    func cropGrow(_ d: Int) {}
    func cropMove(dx: Int, dy: Int, coarse: Bool) {}
    func cropUndo() {}
    func cropRedo() {}
}
