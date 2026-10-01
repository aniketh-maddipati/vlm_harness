import Foundation
import CoreGraphics

// WP-3. Cull keys (KEYMAP "Cull", R-04, R-05, R-08, R-28; behaviour pinned by the parity traces).

/// Cull's own working state for one window: what the grid measured, and the message timer.
@MainActor
public final class CullSession {
    /// Height of the grid's scroll area, as last laid out (the tile-height formula's input).
    public var gridHeight: CGFloat?
    var messageTimer: ScheduledWork?
    var prefsLoaded = false
    public init() {}
}

public extension AppModel {
    /// How long a message stays in the footer before the key reminder comes back.
    static let cullMessageSeconds: TimeInterval = 3.2
    static let cullKeyReminder = "R keep · X out · ← → photos · ↑ ↓ scenes · U next undecided · ⌘Z undo · ⇧⌘Z redo · ⌘3 Edit · ⌘4 Save"

    var cullSession: CullSession { feature(CullSession.self) { CullSession() } }

    private var visibleCount: Int { shoot.local ? total : min(copied, total) }
    private func visibleIndex(_ id: String?) -> Int? { shoot.position(id).flatMap { $0 < visibleCount ? $0 : nil } }

    /// A message in Cull's footer; the key reminder returns after a few seconds.
    private func cullSay(_ text: String) {
        say(text)
        let shown = toast, session = cullSession
        session.messageTimer?.cancel()
        session.messageTimer = clock.after(Self.cullMessageSeconds) { [weak self] in
            if let self, self.toast == shown { self.toast = nil }
        }
    }

    /// R / X: decide the current photo, then move to the next.
    func cullMark(keep: Bool) {
        let n = visibleCount
        guard n > 0 else { return }
        let i = visibleIndex(cullCur) ?? 0, photo = shoot.photos[i]
        decisions.decide(photo.id, keep: keep, cur: photo.id)
        cullCur = shoot.photos[min(i + 1, n - 1)].id
        cullSay((keep ? "Kept " : "Out · ") + photo.file + " · ⌘Z undoes")
        changed()
    }

    func cullMove(_ d: Int) {
        let n = visibleCount
        guard n > 0 else { return }
        guard let i = visibleIndex(cullCur) else { cullCur = shoot.photos[0].id; changed(); return }
        let j = clamp(0, i + d, n - 1)
        guard j != i else { return }
        cullCur = shoot.photos[j].id; changed()
    }

    /// ↑ / ↓: the first photo of the previous / next scene (the nearest one with photos on screen).
    func cullScene(_ d: Int) {
        guard d != 0 else { return }
        guard let p = shoot.photo(cullCur), visibleIndex(p.id) != nil else { cullMove(0); return }
        var s = p.scene + (d > 0 ? 1 : -1)
        while shoot.scenes.indices.contains(s) {
            if let first = shoot.scenes[s].ids.first(where: { visibleIndex($0) != nil }) { cullCur = first; changed(); return }
            s += d > 0 ? 1 : -1
        }
    }

    /// U: the next undecided photo, wrapping around.
    func cullNextUndecided() {
        let n = visibleCount; guard n > 0 else { return }
        let i = visibleIndex(cullCur) ?? -1, keep = decisions.keep
        for k in 1...n {
            let p = shoot.photos[(i + k) % n]
            if keep[p.id] == nil { if cullCur != p.id { cullCur = p.id; changed() }; return }
        }
        cullSay("Everything is decided")
    }

    /// ⌘Z: undo the last decision and go back to the photo it was made on.
    func cullUndo() {
        guard let c = decisions.undo(from: cullCur) else { cullSay("Nothing to undo"); return }
        if let cur = c.cur, visibleIndex(cur) != nil { cullCur = cur }
        cullSay("Undone · ⇧⌘Z redoes"); changed()
    }
    /// ⇧⌘Z / ⌘Y: redo, and go back to the photo that was current when it was undone.
    func cullRedo() {
        guard let c = decisions.redo(from: cullCur) else { cullSay("Nothing to redo"); return }
        if let cur = c.cur, visibleIndex(cur) != nil { cullCur = cur }
        cullSay("Redone"); changed()
    }

