import Foundation

/// Skim's note of the files its Export saved (`skim/exports.json`): each .fcpxml and cut list, where it went, what it was
/// when written (size and date) and which clips it holds with their marks, so the workshop can say which files are
/// current, which are out of date, which a newer save replaced and which are gone. Only files Skim wrote are on it, and
/// only those, unchanged since, may go to the Trash from it (with Put back); nothing is deleted or written over, and a
/// file on the list is never touched by Forget. Foundation only (the bookmarks are resolved in SetsBridge).
nonisolated struct SkimLedger: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var id: String
        var path: String
        /// "fcpxml" or "cut".
        var kind: String
        /// The shoot's key, as the page keeps it.
        var shoot: String
        var at: Double
        var bytes: Int64
        var mtime: Double
        /// The clips the file holds, by their file's path, with the mark each had ("keep", "maybe", "cut", or "").
        var clips: [String: String]
        /// What the page chose that decides which clips go in ("maybes", "all").
        var opts: [String: Bool]
        /// A security-scoped bookmark of the file, so it is found after a quit and after it is moved or renamed.
        var bookmark: Data?
        /// Where it went in the Trash, while it is there.
        var trashed: String?
    }

    /// An entry as it is on disk now.
    enum State: String, Sendable { case here, changed, gone, unknown, trashed }

    static let maxEntries = 500, maxClips = 5000
    static let kinds: Set<String> = ["fcpxml", "cut"]
    let file: URL
    /// Moves one file to the Trash and answers where it went (`FileManager.trashItem` in the app).
    let trash: @Sendable (URL) throws -> URL

    init(file: URL, trash: @escaping @Sendable (URL) throws -> URL = SkimTrash.systemTrash) { self.file = file; self.trash = trash }

    func all() -> [Entry] {
        guard let d = try? Data(contentsOf: file), d.count <= 64 << 20 else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
    }

    @discardableResult
    private func save(_ e: [Entry]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(e.suffix(Self.maxEntries))).write(to: file, options: .atomic)
            return true
        } catch { return false }
    }

    private func change(_ id: String, _ f: (inout Entry) -> Void) -> Entry? {
        var es = all()
        guard let i = es.firstIndex(where: { $0.id == id }) else { return nil }
        f(&es[i])
        return save(es) ? es[i] : nil
    }

    func entry(_ id: String) -> Entry? { all().first { $0.id == id } }

    /// This shoot's files, newest first.
    func entries(shoot: String) -> [Entry] { all().filter { $0.shoot == shoot }.sorted { $0.at > $1.at } }

    /// Notes a file Export just saved and read back.
    @discardableResult
    func record(path: String, kind: String, shoot: String, clips: [String: String], opts: [String: Bool], bookmark: Data?,
                now: Double = Date().timeIntervalSince1970 * 1000) -> Entry? {
        guard Self.kinds.contains(kind), !shoot.isEmpty, clips.count <= Self.maxClips, SkimArrange.isFile(path) else { return nil }
        let e = Entry(id: String(format: "%.0f", now) + "-" + String(UUID().uuidString.prefix(6)), path: path, kind: kind, shoot: shoot, at: now,
                      bytes: SkimArrange.size(path), mtime: SkimArrange.mtime(path), clips: clips.filter { ["keep", "maybe", "cut", ""].contains($0.value) },
                      opts: opts, bookmark: bookmark, trashed: nil)
        var es = all().filter { $0.path != path }   // a path saved again (after the old one went) is one file
        es.append(e)
        return save(es) ? e : nil
    }

    /// The entry's file as it is now, at `url` (where its bookmark says it is; nil when Skim may not look).
    static func state(_ e: Entry, at url: URL?) -> State {
        if e.trashed != nil { return .trashed }
        guard let url else { return .unknown }
        guard SkimArrange.isFile(url.path) else { return .gone }
        return SkimArrange.size(url.path) == e.bytes && abs(SkimArrange.mtime(url.path) - e.mtime) <= 2 ? .here : .changed
    }

    /// A file found somewhere else through its bookmark (moved or renamed in Finder): the note follows it.
    func moved(_ id: String, to path: String) { _ = change(id) { $0.path = path } }

    /// Takes the file off the list. The file itself is not touched.
    @discardableResult
    func forget(_ id: String) -> Bool {
        let es = all(), left = es.filter { $0.id != id }
        return left.count < es.count && save(left)
    }

    /// Moves the file to the Trash: only one Skim wrote and nothing changed since, at `url`.
    func moveToTrash(_ id: String, at url: URL?) -> (ok: Bool, why: String) {
        guard let e = entry(id) else { return (false, "Lumina has no note of that file.") }
        switch Self.state(e, at: url) {
        case .trashed: return (false, "It is already in the Trash.")
        case .unknown: return (false, "Lumina has no access to that folder any more.")
        case .gone: return (false, "It is not there any more.")
        case .changed: return (false, "It changed after Lumina saved it, so Lumina leaves it alone.")
        case .here: break
        }
        guard let url else { return (false, "Lumina has no access to that folder any more.") }
        do {
            let to = try trash(url)
            _ = change(id) { $0.trashed = to.path; $0.path = url.path }
            return (true, "")
        } catch { return (false, "It could not be moved to the Trash.") }
    }

    /// Put back: from the Trash to where it was, while it is still in the Trash and its old place is free.
    func putBack(_ id: String) -> (ok: Bool, why: String) {
        guard let e = entry(id), let t = e.trashed else { return (false, "It is not in the Trash.") }
        guard SkimArrange.isFile(t) else { return (false, "It is not in the Trash any more.") }
        guard !SkimArrange.exists(e.path) else { return (false, "A file is already where it was.") }
        do {
            try FileManager.default.moveItem(atPath: t, toPath: e.path)
            _ = change(id) { $0.trashed = nil }
            return (true, "")
        } catch { return (false, "It could not be put back.") }
    }

    /// One entry for the page, with its state.
    static func json(_ e: Entry, state: State) -> [String: Any] {
        ["id": e.id, "path": e.path, "name": (e.path as NSString).lastPathComponent, "folder": (e.path as NSString).deletingLastPathComponent,
         "kind": e.kind, "at": e.at, "bytes": e.bytes, "clips": e.clips, "opts": e.opts, "state": state.rawValue]
    }
}
