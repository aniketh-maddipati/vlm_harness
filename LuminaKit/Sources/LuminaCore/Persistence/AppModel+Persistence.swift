import Foundation

// WP-8. Snapshot, write-through and restore (R-07, R-19, R-1A, R-70…R-72, R-84).
//
// Write-through. `changed()` → `persistSoon()` takes the snapshot there and then (so a shoot
// swapped a moment later can't lose the old one's last change) and hands it to the store:
//   · at once when nothing was written in the last 250 ms, when the step, the shoot, the save
//     record or the save options changed (R-07: leaving Edit), or when 15 more photos were copied (R-1A);
//   · otherwise 250 ms after the previous write, newest state only: a slider drag or 5,000 fast
//     decisions cost four writes a second.
// `flushPersistence()` writes whatever is unsaved before it returns (quit).
//
// Two windows (R-72), as the prototype does it: a window that sees another window write the shoot
// it shows gets "Changed in another window" and keeps its own state. It does not reload, and the
// warning stays for the window's life. Whichever window changes something next writes its whole
// state: the last change made wins.

public extension AppModel {
    var snapshot: Snapshot {
        let st = persistence
        return Snapshot(shootKey: shoot.key, step: step, cur: cullCur, copied: copied, keep: decisions.keep, looks: edits.looks,
                        tags: edits.tags, done: Array(edits.done), fmt: save.fmt, withEdits: save.withEdits, saved: save.saved,
                        destination: save.destination?.path, folderName: shoot.local ? shoot.name : nil,
                        folderBookmark: shoot.local ? st.folderBookmark : nil, folderPath: shoot.local ? st.folderPath : nil,
                        photoCount: total, revision: revision, writer: windowID)
    }

    /// Called by `changed()`. Writes through, coalesced (see the top of this file).
    func persistSoon() {
        let st = persistence
        wirePersistence()
        let item = persistItem
        if let p = st.pending, p.snapshot.shootKey != item.snapshot.shootKey { st.pending = nil; write(p) }
        st.pending = item
        let wait = PersistenceState.interval - clock.now.timeIntervalSince(st.lastWriteAt)
        if wait <= 0 || mustWriteNow(item.snapshot, after: st.written?.snapshot) { writePending() }
        // Held strongly on purpose: a window closed with a change still waiting writes it first.
        else if st.timer == nil { st.timer = clock.after(wait) { self.writePending() } }
        refreshWarning()
    }

    /// Everything unsaved is on disk when this returns. Call it from `applicationWillTerminate`
    /// (`AppModel.flushAllPersistence()` does every window); cheap when nothing changed.
    func flushPersistence() {
        let st = persistence
        st.timer?.cancel(); st.timer = nil
        if st.background { st.queue.sync {} }
        let item = persistItem
        let dirty = st.pending != nil || st.failed || st.inFlight > 0 || st.written.map { !PersistenceState.same($0, item) } ?? false
        guard dirty else { return }
        st.pending = nil
        st.seq += 1; st.lastWriteAt = clock.now; st.written = item; st.writes += 1
        wrote(st.seq, PersistenceState.save(item, to: services.persistence))
    }

    /// Flush every window's model (quit). Also runs by itself on `NSApplication.willTerminate`.
    static func flushAllPersistence() { PersistenceRegistry.flushAll() }

    /// Called once at launch, after the card is in place: the step, both current photos, decisions,
    /// edits, copy progress and the save options of the shoot on screen; and, when the last session
    /// was an imported folder that isn't on screen, the offer to reopen it (R-19).
    func restore() {
        let st = persistence
        wirePersistence()
        if let (s, x) = loadSaved(shootKey: shoot.key) {
            apply(s, x, to: shoot, step: true)
            open.hasRecent = !shoot.isEmpty
        }
        if !shoot.local, let last = try? services.persistence.loadLast(), last.shootKey != shoot.key, let name = last.folderName {
            st.reopen = last
            open.reopenName = name; open.reopenCount = last.photoCount; open.hasRecent = true
        }
        refreshWarning()
    }

    static let storageWarning = "Couldn’t save on this computer. Keep this window open."
    static let otherWindowWarning = "Changed in another window"
    static let offlineWarning = "Offline · saved on this computer"
}

// MARK: imported folders (R-19), for WP-2

/// The last session's folder, to reopen or to offer on Open.
public struct FolderToReopen: Sendable, Equatable {
    public var shootKey: String
    public var name: String
    public var photoCount: Int
    public var path: String?
    public var bookmark: Data?
}

