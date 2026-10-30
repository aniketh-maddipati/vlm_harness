import Foundation

/// Live AirDrop (LOCAL-CHANGES 316): clips that land in the watched folder (Downloads, where AirDrop saves) while the
/// switch is on are added to the open shoot, or start one, with no Finder panel. AirDrop is only ever an input: the
/// watched folder never becomes a shoot's folder (Trash, Arrange, the drive line), and nothing in it is moved, renamed or
/// written; Skim only reads the clips it hands over.
///
/// This is the decision half, pure over snapshots of (name, size, modified) at a time, so the tests can drive it: what
/// counts as an arrival (a clip that was not there when the switch went on, never a dot-file or a file still being
/// downloaded), when it has settled (the same size and time on two looks `settle` apart, so a clip still being written is
/// never handed over), and which arrivals go together (handed over once nothing new has happened for `gather`, or `hold`
/// after the first settled, whichever comes first). Foundation only.
nonisolated struct SkimAirdrop: Sendable {
    static let settle: TimeInterval = 0.8
    static let gather: TimeInterval = 1.5
    /// A settled clip waits at most this long for a big one still arriving beside it.
    static let hold: TimeInterval = 10
    /// The names a download carries until it is complete (Safari, Chrome, Firefox, the Finder's copy, iCloud).
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload", "icloud"]

    /// A file that may be a clip arriving: a clip by its name as the page reads one, not hidden, not a partial download.
    static func isArrival(_ name: String) -> Bool {
        guard !name.hasPrefix("."), !name.hasPrefix("~"), !name.hasSuffix("~") else { return false }
        guard !partialExtensions.contains((name as NSString).pathExtension.lowercased()) else { return false }
        return SkimPickScan.isClip(name)
    }

    /// One file as one look saw it. A file preallocated at its full size and filled in place still changes `modified`.
    struct Mark: Equatable, Sendable {
        var size: Int64
        var modified: TimeInterval = 0
    }

    struct Seen: Equatable, Sendable {
        var mark: Mark
        /// When the mark was last seen to change (or first seen).
        var changed: TimeInterval
    }

    /// Names there when the switch went on: never arrivals, unless they go away and come back.
    private(set) var before: Set<String>
    /// Arrivals not settled yet.
    private(set) var settling: [String: Seen] = [:]
    /// Arrivals settled, waiting to be handed over with the rest of their batch.
    private(set) var settled: [String: Mark] = [:]
    /// Arrivals already handed over: never again while they stay as they were (a clip replaced by another is new).
    private(set) var handed: [String: Mark] = [:]
    private var lastActivity: TimeInterval = -.infinity
    private var firstSettled: TimeInterval?

    init(existing: [String]) { before = Set(existing) }

    /// Something is on its way: the watcher keeps looking every half second until this is false.
    var waiting: Bool { !settling.isEmpty || !settled.isEmpty }

    /// One look at the folder: every candidate file's mark now.
    mutating func look(_ files: [String: Mark], at now: TimeInterval) {
        before.formIntersection(files.keys)
        for name in settling.keys where files[name] == nil { settling[name] = nil }
        for name in settled.keys where files[name] == nil { settled[name] = nil }
        for name in handed.keys where files[name] == nil { handed[name] = nil }
        for (name, mark) in files where Self.isArrival(name) && !before.contains(name) {
            if let h = handed[name], h == mark { continue }
            if let s = settled[name] {
                if s == mark { continue }
                settled[name] = nil              // changed again after it looked done: it starts over
            }
            if var s = settling[name] {
                if s.mark != mark { s.mark = mark; s.changed = now; settling[name] = s; lastActivity = now; continue }
                if mark.size > 0, now - s.changed >= Self.settle {
                    settling[name] = nil; settled[name] = mark
                    if firstSettled == nil { firstSettled = now }
                }
            } else {
                settling[name] = Seen(mark: mark, changed: now); lastActivity = now
            }
        }
        if settled.isEmpty { firstSettled = nil }
    }

    /// Convenience for sizes alone (the tests).
    mutating func look(sizes: [String: Int64], at now: TimeInterval) {
        look(sizes.mapValues { Mark(size: $0) }, at: now)
    }

    /// The batch to hand over now, sorted by name, or nil while it is still gathering.
    mutating func take(at now: TimeInterval) -> [String]? {
        guard !settled.isEmpty, let first = firstSettled else { return nil }
        let quiet = settling.isEmpty && now - lastActivity >= Self.gather
        guard quiet || now - first >= Self.hold else { return nil }
        let out = settled.keys.sorted()
        for (n, m) in settled { handed[n] = m }
        settled = [:]; firstSettled = nil
        return out
    }
}

