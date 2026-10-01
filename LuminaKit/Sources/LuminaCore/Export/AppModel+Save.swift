import Foundation
import Observation

// WP-7. Save (R-32…R-36, R-83).

/// Save's own state for a window (not persisted): what the last save here wrote, the queue of
/// exports, the message timer.
@MainActor @Observable
public final class SaveFeature {
    /// What a save covered, so the next one can say which photos changed.
    struct Written {
        var sig: String, fmt: SaveFormat
        /// Where copies or JPEGs went (nil for sidecars: they sit next to each photo).
        var destination: String?
        /// Photo id → its look as written ("" = as shot).
        var looks: [String: String]
    }
    /// `save.message` is a failure (error colour, stays until the next action).
    public var messageIsError = false
    @ObservationIgnored var written: Written?
    @ObservationIgnored var messageTimer: ScheduledWork?
    @ObservationIgnored var tail: Task<Void, Never>?
    @ObservationIgnored var running = 0
    @ObservationIgnored var sigCache: (key: [Int], fmt: SaveFormat, withEdits: Bool, sig: String, edited: Int)?
    public init() {}
}

public extension AppModel {
    static let alreadySaved = "Already saved. Nothing changed since."
    static let cardDestination = "Pick a folder that isn’t on the card. Lumina never writes to the card."
    /// How long the ⏎ guard and "Already saved" stay up (the prototype's toast).
    static let saveMessageSeconds: TimeInterval = 3.2

    var saveFeature: SaveFeature { feature(SaveFeature.self) { SaveFeature() } }

    /// The looks that a save would write, by photo id.
    var keptLooks: [String: Look] {
        var d: [String: Look] = [:]
        for id in keptIDs { let l = edits.look(id, decisions: decisions); if !l.isEmpty { d[id] = l } }
        return d
    }

    /// format # edits included # kept ids # each edited photo's look. Cached until a decision,
    /// an edit or a Save option changes (the Save screen asks on every draw; 5,000 photos, R-83).
    var saveSignature: String { signatureAndEdited.sig }

    /// Kept photos that carry an edit, whether or not edits are included.
    var keptEditedCount: Int { signatureAndEdited.edited }

    private var signatureAndEdited: (sig: String, edited: Int) {
        let f = saveFeature, key = [ObjectIdentifier(decisions).hashValue, decisions.revision, ObjectIdentifier(edits).hashValue, edits.revision, copied]
        if let c = f.sigCache, c.key == key, c.fmt == save.fmt, c.withEdits == save.withEdits { return (c.sig, c.edited) }
        let looks = keptLooks
        let sig = SaveSignature.make(fmt: save.fmt, withEdits: save.withEdits, kept: keptIDs, looks: looks)
        f.sigCache = (key, save.fmt, save.withEdits, sig, looks.count)
        return (sig, looks.count)
    }

    /// Nothing has changed since the last save: the button reads "✓ Saved" and saving does nothing (R-34).
    var saveIsCurrent: Bool {
        guard let s = save.saved, s.sig == saveSignature else { return false }
        // Same photos and looks, but the copies were sent somewhere else since: that is a change too.
        if let w = saveFeature.written, w.sig == s.sig, w.fmt != .xmp { return w.destination == exportDestination(w.fmt).path }
        return true
    }

    /// ⌘S: from another step, go to Save without saving (R-35); on Save, save.
    func saveShortcut() { if step == .save { saveNow() } else { go(.save) } }

    /// ⏎ on Save: only after a pause (R-33). With nothing kept it does nothing at all (R-36).
    func saveEnter() {
        let now = clock.now, sinceLast = now.timeIntervalSince(save.lastEnter)
        save.lastEnter = now
        guard !keptIDs.isEmpty else { return }
        guard sinceStepChange >= 1.5, sinceLast >= 1 else { saveSay(KeyRouter.saveGuard); return }
        saveNow()
    }