    /// The tile height in use: the ⌘+ / ⌘− choice, else clamp(80, 0.115 × gridHeight, 200).
    func cullTileHeight(gridHeight: CGFloat) -> CGFloat {
        cull.tileHeightOverride.map { clamp(CullLayout.userRange.lowerBound, CGFloat($0), CullLayout.userRange.upperBound) }
            ?? CullLayout.tileHeight(gridHeight: gridHeight)
    }

    /// ⌘+ / ⌘−: tile height ×1.25 per step, 64…320, remembered.
    func cullTileSize(_ d: Int) {
        guard d != 0 else { return }
        cullRestoreTileSize()
        // The top bar and the footer take about 100pt when the grid hasn't been measured yet.
        let base = cullTileHeight(gridHeight: cullSession.gridHeight ?? max(0, windowSize.height - 100))
        let next = clamp(CullLayout.userRange.lowerBound, (d > 0 ? base * CullLayout.userStep : base / CullLayout.userStep).rounded(), CullLayout.userRange.upperBound)
        cull.tileHeightOverride = Double(next)
        CullPrefs.save(tileHeight: Double(next), config: config)
    }

    /// Bring back the tile size chosen in an earlier session. Safe to call any number of times.
    func cullRestoreTileSize() {
        let session = cullSession
        guard !session.prefsLoaded else { return }
        session.prefsLoaded = true
        if cull.tileHeightOverride == nil, let h = CullPrefs.tileHeight(config: config) { cull.tileHeightOverride = h }
    }

    /// "Keep n suggested": the scene's undecided, suggested photos, as one undo step.
    func keepSuggested(scene: Int) {
        guard shoot.scenes.indices.contains(scene) else { return }
        let keep = decisions.keep
        let ids = shoot.scenes[scene].ids.filter { keep[$0] == nil && shoot.photo($0)?.suggested == true && visibleIndex($0) != nil }
        guard !ids.isEmpty else { return }
        decisions.mark(ids, keep: true, cur: cullCur)
        cullSay("Kept \(ids.count) suggested · ⌘Z undoes"); changed()
    }

    /// A tile was clicked.
    func select(_ id: String) { guard shoot.photo(id) != nil, cullCur != id else { return }; cullCur = id; changed() }

    /// The Keep / Out buttons under the preview: decide without moving on.
    func cullSet(keep: Bool) {
        guard let id = cullCur, let p = shoot.photo(id) else { return }
        guard decisions.keep[id] != keep else { return }
        decisions.mark(id, keep: keep, cur: id)
        cullSay((keep ? "Kept " : "Out · ") + p.file + " · ⌘Z undoes"); changed()
    }
}

/// The tile size the user chose with ⌘+ / ⌘−: a preference of the person, not of a shoot, so it
/// lives beside the store rather than in a shoot's snapshot. A launch with its own store
/// directory keeps it there; tests and command-line tools without one keep it in memory only.
enum CullPrefs {
    private static let key = "lumina.cull.tileHeight.v1", file = "cull-prefs.json"
    /// Only the app itself writes the user's defaults.
    private static func usesDefaults(_ config: LaunchConfig) -> Bool { !config.uiTest && Bundle.main.bundleIdentifier != nil }

    static func tileHeight(config: LaunchConfig) -> Double? {
        let v: Double?
        if let dir = config.storeDir {
            v = (try? Data(contentsOf: dir.appendingPathComponent(file))).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }?["tileHeight"]
        } else if usesDefaults(config) {
            v = UserDefaults.standard.object(forKey: key) as? Double
        } else { v = nil }
        return v.flatMap { $0.isFinite && CullLayout.userRange.contains(CGFloat($0)) ? $0 : nil }
    }

    static func save(tileHeight: Double, config: LaunchConfig) {
        if let dir = config.storeDir {
            // Losing the tile size is harmless; a full disk is reported by the store itself (R-71).
            guard !Faults.shared.has(.storageFull), let data = try? JSONEncoder().encode(["tileHeight": tileHeight]) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
        } else if usesDefaults(config) {
            UserDefaults.standard.set(tileHeight, forKey: key)
        }
    }
}
