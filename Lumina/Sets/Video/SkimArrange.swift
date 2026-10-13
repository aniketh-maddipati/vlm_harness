import Foundation

/// Arrange (Export's workshop, the draft layer): clips the user dragged onto folders, moved there on the same drive after
/// Apply, and put back with Undo, even after a quit. A move is a rename on one drive: a clip never goes to another drive
/// (that would be a copy, which is not built), never onto or off a camera card or a read-only drive, never outside the
/// folders Skim was let into, and never over a file (a name already there leaves that clip where it is). A Sony clip
/// moves with its sidecars (`C0001M01.XML`). Each run is written to `skim/arrange.json` before anything moves, and again
/// after; Undo checks every file on disk (still where Skim put it, same size and date) before moving it back, so a run
/// cut short by a crash undoes what did move. Folders a run made are removed by its Undo only when they are empty.
/// Nothing is deleted. Foundation only.
nonisolated struct SkimArrange: Sendable {
    /// One clip the page wants moved: its file and the folder it goes into (made if it is not there yet).
    struct Move: Equatable, Sendable { var from: String; var dir: String }

    /// One file of a run: where it was, where it went, and what it was then (for Undo's check).
    struct Step: Codable, Equatable, Sendable {
        var clip: String
        var from: String
        var to: String
        var bytes: Int64
        var mtime: Double
        var done: Bool
    }

    struct Run: Codable, Equatable, Sendable {
        var id: String
        var shoot: String
        var at: Double
        var steps: [Step]
        /// Folders this run made, outermost first.
        var made: [String]
        var undone: Bool
        var json: [String: Any] {
            let moved = steps.filter(\.done), clips = Set(moved.map(\.clip))
            return ["id": id, "shoot": shoot, "at": at, "clips": clips.count, "bytes": moved.filter { $0.clip == $0.from }.reduce(Int64(0)) { $0 + $1.bytes }, "undone": undone]
        }
    }

    /// One clip's answer to the page: where it was and where it is now.
    struct Answer: Equatable, Sendable {
        var from: String; var to: String; var ok: Bool; var why: String
        var json: [String: Any] { ["from": from, "to": to, "ok": ok, "why": why] }
    }

    static let maxRuns = 50, maxMoves = 5000
    let log: URL

    func runs() -> [Run] {
        guard let d = try? Data(contentsOf: log), d.count <= 32 << 20 else { return [] }
        return (try? JSONDecoder().decode([Run].self, from: d)) ?? []
    }

    @discardableResult
    private func save(_ r: [Run]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(r.suffix(Self.maxRuns))).write(to: log, options: .atomic)
            return true
        } catch { return false }
    }

    private func put(_ run: Run) -> Bool {
        var all = runs().filter { $0.id != run.id }
        all.append(run)
        return save(all)
    }

    // MARK: Disk facts

    static func std(_ p: String) -> String { URL(fileURLWithPath: p).standardizedFileURL.path }

    /// A plain absolute path: no `..` or `.` parts, no NUL.
    static func plain(_ p: String) -> Bool {
        guard p.hasPrefix("/"), !p.contains("\0") else { return false }
        return !p.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }

    static func attrs(_ p: String) -> [FileAttributeKey: Any]? { try? FileManager.default.attributesOfItem(atPath: p) }
    static func isFile(_ p: String) -> Bool { (attrs(p)?[.type] as? FileAttributeType) == .typeRegular }
    static func isDir(_ p: String) -> Bool { (attrs(p)?[.type] as? FileAttributeType) == .typeDirectory }
    static func exists(_ p: String) -> Bool { attrs(p) != nil }
    static func device(_ p: String) -> UInt64? { (attrs(p)?[.systemNumber] as? NSNumber)?.uint64Value }
    static func size(_ p: String) -> Int64 { (attrs(p)?[.size] as? NSNumber)?.int64Value ?? -1 }
    static func mtime(_ p: String) -> Double { (attrs(p)?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0 }

    /// The deepest folder of `dir` that is on disk, and the names below it still to be made (each a plain folder name).
    static func existing(_ dir: String) -> (base: String, rest: [String])? {
        var base = std(dir), rest: [String] = []
        while !isDir(base) {
            if exists(base) { return nil }   // a file where a folder should be
            let name = (base as NSString).lastPathComponent
            guard SkimPlaces.folderName(name) == name else { return nil }
            rest.insert(name, at: 0)
            base = (base as NSString).deletingLastPathComponent
            if base == "/" || base.isEmpty { return nil }
        }
        return (base, rest)
    }

    // MARK: Apply

    /// Moves each clip (and its sidecars) into its folder. `allowed` says whether a path is inside a folder Skim was let
    /// into; `refuse` gives the reason a place may not be written (a camera card, a read-only drive), or nil. One answer
    /// per move asked for; the run's id is nil when nothing moved.
    func apply(_ moves: [Move], shoot: String, allowed: (String) -> Bool, refuse: (String) -> String?,
               now: Double = Date().timeIntervalSince1970 * 1000) -> (run: String?, answers: [Answer]) {
        let fm = FileManager.default
        var answers = [Answer?](repeating: nil, count: moves.count)
        var plan: [(i: Int, steps: [Step], dir: String, rest: [String], base: String)] = []
        var claimed = Set<String>()
        for (i, m) in moves.enumerated() {
            let no = { (why: String) in answers[i] = Answer(from: m.from, to: "", ok: false, why: why) }
            guard i < Self.maxMoves, Self.plain(m.from), Self.plain(m.dir) else { no("not a place Skim can move to"); continue }
            let from = Self.std(m.from), dir = Self.std(m.dir)
            guard Self.isFile(from) else { no("not there any more"); continue }
            guard let ex = Self.existing(dir) else { no("that folder can't be made there"); continue }
            guard allowed(from), allowed(ex.base) else { no("outside the drives and folders Lumina has access to"); continue }
            if let why = refuse(from) ?? refuse(ex.base) { no(why); continue }
            guard let a = Self.device(from), let b = Self.device(ex.base), a == b else { no("on another drive: Skim moves clips only within one drive"); continue }
            if (from as NSString).deletingLastPathComponent == dir { no("already in that folder"); continue }
            let files = [from] + SkimTrash.companions(of: URL(fileURLWithPath: from)).map(\.path)
            var steps: [Step] = [], taken: String?
            for f in files {
                let to = (dir as NSString).appendingPathComponent((f as NSString).lastPathComponent)
                if Self.exists(to) || claimed.contains(to.lowercased()) { taken = (f as NSString).lastPathComponent; break }
                steps.append(Step(clip: from, from: f, to: to, bytes: Self.size(f), mtime: Self.mtime(f), done: false))
            }
            if let taken { no("a file named \(taken) is already there"); continue }
            steps.forEach { claimed.insert($0.to.lowercased()) }
            plan.append((i, steps, dir, ex.rest, ex.base))
        }
        guard !plan.isEmpty else { return (nil, answers.map { $0! }) }

        // Written before anything moves: a run cut short is still on the list, and Undo finds what moved by looking.
        var run = Run(id: String(format: "%.0f", now) + "-" + String(UUID().uuidString.prefix(6)), shoot: shoot, at: now, steps: plan.flatMap { $0.steps }, made: [], undone: false)
        guard put(run) else { return (nil, answers.enumerated().map { $0.element ?? Answer(from: moves[$0.offset].from, to: "", ok: false, why: "Skim could not keep its note of the moves, so nothing moved") }) }

        var k = 0
        for p in plan {
            defer { k += p.steps.count }
            // the folders still to be made, outermost first
            var at = p.base, made = true
            for name in p.rest {
                at = (at as NSString).appendingPathComponent(name)
                if Self.isDir(at) { continue }
                do { try fm.createDirectory(atPath: at, withIntermediateDirectories: false); run.made.append(at) }
                catch { made = false; break }
            }
            let m = moves[p.i]
            guard made else { answers[p.i] = Answer(from: m.from, to: "", ok: false, why: "the folder could not be made"); continue }
            var why: String?
            for (j, s) in p.steps.enumerated() {
                if Self.exists(s.to) { if j == 0 { why = "a file named \((s.to as NSString).lastPathComponent) is already there"; break }; continue }
                do { try fm.moveItem(atPath: s.from, toPath: s.to); run.steps[k + j].done = true }
                catch { if j == 0 { why = "it could not be moved"; break } }
            }
            answers[p.i] = why.map { Answer(from: m.from, to: "", ok: false, why: $0) } ?? Answer(from: m.from, to: p.steps[0].to, ok: true, why: "")
        }
        _ = put(run)
        return (run.steps.contains(where: \.done) ? run.id : nil, answers.map { $0! })
    }

    // MARK: Undo

    /// Puts a run's files back where they were: each only if it is still where Skim put it, with the same size and date,
    /// and nothing has taken its old place. Then the folders the run made go, if they are empty. One answer per clip.
    func undo(id: String) -> [Answer] {
        var all = runs()
        guard let at = all.firstIndex(where: { $0.id == id }) else { return [] }
        var run = all[at]
        guard !run.undone else { return [] }
        let fm = FileManager.default
        // clip by clip, the last moved first; a clip that can't go back keeps its sidecars with it
        var groups: [(clip: String, idx: [Int])] = []
        for (n, s) in run.steps.enumerated() {
            // a step the note says did not happen may have (the run was cut short): the disk decides
            guard s.done || (!Self.exists(s.from) && Self.isFile(s.to)) else { continue }
            if let g = groups.indices.last, groups[g].clip == s.clip { groups[g].idx.append(n) } else { groups.append((s.clip, [n])) }
        }
        var answers: [Answer] = []
        for g in groups.reversed() {
            guard let head = g.idx.first(where: { run.steps[$0].from == g.clip }) else { continue }
            let c = run.steps[head]
            var why: String?
            if !Self.isFile(c.to) { why = "not where Skim put it any more" }
            else if Self.exists(c.from) { why = "a file is already where it was" }
            else if Self.size(c.to) != c.bytes || abs(Self.mtime(c.to) - c.mtime) > 2 { why = "it changed after it was moved" }
            else if (try? fm.createDirectory(atPath: (c.from as NSString).deletingLastPathComponent, withIntermediateDirectories: true)) == nil { why = "its folder could not be made again" }
            if why == nil {
                for n in g.idx {
                    let s = run.steps[n]
                    guard Self.isFile(s.to), !Self.exists(s.from) else { continue }
                    do { try fm.moveItem(atPath: s.to, toPath: s.from); run.steps[n].done = false }
                    catch { if n == head { why = "it could not be moved back" } }
                }
            }
            answers.append(Answer(from: c.from, to: c.to, ok: why == nil, why: why ?? ""))
        }
        // the folders this run made, innermost first, only when nothing is in them (Finder's .DS_Store aside)
        for d in run.made.reversed() {
            guard let names = try? fm.contentsOfDirectory(atPath: d), names.allSatisfy({ $0 == ".DS_Store" }) else { continue }
            names.forEach { try? fm.removeItem(atPath: (d as NSString).appendingPathComponent($0)) }
            try? fm.removeItem(atPath: d)
        }
        run.undone = !run.steps.contains(where: \.done)
        all[at] = run
        save(all)
        return answers
    }
}
