import Foundation

// WP-7. Save (R-32…R-36, R-83).

public extension AppModel {
    /// The looks that a save would write, by photo id.
    var keptLooks: [String: Look] {
        var d: [String: Look] = [:]
        for id in keptIDs { let l = edits.look(id, decisions: decisions); if !l.isEmpty { d[id] = l } }
        return d
    }
    var saveSignature: String { SaveSignature.make(fmt: save.fmt, withEdits: save.withEdits, kept: keptIDs, looks: keptLooks) }

    /// ⌘S: from another step, go to Save without saving (R-35); on Save, save.
    func saveShortcut() { if step == .save { saveNow() } else { go(.save) } }

    /// ⏎ on Save: only after a pause (R-33).
    func saveEnter() {
        let now = clock.now, sinceLast = now.timeIntervalSince(save.lastEnter)
        save.lastEnter = now
        guard sinceStepChange >= 1.5, sinceLast >= 1 else { if !keptIDs.isEmpty { save.message = KeyRouter.saveGuard }; return }
        saveNow()
    }

    func saveNow() {
        let kept = keptIDs
        guard !kept.isEmpty, !save.saving else { return }
        let sig = saveSignature
        if save.saved?.sig == sig { save.message = "Already saved. Nothing changed since."; return }
        let looks = save.withEdits ? keptLooks : [:]
        Perf.measure("Save") {
            save.saved = SavedRecord(sig: sig, n: kept.count, ne: looks.count, fmt: save.fmt, at: clock.now, again: save.saved != nil)
            save.message = nil
        }
        changed()
        let job = ExportJob(format: save.fmt, items: kept.compactMap { id in shoot.photo(id).map { .init(photo: $0, look: looks[id]) } }, destination: save.destination)
        let exporter = services.exporter
        Task { [weak self] in
            let r = await Task.detached(priority: .utility) { await exporter.export(job) }.value
            self?.save.lastResult = r.reveal
            if !r.failed.isEmpty { ErrorFunnel.report("export failed for \(r.failed.count) photos") }
        }
    }

    func setFormat(_ f: SaveFormat) { guard save.fmt != f else { return }; save.fmt = f; save.message = nil; changed() }
    func setWithEdits(_ on: Bool) { guard save.withEdits != on else { return }; save.withEdits = on; save.message = nil; changed() }
}