/// The watching: a file-system source on the folder (an entry added, renamed or removed), and, while something is on
/// its way, a look every half second, since a file growing inside the folder doesn't change the folder. Off the main
/// thread, on its own serial queue; `onBatch` gets the settled clips' URLs there. `onGone` when the folder can no longer
/// be read (moved, deleted, the drive gone). Read only: names, kinds, sizes and times. Foundation only.
nonisolated final class SkimAirdropWatch: @unchecked Sendable {
    let folder: URL
    private let queue = DispatchQueue(label: "lumina.skim.airdrop", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var state = SkimAirdrop(existing: [])
    private let onBatch: @Sendable ([URL]) -> Void
    private let onGone: @Sendable () -> Void
    private let clock: @Sendable () -> TimeInterval

    init(folder: URL, clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onBatch: @escaping @Sendable ([URL]) -> Void, onGone: @escaping @Sendable () -> Void) {
        self.folder = folder; self.clock = clock; self.onBatch = onBatch; self.onGone = onGone
    }

    /// Starts watching; what is in the folder now is never handed over. False when the folder can't be opened or read.
    func start() -> Bool {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        guard let now = list() else { close(fd); return false }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, let s = self.source else { return }
            if !s.data.isDisjoint(with: [.rename, .delete, .revoke]) { self.stopOnQueue(); self.onGone(); return }
            self.tick()
        }
        src.setCancelHandler { close(fd) }
        queue.sync {
            state = SkimAirdrop(existing: Array(now.keys))
            source = src
        }
        src.resume()
        return true
    }

    func stop() { queue.async { [weak self] in self?.stopOnQueue() } }

    private func stopOnQueue() {
        timer?.cancel(); timer = nil
        source?.cancel(); source = nil
    }

    /// The folder's arrival candidates and their marks (only those are stat'ed: a Downloads folder can hold thousands).
    private func list() -> [String: SkimAirdrop.Mark]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        var out: [String: SkimAirdrop.Mark] = [:]
        for n in names where SkimAirdrop.isArrival(n) {
            var st = stat()
            guard lstat(folder.appendingPathComponent(n).path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            out[n] = .init(size: Int64(st.st_size), modified: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
        }
        return out
    }

    private func tick() {
        guard source != nil else { return }
        guard let files = list() else { stopOnQueue(); onGone(); return }
        let now = clock()
        state.look(files, at: now)
        if let batch = state.take(at: now) { onBatch(batch.map { folder.appendingPathComponent($0) }) }
        if state.waiting, timer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume(); timer = t
        } else if !state.waiting, let t = timer {
            t.cancel(); timer = nil
        }
    }
}

/// The switch's state kept with the folder's bookmark: `skim/airdrop.json` in the container.
nonisolated struct SkimAirdropStore: Sendable {
    struct Saved: Codable, Equatable, Sendable {
        var bookmark: Data
        var path: String
        var on: Bool
    }
    let file: URL

    func read() -> Saved? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    @discardableResult
    func write(_ s: Saved?) -> Bool {
        do {
            guard let s else { try? FileManager.default.removeItem(at: file); return true }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(s).write(to: file, options: .atomic)
            return true
        } catch { return false }
    }
}