public extension AppModel {
    /// Stash where the imported folder is, so the next launch can reopen it. Call it when a
    /// folder is imported, before or after `setShoot`. Makes a security-scoped bookmark when
    /// none is given (a plain one where the app isn't allowed to make scoped ones).
    func rememberFolder(_ url: URL, bookmark: Data? = nil) {
        let st = persistence
        st.folderPath = url.path
        st.folderBookmark = bookmark ?? (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
        if shoot.local { persistSoon() }
    }

    /// The shoot on screen is no longer a folder to come back to (dropped loose files).
    func forgetFolder() {
        let st = persistence
        st.folderPath = nil; st.folderBookmark = nil
        if shoot.local { persistSoon() }
    }

    /// The folder the last session had open, when it isn't the shoot on screen. Nil once it is.
    var folderToReopen: FolderToReopen? {
        persistence.reopen.flatMap { s in
            s.folderName.map { FolderToReopen(shootKey: s.shootKey, name: $0, photoCount: s.photoCount, path: s.folderPath, bookmark: s.folderBookmark) }
        }
    }

    /// The folder to reopen as a URL the app may read: through its bookmark (access to a
    /// security-scoped one is started and left on for the session), else its path when that is
    /// still readable. Nil = show `open.reopenFolder` and let the user choose it again.
    func resolveFolderToReopen() -> URL? {
        guard let f = folderToReopen else { return nil }
        if let b = f.bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = u.startAccessingSecurityScopedResource()
                if FileManager.default.isReadableFile(atPath: u.path) { return u }
            }
            if let u = try? URL(resolvingBookmarkData: b, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.isReadableFile(atPath: u.path) { return u }
        }
        if let p = f.path, FileManager.default.isReadableFile(atPath: p) { return URL(fileURLWithPath: p, isDirectory: true) }
        return nil
    }

    /// What the store holds for a shoot, or nil. A damaged file is reported once and reads as nil.
    func savedSnapshot(shootKey: String) -> Snapshot? { loadSaved(shootKey: shootKey)?.0 }

    /// `setShoot(_:)` with whatever the store remembers for that shoot: decisions, edits, both
    /// current photos, the save options, and with `restoreStep` the step it was left on (the
    /// automatic reopen at launch; a drop or a pick mid-session stays on its step, R-17).
    /// Returns whether anything was restored.
    @discardableResult
    func setShootRestoring(_ s: Shoot, restoreStep: Bool = false) -> Bool {
        let st = persistence
        if st.reopen?.shootKey == s.key, st.folderPath == nil {
            st.folderPath = st.reopen?.folderPath; st.folderBookmark = st.reopen?.folderBookmark
        }
        if st.reopen?.shootKey == s.key { st.reopen = nil; open.reopenName = nil; open.reopenCount = 0 }
        guard let (snap, x) = loadSaved(shootKey: s.key) else { setShoot(s); return false }
        apply(snap, x, to: s, step: restoreStep)
        return true
    }
}

// MARK: inside

extension AppModel {
    var persistence: PersistenceState { feature(PersistenceState.self) { PersistenceState(background: clock is LiveScheduler) } }

    var persistItem: PersistenceState.Item { (snapshot, SnapshotExtras(editCur: editCur)) }

    /// Once per model: hear other windows' writes (R-72), and be flushed at quit.
    func wirePersistence() {
        let st = persistence
        guard !st.wired else { return }
        st.wired = true
        PersistenceRegistry.add(self)
        services.persistence.observe { [weak self] snap in
            if Thread.isMainThread { MainActor.assumeIsolated { self?.persistenceChanged(snap) } }
            else { DispatchQueue.main.async { MainActor.assumeIsolated { self?.persistenceChanged(snap) } } }
        }
    }

    /// The store was written. Our own writes and other shoots' don't concern this window.
    func persistenceChanged(_ snap: Snapshot) {
        guard snap.writer != windowID, snap.shootKey == shoot.key, !shoot.isEmpty else { return }
        persistence.otherWindow = true
        refreshWarning()
    }

    /// `edit.warning`, by what matters most: not saved, then another window, then offline.
    func refreshWarning() {
        let st = persistence
        let w: String? = st.failed ? Self.storageWarning : st.otherWindow ? Self.otherWindowWarning
            : Faults.shared.has(.offline) ? Self.offlineWarning : nil
        let ours = [Self.storageWarning, Self.otherWindowWarning, Self.offlineWarning]
        if edit.warning != w, edit.warning.map(ours.contains) ?? true { edit.warning = w }
    }

