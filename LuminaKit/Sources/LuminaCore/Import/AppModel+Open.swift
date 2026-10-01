import Foundation

// WP-2. Open: the card copy, imports and drops, the folder to reopen, Start over
// (R-01, R-10…R-1A, R-31, R-85).
//
// A window has at most two shoots in a session: the card and the "local" shoot made of everything
// imported or dropped. The first import puts the local shoot in place of the card; later imports
// add to it. The card's button goes back to the card, the folder row goes back to the local shoot,
// and each keeps its own decisions (stored under its own `Shoot.key`).

/// WP-2's own state: the import queue and the two shoots. Not observed; what the screen shows is
/// in `AppModel.open` and `AppModel.imports`.
@MainActor
final class OpenFeature {
    struct Batch {
        var urls: [URL]
        /// The launch reopening the last folder by itself (R-19): no message, and the step comes back too.
        var reopen = false
        /// The store key to use if this batch starts the local shoot (a reopened folder keeps its key).
        var key: String?
        var step: Step
    }
    var queue: [Batch] = []
    var runner: Task<Void, Never>?
    var batchID = 0
    /// Bumped whenever the copy is (re)started or stopped; a tick from an older run does nothing.
    var copyRun = 0
    var localItems: [ImportItem] = []
    var localShoot: Shoot?
    var localKey: String?
    var roots: [FolderRoot] = []
    var cardShoot: Shoot?
    /// A shoot's state when the window last switched away from it (the store may still be writing).
    var stash: [String: Snapshot] = [:]
    var triedReopen = false
    var startOverTimer: ScheduledWork?
}

public extension AppModel {
    internal var openFeature: OpenFeature { feature(OpenFeature.self) { OpenFeature() } }

    // MARK: the card

    /// ⏎ on Open, or the card button: start the copy (once) and go to Cull. Ignored within
    /// 450 ms of a step change (R-01).
    func openEnter() {
        guard sinceStepChange >= 0.45 else { return }
        startCulling()
    }

    func startCulling() {
        let f = openFeature
        // The button belongs to the card: with an imported folder on screen it goes back to the card.
        var switched = false
        if shoot.local, let card = f.cardShoot ?? Shoot.card(config.card), !card.isEmpty {
            f.stash[shoot.key] = snapshot
            adopt(card, from: f.stash[card.key] ?? (try? services.persistence.load(shootKey: card.key)))
            switched = true
        }
        guard !shoot.isEmpty else { return }
        if !shoot.local, copied < total, !copying { startCopy() }
        if switched, step == .cull { changed() }
        go(.cull)
    }

    /// The (simulated) card copy: photos arrive one by one at `config.copyRate` per second. The
    /// count only goes up (R-1A), is saved at least every 15 photos, and a relaunch picks it up
    /// where it stopped (`AppModel.launch` calls this again).
    func startCopy() {
        let f = openFeature
        f.copyRun += 1
        guard !shoot.local, copied < total else { copying = false; return }
        copying = true
        let run = f.copyRun, key = shoot.key, rate = max(1, config.copyRate ?? 66)
        let base = copied, began = clock.now, interval = max(1 / rate, 1.0 / 120)
        func tick() {
            guard f.copyRun == run, copying, shoot.key == key else { return }
            // By the clock, not by counting ticks: a late timer never slows the copy down.
            let due = base + Int((clock.now.timeIntervalSince(began) * rate + 1e-6).rounded(.down))
            let next = min(total, max(copied, due))
            if next != copied {
                let before = copied
                copied = next
                if cullCur == nil { cullCur = shoot.photos.first?.id }
                if next >= total { copying = false; changed() } else if next / 15 != before / 15 { changed() }
            }
            if copied < total { clock.after(interval) { tick() } }
        }
        clock.after(interval) { tick() }
    }

    // MARK: pickers

    /// ⌘O / "Open folder…".
    func chooseFolder() { hooks.pickFolder?() }

    /// "Choose photos…".
    func choosePhotos() { hooks.pickPhotos?() }

    // MARK: import

    /// Folders and files from a picker, a drop or `LUMINA_FIXTURE`. Folders are walked all the way
    /// down off the main thread; every file is classified, decoded and checked against what the
    /// shoot already has, then the shoot is regrouped (R-10…R-16). A batch that arrives while
    /// another is being checked waits its turn; nothing is lost (R-18).
    func importURLs(_ urls: [URL]) { enqueueImport(urls) }