    /// The Save button and ⌘S. The save is recorded at once (R-83); the files are written off
    /// the main thread, one save after another. Saving what is already saved does nothing, so a
    /// triple click plus ⌘S ⌘S is one save (R-32, R-34).
    func saveNow() {
        let kept = keptIDs
        guard !kept.isEmpty else { return }
        if saveIsCurrent { saveSay(Self.alreadySaved); return }
        let f = saveFeature, previous = save.saved
        var job: ExportJob?
        let sig = saveSignature
        Perf.measure("Save") {
            let looks = save.withEdits ? keptLooks : [:]
            let fmt = save.fmt, dest = exportDestination(fmt)
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            var now: [String: String] = [:]; now.reserveCapacity(kept.count)
            for id in kept { now[id] = looks[id].flatMap { try? enc.encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? "" }
            let path = fmt == .xmp ? nil : dest.path
            // Only what changed is rewritten: the photos whose look or membership changed since
            // the last save of the same kind to the same place.
            var changedOnly: Set<String>?
            if let w = f.written, w.fmt == fmt, w.destination == path {
                var c = Set(kept.filter { w.looks[$0] != now[$0] })
                for id in w.looks.keys where now[id] == nil { c.insert(id) }
                changedOnly = c
            }
            save.saved = SavedRecord(sig: sig, n: kept.count, ne: looks.count, fmt: fmt, at: clock.now, again: previous != nil)
            f.written = SaveFeature.Written(sig: sig, fmt: fmt, destination: path, looks: now)
            job = ExportJob(format: fmt, items: kept.compactMap { id in shoot.photo(id).map { .init(photo: $0, look: looks[id]) } },
                            destination: dest, changedOnly: changedOnly)
        }
        clearSaveMessage()
        changed()
        if let job { enqueue(job, sig: sig, previous: previous) }
    }

    /// Exports run one at a time, in the order they were asked for, off the main thread.
    private func enqueue(_ job: ExportJob, sig: String, previous: SavedRecord?) {
        let f = saveFeature, exporter = services.exporter, before = f.tail
        f.running += 1; save.saving = true
        f.tail = Task { [weak self] in
            await before?.value
            let r = await Task.detached(priority: .utility) { await exporter.export(job) }.value
            self?.exportFinished(r, sig: sig, previous: previous, count: job.items.count)
        }
    }

    private func exportFinished(_ r: ExportResult, sig: String, previous: SavedRecord?, count: Int) {
        let f = saveFeature
        f.running -= 1; save.saving = f.running > 0
        if let u = r.reveal { save.lastResult = u }
        guard !r.failed.isEmpty else { return }
        // Some files aren't there: don't keep saying "Saved". The save before this one stands,
        // and the next save writes everything again.
        Perf.log.error("save: \(r.failed.count, privacy: .public) of \(count, privacy: .public) photos not written")
        f.written = nil
        if save.saved?.sig == sig { save.saved = previous; changed() }
        let first = r.failed.keys.sorted().first!
        let name = shoot.photo(first)?.file ?? first, more = r.failed.count - 1
        saveSay("\(r.failed.count) of \(count) photos weren’t saved: \(name) · \(r.failed[first]!)\(more > 0 ? ", and \(more) more" : ""). Nothing was lost. Save again to retry.", error: true)
    }

    /// Wait for the exports asked for so far (tests, and quitting cleanly).
    func saveSettled() async { var seen: Task<Void, Never>?; while let t = saveFeature.tail, t != seen { await t.value; seen = t } }

    func setFormat(_ f: SaveFormat) { guard save.fmt != f else { return }; save.fmt = f; clearSaveMessage(); changed() }
    func setWithEdits(_ on: Bool) { guard save.withEdits != on else { return }; save.withEdits = on; clearSaveMessage(); changed() }

    // MARK: destination

    /// "Change…": the UI's folder picker (`hooks.pickDestination`) ends here.
    func chooseDestination() { hooks.pickDestination?() }

    /// Where Folder copies and JPEGs go from now on. A card is refused (trust rules).
    func setDestination(_ url: URL) {
        if ExportFiles.isCard(url) { saveSay(Self.cardDestination, error: true); return }
        guard save.destination != url else { return }
        save.destination = url; clearSaveMessage(); changed()
    }

    /// The folder the photos are in (sidecars go next to each one): the first kept file's folder.
    /// The demo card has no files; it shows where the app copies a card to.
    var shootFolder: URL {
        for id in keptIDs.prefix(1) { if case .file(let u)? = shoot.photo(id)?.source { return u.deletingLastPathComponent() } }
        for p in shoot.photos.prefix(1) { if case .file(let u) = p.source { return u.deletingLastPathComponent() } }
        return Self.libraryRoot.appendingPathComponent(shootDay)
    }

    /// Where a save in `fmt` lands: the chosen folder, or ~/Pictures/Lumina/{day} {name}/Keepers
    /// (JPEG for JPEGs). For Lightroom it is the photos' own folder (only "Show in Finder" uses it).
    func exportDestination(_ fmt: SaveFormat) -> URL {
        if fmt == .xmp { return shootFolder }
        if let d = save.destination { return d }
        return Self.libraryRoot.appendingPathComponent("\(shootDay) \(shoot.name)").appendingPathComponent(fmt == .jpeg ? "JPEG" : "Keepers")
    }

    private static var libraryRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Lumina") }
    private var shootDay: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: shoot.photos.first?.shot ?? clock.now)
    }

    /// "Show in Finder": what the last save wrote, else where it will go.
    func revealSaved() { hooks.reveal?(save.lastResult ?? exportDestination(save.saved?.fmt ?? save.fmt)) }

    // MARK: messages

    /// The line beside the Save button. Notices go away by themselves; failures stay.
    func saveSay(_ text: String, error: Bool = false) {
        let f = saveFeature
        f.messageTimer?.cancel(); f.messageTimer = nil
        save.message = text; f.messageIsError = error
        guard !error else { return }
        f.messageTimer = clock.after(Self.saveMessageSeconds) { [weak self] in
            guard let self, self.save.message == text else { return }
            self.save.message = nil
        }
    }

    func clearSaveMessage() {
        let f = saveFeature
        f.messageTimer?.cancel(); f.messageTimer = nil
        if save.message != nil { save.message = nil }
        if f.messageIsError { f.messageIsError = false }
    }
}
