import Foundation

// WP-3. Cull keys (KEYMAP "Cull", R-04, R-05, R-08, R-28; behaviour pinned by the parity traces).

public extension AppModel {
    private func visibleIndex(_ id: String?) -> Int? { shoot.position(id).flatMap { $0 < visiblePhotos.count ? $0 : nil } }

    /// R / X: decide the current photo, then move to the next.
    func cullMark(keep: Bool) {
        guard let id = cullCur, let i = visibleIndex(id) else { return }
        decisions.mark(id, keep: keep, cur: id)
        if i + 1 < visiblePhotos.count { cullCur = shoot.photos[i + 1].id }
        changed()
    }

    func cullMove(_ d: Int) {
        guard let i = visibleIndex(cullCur) else { cullCur = visiblePhotos.first?.id; return }
        let j = clamp(0, i + d, visiblePhotos.count - 1)
        guard j != i else { return }
        cullCur = shoot.photos[j].id; changed()
    }

    /// ↑ / ↓: the first photo of the previous / next scene.
    func cullScene(_ d: Int) {
        guard let p = shoot.photo(cullCur) else { return }
        let s = p.scene + d
        guard shoot.scenes.indices.contains(s), let first = shoot.scenes[s].ids.first, visibleIndex(first) != nil else { return }
        cullCur = first; changed()
    }

    /// U: the next undecided photo, wrapping around.
    func cullNextUndecided() {
        let n = visiblePhotos.count; guard n > 0 else { return }
        let i = visibleIndex(cullCur) ?? -1
        for k in 1...n { let p = shoot.photos[(i + k) % n]; if decisions.keep[p.id] == nil { cullCur = p.id; changed(); return } }
    }

    /// ⌘Z: undo the last decision and go back to the photo it was made on.
    func cullUndo() { if let c = decisions.undo() { if let cur = c.cur { cullCur = cur }; changed() } }
    func cullRedo() { if let c = decisions.redo() { if let cur = c.cur { cullCur = cur }; changed() } }

    /// ⌘+ / ⌘−: tile height ×1.25 per step, 64…320, remembered.
    func cullTileSize(_ d: Int) {
        let base = cull.tileHeightOverride ?? Double(CullLayout.tileHeight(gridHeight: windowSize.height))
        cull.tileHeightOverride = clamp(64, base * (d > 0 ? 1.25 : 0.8), 320)
    }

    /// "Keep n suggested": the scene's undecided, suggested photos, as one undo step.
    func keepSuggested(scene: Int) {
        guard shoot.scenes.indices.contains(scene) else { return }
        let ids = shoot.scenes[scene].ids.filter { decisions.keep[$0] == nil && shoot.photo($0)?.suggested == true && visibleIndex($0) != nil }
        guard !ids.isEmpty else { return }
        decisions.mark(ids, keep: true, cur: cullCur); changed()
    }

    /// A tile was clicked.
    func select(_ id: String) { guard shoot.photo(id) != nil, cullCur != id else { return }; cullCur = id; changed() }

    /// The Keep / Out buttons under the preview: decide without moving on.
    func cullSet(keep: Bool) { guard let id = cullCur else { return }; decisions.mark(id, keep: keep, cur: id); changed() }
}