    /// Resolves when every queued import has been applied (tests, and anything that must not race one).
    func importsIdle() async {
        while let t = openFeature.runner { await t.value }
    }

    private func enqueueImport(_ urls: [URL], reopen: Bool = false, key: String? = nil) {
        guard !urls.isEmpty else { return }
        let f = openFeature
        f.queue.append(OpenFeature.Batch(urls: urls, reopen: reopen, key: key, step: step))
        imports.busy = true
        if f.runner == nil { f.runner = Task { @MainActor [weak self] in await self?.drainImports() } }
    }

    private func drainImports() async {
        let f = openFeature
        while !f.queue.isEmpty {
            let batch = f.queue.removeFirst()
            f.batchID += 1
            let id = f.batchID, signpost = Perf.begin("Import")
            imports.busy = true; imports.checked = 0; imports.toCheck = 0
            let request = ImportRequest(urls: batch.urls, existing: f.localItems, shootName: f.localShoot?.name)
            // The main thread only ever gets two integers from the check, so keys stay quick (R-85).
            let progress: @Sendable (Int, Int) -> Void = { [weak self] checked, toCheck in
                Task { @MainActor [weak self] in
                    guard let self, self.openFeature.batchID == id, self.imports.busy else { return }
                    self.imports.checked = max(self.imports.checked, checked); self.imports.toCheck = toCheck
                }
            }
            let outcome = await Task.detached(priority: .utility) { await ImportWalker.run(request, progress: progress) }.value
            finishImport(outcome, batch)
            Perf.end("Import", signpost)
        }
        imports.busy = false; imports.checked = 0; imports.toCheck = 0
        f.runner = nil
    }

    private func finishImport(_ o: ImportOutcome, _ batch: OpenFeature.Batch) {
        let f = openFeature
        guard var local = o.shoot, !o.accepted.isEmpty else {
            // Reopening by itself found nothing (the folder moved or was emptied): Open still offers it.
            if batch.reopen { return }
            imports.added = 0; imports.failed = true
            imports.message = o.noFiles && o.unreadable ? ImportSummary.wentWrong
                : ImportSummary(added: 0, skipped: o.skipped, emptyFolder: o.noFiles).message
            if step != .open { say("No photos added. Open has the details.") }
            return
        }
        let key = f.localKey ?? batch.key ?? Self.localShootKey(o.roots, name: o.name)
        local.key = key
        f.localKey = key; f.localItems += o.accepted; f.localShoot = local
        for r in o.roots where !f.roots.contains(where: { $0.path == r.path }) { f.roots.append(r) }

        var stored: Snapshot?
        if shoot.local {
            // More photos for the shoot on screen: every decision and edit stays with its photo.
            setShoot(local, keep: decisions.keep, looks: edits.looks, tags: edits.tags, done: Array(edits.done))
        } else {
            // The first import replaces the card's shoot; a folder seen before gets its decisions back (R-19).
            if !shoot.isEmpty { f.cardShoot = shoot; f.stash[shoot.key] = snapshot }
            stored = f.stash[key] ?? (try? services.persistence.load(shootKey: key))
            adopt(local, from: stored)
        }
        open.hasRecent = true; open.reopenName = local.name; open.reopenCount = local.photos.count
        FolderMemory.save(.init(name: local.name, count: local.photos.count, shootKey: key, roots: f.roots), to: services.persistence, writer: windowID)

        imports.added = o.accepted.count; imports.failed = false
        if batch.reopen {
            imports.message = nil
            // Back where the last session was, unless the user has already gone somewhere.
            if step == batch.step, let s = stored?.step, s != step { go(s) } else { changed() }
            return
        }
        let message = ImportSummary(added: o.accepted.count, folder: Self.isolated(o.name), skipped: o.skipped).message
        imports.message = message
        // From Open the photos are the next thing to look at; anywhere else the drop adds and stays (R-17).
        if step == .open { go(.cull) } else {
            say(message + (step == .edit ? " They show in Cull now, and in Edit next time you open it." : ""))
            changed()
        }
    }