    /// Changes that don't wait for the interval: leaving a step (R-07), another shoot, a save,
    /// the save options, and every 15 photos of the copy (R-1A).
    private func mustWriteNow(_ s: Snapshot, after w: Snapshot?) -> Bool {
        guard let w else { return true }
        if s.step != w.step || s.shootKey != w.shootKey || s.saved != w.saved || s.fmt != w.fmt || s.withEdits != w.withEdits { return true }
        return s.copied != w.copied && (s.copied >= w.copied + PersistenceState.copyStride || s.copied >= s.photoCount)
    }

    private func writePending() {
        let st = persistence
        st.timer?.cancel(); st.timer = nil
        guard let item = st.pending else { return }
        st.pending = nil
        write(item)
    }

    private func write(_ item: PersistenceState.Item) {
        let st = persistence, store = services.persistence
        st.seq += 1; let n = st.seq
        st.lastWriteAt = clock.now; st.written = item; st.writes += 1
        guard st.background else { wrote(n, PersistenceState.save(item, to: store)); return }
        st.inFlight += 1
        st.queue.async { [weak self] in
            let error = PersistenceState.save(item, to: store)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self else { return }
                self.persistence.inFlight -= 1
                self.wrote(n, error)
            } }
        }
    }

    /// A write came back. Storage full (R-71) is a state, not an error: warn, keep working in
    /// memory, try again later. Anything else that stops a write is also reported, once.
    private func wrote(_ n: Int, _ error: Error?) {
        let st = persistence
        guard n > st.handled else { return }
        st.handled = n
        if let error {
            st.failed = true
            if case PersistenceError.storageFull = error {} else if !st.reportedWriteError { st.reportedWriteError = true; ErrorFunnel.report("persist", error) }
            if st.retry == nil {
                st.retry = clock.after(PersistenceState.retryInterval) { [weak self] in
                    guard let self else { return }
                    let st = self.persistence
                    st.retry = nil
                    if st.failed { st.pending = self.persistItem; self.writePending() }
                }
            }
        } else {
            st.failed = false
            st.retry?.cancel(); st.retry = nil
        }
        refreshWarning()
    }

    /// The stored state for a shoot. Whatever stops it being read is reported and reads as nothing.
    private func loadSaved(shootKey: String) -> (Snapshot, SnapshotExtras)? {
        do {
            if let s = services.persistence as? any SnapshotExtrasStore { return try s.loadWithExtras(shootKey: shootKey).map { ($0.snapshot, $0.extras) } }
            return try services.persistence.load(shootKey: shootKey).map { ($0, SnapshotExtras()) }
        } catch { ErrorFunnel.report("restore", error); return nil }
    }

    /// Put a stored snapshot on screen for shoot `s`. Ids the shoot no longer has are left out.
    private func apply(_ snap: Snapshot, _ x: SnapshotExtras, to s: Shoot, step restoreStep: Bool) {
        let st = persistence
        let keep = snap.keep.filter { s.photo($0.key) != nil }
        func known(_ key: String) -> Bool { s.photo(key) != nil || s.burst(key) != nil }
        setShoot(s, keep: keep, looks: snap.looks.filter { known($0.key) }, tags: snap.tags.filter { known($0.key) }, done: snap.done.filter(known))
        if !s.local { copied = max(copied, min(snap.copied, total)) }
        if let c = snap.cur, s.photo(c) != nil { cullCur = c }
        if cullCur == nil { cullCur = visiblePhotos.first?.id }
        editCur = x.editCur.flatMap { s.photo($0) != nil ? $0 : nil }
        save.fmt = snap.fmt; save.withEdits = snap.withEdits; save.saved = snap.saved
        save.destination = snap.destination.map { URL(fileURLWithPath: $0) }
        if s.local, st.folderPath == nil { st.folderPath = snap.folderPath; st.folderBookmark = snap.folderBookmark }
        if restoreStep {
            step = snap.step
            if step == .edit { enterEdit() }
            // Arriving by relaunch counts as arriving: a ⏎ still held doesn't start or save anything (R-01, R-33).
            if step != .open { stepChangedAt = clock.now }
            // A copy that was under way goes on (`launch` restarts it when `copying` is set), R-1A.
            if !s.local, copied < total, snap.step != .open || snap.copied > 0 { copying = true }
        }
        st.written = persistItem
    }
}
