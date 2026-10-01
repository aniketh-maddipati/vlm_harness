import Foundation

// WP-8. Snapshot, write-through and restore (R-70…R-72, R-1A, R-19).

public extension AppModel {
    var snapshot: Snapshot {
        Snapshot(shootKey: shoot.key, step: step, cur: cullCur, copied: copied, keep: decisions.keep, looks: edits.looks,
                 tags: edits.tags, done: Array(edits.done), fmt: save.fmt, withEdits: save.withEdits, saved: save.saved,
                 destination: save.destination?.path, folderName: shoot.local ? shoot.name : nil, photoCount: total,
                 revision: revision, writer: windowID)
    }

    /// Called by `changed()`. WP-8: write through (Edit drags coalesced), warn on a full disk.
    func persistSoon() {
        do { try services.persistence.save(snapshot); if edit.warning == Self.storageWarning { edit.warning = nil } }
        catch PersistenceError.storageFull { edit.warning = Self.storageWarning }
        catch { ErrorFunnel.report("persist", error) }
    }

    /// Called once at launch, after the card is in place. WP-8: step, photo, decisions, edits, copy progress.
    func restore() {
        guard let s = try? services.persistence.load(shootKey: shoot.key) else { return }
        setShoot(shoot, keep: s.keep, looks: s.looks, tags: s.tags, done: s.done)
        copied = max(copied, s.copied); cullCur = s.cur ?? cullCur
        save.fmt = s.fmt; save.withEdits = s.withEdits; save.saved = s.saved
        step = s.step
    }

    static let storageWarning = "Couldn’t save on this computer. Keep this window open."
    static let otherWindowWarning = "Changed in another window"
    static let offlineWarning = "Offline · saved on this computer"
}