    /// Put `s` on screen with what the store remembers for it: decisions, edits, place, save state.
    private func adopt(_ s: Shoot, from snap: Snapshot?) {
        let f = openFeature
        f.copyRun += 1; copying = false
        let ids = Set(s.photos.map(\.id))
        setShoot(s, keep: (snap?.keep ?? [:]).filter { ids.contains($0.key) }, looks: snap?.looks ?? [:], tags: snap?.tags ?? [:], done: snap?.done ?? [])
        if !s.local { copied = min(s.photos.count, max(0, snap?.copied ?? 0)) }
        if let c = snap?.cur, let i = shoot.position(c), i < visiblePhotos.count { cullCur = c } else { cullCur = visiblePhotos.first?.id }
        editCur = nil
        save.saved = snap?.saved
        if let snap { save.fmt = snap.fmt; save.withEdits = snap.withEdits }
        open.startOverArmedUntil = nil
    }

    /// One key per folder, the same on every launch: decisions are stored under it.
    internal static func localShootKey(_ roots: [FolderRoot], name: String) -> String {
        if let dir = roots.first(where: \.isFolder) { return "folder-" + SceneGrouper.hash(dir.path) }
        if let file = roots.first { return "photos-" + SceneGrouper.hash((file.path as NSString).deletingLastPathComponent) }
        return "folder-" + SceneGrouper.hash(name)
    }

    // MARK: the folder to reopen (R-19)

    /// Once per window, at launch: if the last session ended in an imported folder, open it again
    /// through its bookmark, without asking, and put its decisions and step back. If the folder
    /// can't be reached, or the last session ended on the card, Open offers it as a row instead.
    func reopenLastFolder() {
        let f = openFeature
        guard !f.triedReopen else { return }
        f.triedReopen = true
        guard !shoot.local, f.localShoot == nil, let mem = FolderMemory.load(from: services.persistence) else { return }
        open.reopenName = mem.name; open.reopenCount = mem.count
        guard config.fixture == nil, f.runner == nil else { return }
        let last = (try? services.persistence.loadLast())?.shootKey
        guard last == mem.shootKey || last == FolderMemory.key else { return }
        let urls = mem.roots.compactMap(FolderMemory.resolve)
        guard !urls.isEmpty else { return }
        enqueueImport(urls, reopen: true, key: mem.shootKey.isEmpty ? nil : mem.shootKey)
    }

    /// The "Folder · {name}" row: back to the imported photos. Straight away when they are still
    /// in memory or their bookmark opens; otherwise the folder picker.
    func reopenFolder() {
        let f = openFeature
        if !shoot.local, let local = f.localShoot {
            if !shoot.isEmpty { f.cardShoot = shoot; f.stash[shoot.key] = snapshot }
            adopt(local, from: f.stash[local.key] ?? (try? services.persistence.load(shootKey: local.key)))
            if step == .cull { changed() } else { go(.cull) }
            return
        }
        if let mem = FolderMemory.load(from: services.persistence) {
            let urls = mem.roots.compactMap(FolderMemory.resolve)
            if !urls.isEmpty { enqueueImport(urls, key: mem.shootKey.isEmpty ? nil : mem.shootKey); return }
        }
        chooseFolder()
    }

    // MARK: Recent

    /// The Recent row: on with the shoot, to Save when every photo is decided and something is kept.
    func resumeRecent() {
        go(decisions.keptCount > 0 && openUndecided == 0 ? .save : .cull)
    }

    /// Start over: the first click arms it for 4 s, the second clears the decisions (R-31).
    func startOverClick() {
        let f = openFeature
        f.startOverTimer?.cancel(); f.startOverTimer = nil
        if let until = open.startOverArmedUntil, clock.now < until {
            open.startOverArmedUntil = nil
            f.copyRun += 1; copying = false
            f.stash[shoot.key] = nil
            try? services.persistence.clear(shootKey: shoot.key)
            setShoot(shoot)
            // A card starts again from nothing copied; an imported folder has no copy to redo.
            if !shoot.local { copied = 0 }
            cullCur = visiblePhotos.first?.id; editCur = nil
            save.saved = nil; save.withEdits = true; toast = nil
            changed()
        } else {
            open.startOverArmedUntil = clock.now.addingTimeInterval(4)
            f.startOverTimer = clock.after(4) { [weak self] in
                guard let s = self, let u = s.open.startOverArmedUntil, s.clock.now >= u else { return }
                s.open.startOverArmedUntil = nil
            }
        }
    }
}
