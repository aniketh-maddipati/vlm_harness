import Foundation

/// Per-shoot memory in Application Support (README "What the prototype environment does for you":
/// session memory → per-shoot database, removable). One folder per shoot:
///   shoots/<id>/session.json   the page's decisions, keyed by file path (not by position)
///   shoots/<id>/Lumina.json    the shoot header: the RAW decoder map per body and the pinned
///                              decoder version (LookShootHeader, RAW 9 §1 and §7)
///   shoots/index.json          recent shoots for the Open screen, newest first
/// A store file this build can't read whole (damaged, or a session from a newer format) is moved
/// aside before it would be replaced, never written over: `index.damaged.json`,
/// `<id>/session.damaged.json`, `<id>/session.v<N>.json` (release task R8).
/// Only Lumina's own files live here; RAWs and sidecars are never touched.
nonisolated struct SetsShootStore {
    struct Shoot: Codable, Equatable {
        var id: String
        var title: String
        var path: String
        var volumeUUID: String?
        var photos: Int
        var firstCapture: String      // "YYYY:MM:DD HH:MM:SS" from EXIF, may be empty
        var opened: Date
        /// The security-scoped bookmark: the only way back into the folder after a relaunch in the
        /// App Sandbox (`SetsAccess.reopen`). `path` is kept for display only.
        var bookmark: Data?
        /// For the Open screen's recent cards (the page's own recents shape): rows seen, keepers,
        /// the last photo. Updated with every saved session; absent in older indexes.
        var seen: Int?
        var keepers: Int?
        var last: String?
        /// `id(for:)` of where the folder is now, when it differs from `id`: the folder was renamed
        /// or moved since it was first opened and the reopen followed it (its bookmark did). Nil
        /// (older indexes, never moved) means the folder is where `id` says.
        var place: String? = nil

        var currentPlace: String { place ?? id }
    }

    /// The longest strings the index keeps. A capture date is 19 characters; a title or a file's
    /// name is at most 255 (a file name's limit). `firstCapture` and `last` come from the page
    /// (`shootOpened`, `saveSession`'s summary): a 10 MB one would be rewritten with the index on
    /// every open and every saved session (threat model T5).
    enum Cap {
        static let date = 32
        static let name = 255
    }

    static func capped(_ s: String, _ n: Int) -> String { String(s.prefix(n)) }

    /// A shoot as the index stores it: every string the page or a folder's name supplies, inside `Cap`.
    static func bounded(_ shoot: Shoot) -> Shoot {
        var s = shoot
        s.title = capped(s.title, Cap.name)
        s.firstCapture = capped(s.firstCapture, Cap.date)
        s.last = s.last.map { capped($0, Cap.name) }
        return s
    }

    let root: URL

    init(supportDir: URL) { root = supportDir.appendingPathComponent("shoots", isDirectory: true) }

    /// Stable id for a folder: its volume (so a card is the same card under any mount name) plus
    /// its path inside that volume.
    static func id(for folder: URL) -> String {
        let vals = try? folder.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeURLKey])
        var rel = folder.standardizedFileURL.path
        if let vol = vals?.volume?.standardizedFileURL.path, vol != "/", rel.hasPrefix(vol) { rel = String(rel.dropFirst(vol.count)) }
        return String(SetsFileOps.sha256(Data(((vals?.volumeUUIDString ?? "") + "|" + rel).utf8)).prefix(16))
    }

    /// An id is exactly what `id(for:)` makes: 16 lowercase hex characters. Ids also come from the
    /// page (saveSession, workingFiles, removeShoot) and name a folder under `root`, so anything
    /// else ("..", a path, an empty string) is refused before a path is built from it.
    static func isID(_ id: String) -> Bool {
        id.utf8.count == 16 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// The one place a shoot's folder is named. Writers pass the refusal on; readers answer
    /// nil / empty / 0.
    private func dir(_ id: String) throws -> URL {
        guard Self.isID(id) else { throw SetsFileOps.Failure("not a shoot id") }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    /// The recent shoots, newest first. An entry that does not decode is left out; the rest stay.
    func index() -> [Shoot] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("index.json")) else { return [] }
        return Self.decodeIndex(data).shoots.sorted { $0.opened > $1.opened }
    }

    /// The entries of an index, and whether every entry decoded (`whole`). Not a list: none, not whole.
    static func decodeIndex(_ data: Data) -> (shoots: [Shoot], whole: Bool) {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let entries = try? dec.decode([ImportEntry].self, from: data) else { return ([], false) }
        let shoots = entries.compactMap(\.shoot)
        return (shoots, shoots.count == entries.count)
    }

    /// The session format a session's JSON names (`v`, written by plumbing.js's `snapshot`): 0 for
    /// an object without one, nil when the bytes are not a JSON object.
    static func sessionVersion(_ data: Data) -> Int? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (obj["v"] as? NSNumber)?.intValue ?? 0
    }

    /// Moves the file at `url` to `name` beside it (replacing an earlier copy of that name) unless
    /// `readable` accepts its bytes. Nothing there, or an empty file, is left as it is.
    private func setAside(_ url: URL, as name: String, unless readable: (Data) -> Bool) throws {
        guard let data = try? Data(contentsOf: url), !data.isEmpty, !readable(data) else { return }
        let aside = url.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: url, to: aside)
    }

    /// The shoot for a folder at `place` (`id(for:)` of it): the one that is there now (opened
    /// there, or followed there by a reopen), else a new one. A new shoot normally takes `place` as
    /// its id; but when the shoot first opened at `place` has since moved away, the folder now at
    /// its old place is another one and gets an id of its own, so the two never share a session.
    func shootID(at place: String) -> String {
        let all = index()
        if let here = all.first(where: { $0.currentPlace == place }) { return here.id }
        guard all.contains(where: { $0.id == place }) else { return place }
        var n = 1
        while true {
            let c = String(SetsFileOps.sha256(Data("\(place)|\(n)".utf8)).prefix(16))
            if !all.contains(where: { $0.id == c }), !FileManager.default.fileExists(atPath: root.appendingPathComponent(c).path) { return c }
            n += 1
        }
    }

    /// A shoot opened again: its fields replace the old entry's, except the Open screen's counts
    /// and the bookmark, which stay when the new entry has none (a reopen keeps the bookmark it
    /// came through; only a fresh grant or a renewal replaces it).
    func upsert(_ shoot: Shoot) throws {
        let all = index()
        var shoot = shoot
        if let old = all.first(where: { $0.id == shoot.id }) {
            shoot.seen = shoot.seen ?? old.seen; shoot.keepers = shoot.keepers ?? old.keepers; shoot.last = shoot.last ?? old.last
            shoot.bookmark = shoot.bookmark ?? old.bookmark
        }
        if shoot.place == shoot.id { shoot.place = nil }
        var list = all.filter { $0.id != shoot.id }
        list.insert(shoot, at: 0)
        try write(list)
    }

    func session(_ id: String) -> Data? {
        try? Data(contentsOf: dir(id).appendingPathComponent("session.json"))
    }

    /// The page's session for a shoot. The one it replaces is kept aside when this build could not
    /// have read it: not a JSON object (`session.damaged.json`; the page started empty), or a newer
    /// format than the one being written (`session.v<N>.json`: a newer build wrote it, so this one
    /// understood only part of it).
    func saveSession(_ id: String, _ json: Data) throws {
        let url = try dir(id).appendingPathComponent("session.json")
        let incoming = Self.sessionVersion(json) ?? 0
        try setAside(url, as: "session.damaged.json") { Self.sessionVersion($0) != nil }
        if let old = try? Data(contentsOf: url), let v = Self.sessionVersion(old), v > incoming {
            try setAside(url, as: "session.v\(v).json") { _ in false }
        }
        try SetsFileOps.replaceOwn(json, at: url)
    }

    /// The shoot header (`Lumina.json`), or an empty one.
    func header(_ id: String) -> LookShootHeader {
        guard let data = try? Data(contentsOf: dir(id).appendingPathComponent(LookShootHeader.fileName)),
              let h = try? LookShootHeader.decode(data) else { return LookShootHeader() }
        return h
    }

    func saveHeader(_ id: String, _ header: LookShootHeader) throws {
        try SetsFileOps.replaceOwn(try header.encoded(), at: try dir(id).appendingPathComponent(LookShootHeader.fileName))
    }

    /// The numbers the Open screen shows for a shoot. Written only when they change.
    func saveSummary(_ id: String, photos: Int?, seen: Int?, keepers: Int?, last: String?) throws {
        _ = try dir(id)
        var list = index()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let before = list[i]
        if let photos { list[i].photos = photos }
        list[i].seen = seen ?? list[i].seen
        list[i].keepers = keepers ?? list[i].keepers
        list[i].last = last ?? list[i].last
        list[i] = Self.bounded(list[i])                    // before the comparison: an over-long `last` is not a change every time
        guard list[i] != before else { return }
        try write(list)
    }

    /// A stale bookmark resolved and made again (`SetsAccess.reopen`): the new one, and where the
    /// folder is now, replace the old ones. Nothing else changes; an unknown id is ignored.
    func renewBookmark(_ id: String, _ bookmark: Data, path: String, place: String) throws {
        _ = try dir(id)
        var list = index()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].bookmark = bookmark
        list[i].path = path
        list[i].place = place == id ? nil : place
        try write(list)
    }

    /// The one place the index is written: every entry bounded (`Cap`), whoever made it.
    /// An index that did not decode whole is kept as `index.damaged.json` first: `list` was made
    /// without the entries it lost.
    private func write(_ list: [Shoot]) throws {
        try setAside(root.appendingPathComponent("index.json"), as: "index.damaged.json") { Self.decodeIndex($0).whole }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list.map(Self.bounded)), at: root.appendingPathComponent("index.json"))
    }

    /// "Remove Lumina's working files" for one shoot: its session and index entry. Never RAWs or .xmp.
    /// A refused id throws before anything is removed or the index is rewritten.
    func remove(_ id: String) throws {
        let folder = try dir(id)
        try? FileManager.default.removeItem(at: folder)
        try write(index().filter { $0.id != id })
    }

    func bytes(_ id: String) -> Int64 {
        guard let folder = try? dir(id) else { return 0 }
        let files = (FileManager.default.enumerator(at: folder,includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: Sessions from before the sandbox (release task R1e)
    //
    // Until the app was sandboxed its store was ~/Library/Application Support/Lumina. A sandboxed
    // build keeps its own inside its container and cannot read the old one, so the decisions made
    // with the earlier build look gone although they are on disk. `importStore` copies them over
    // once the user has picked the old folder in a panel (SetsRootView). A shoot's id comes from
    // its volume and path, so an imported session is found as soon as the same folder is opened.

    /// What an import leaves alone, and why.
    nonisolated enum ImportSkip: String, Hashable, Sendable {
        case notAnID        // a folder in the old `shoots/` whose name is not a shoot id
        case link           // a shoot folder, or its session.json, that is a symbolic link
        case noSession      // a shoot folder without a session.json (nothing was decided there)
        case tooBig         // a session over `importSessionBytes`
        case unreadable     // a session that is not a JSON object in UTF-8
        case header         // a Lumina.json that is a link, too big or does not decode (its session still comes)
        case index          // the old index.json: a link, too big, or not a list
        case entry          // one entry of the old index: fields missing, or its id is not an id
    }

    nonisolated struct ImportResult: Equatable, Sendable {
        /// Sessions, headers and recents written into this store.
        var sessions = 0
        var headers = 0
        var recents = 0
        /// Shoots this store already has a session for: the same bytes, or other ones (kept).
        var alreadyHere = 0
        var keptNewer = 0
        var skipped: [ImportSkip: Int] = [:]

        var changed: Bool { sessions + headers + recents > 0 }
        var skippedTotal: Int { skipped.values.reduce(0, +) }

        /// One line for the page's status line (`__lumina.say`), in its own style.
        var statusLine: String {
            var parts: [String]
            if sessions > 0 {
                parts = [sessions == 1 ? "1 session brought over" : "\(sessions) sessions brought over"]
                parts.append(sessions == 1 ? "open its folder to continue it" : "open a folder to continue it")
            } else if alreadyHere + keptNewer > 0 {
                parts = ["earlier sessions are already here"]
            } else {
                parts = ["no earlier sessions found"]
            }
            if sessions > 0, keptNewer > 0 { parts.append("\(keptNewer) kept as \(keptNewer == 1 ? "it is" : "they are") here") }
            if skippedTotal > 0 { parts.append("\(skippedTotal) skipped") }
            return parts.joined(separator: " · ")
        }
    }

    /// The largest session an import takes: what the bridge lets the page store (`SetsBridge.maxSessionBytes`).
    static let importSessionBytes = 16 << 20
    /// The largest Lumina.json an import takes (a real one is a few hundred bytes).
    static let importHeaderBytes = 1 << 20
    /// The longest strings an imported index entry keeps: a capture date is 19 characters, a title
    /// or a file's name at most 255 (a file name's limit), a path 4096, a volume UUID 36.
    static let importDateCap = 32, importNameCap = 255, importPathCap = 4096, importVolumeCap = 64

    /// The marker that the question about earlier sessions was answered (beside `shoots/`).
    var importAskedURL: URL { root.deletingLastPathComponent().appendingPathComponent("import-asked") }

    /// Launch asks about earlier sessions only while this store has never been used: no index
    /// yet, and the question not answered before.
    var offersImport: Bool {
        !FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path)
            && !FileManager.default.fileExists(atPath: importAskedURL.path)
    }

    func markImportAsked() throws { try SetsFileOps.replaceOwn(Data("asked\n".utf8), at: importAskedURL) }

    /// The earlier store in a folder picked in the panel: the folder itself ("…/Application
    /// Support/Lumina") or, one level up, its "Lumina". It must hold `shoots/index.json` as plain
    /// files and folders (no links). Nil otherwise.
    static func earlierStore(in picked: URL) -> URL? {
        for c in [picked, picked.appendingPathComponent("Lumina", isDirectory: true)] {
            let shoots = c.appendingPathComponent("shoots", isDirectory: true)
            if importKind(shoots) == .typeDirectory, importKind(shoots.appendingPathComponent("index.json")) == .typeRegular { return c }
        }
        return nil
    }

    /// What is at `url`, without following a link there (lstat).
    private static func importKind(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    /// A plain file's bytes when it is one and at most `limit` long. Nil otherwise.
    private static func importBytes(_ url: URL, limit: Int) -> Data? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), a[.type] as? FileAttributeType == .typeRegular,
              let size = (a[.size] as? NSNumber)?.int64Value, size <= Int64(limit),
              let data = try? Data(contentsOf: url), data.count <= limit else { return nil }
        return data
    }

    /// One entry of the old index, or nil when it does not decode: one bad entry does not cost the rest.
    private nonisolated struct ImportEntry: Decodable {
        let shoot: Shoot?
        init(from decoder: Decoder) throws { shoot = try? Shoot(from: decoder) }
    }

    /// Brings the sessions of an earlier store (`oldSupport`, the folder that holds `shoots/`)
    /// into this one. The old folder is only read: nothing in it is changed, moved or removed.
    ///
    /// The rule for a shoot that is in both stores: **this store wins**. A shoot that already has a
    /// session here keeps it, and its Lumina.json, untouched (counted as `alreadyHere` when the
    /// bytes are equal, `keptNewer` when they differ); an index entry that is already here keeps
    /// every field, its bookmark included. So an import never replaces work done since, and a
    /// second import changes nothing.
    ///
    /// For every other shoot folder with a valid id: `session.json` is copied byte for byte, and
    /// `Lumina.json` when this store has none for it. Index entries come without their bookmarks
    /// (made outside the sandbox, they do not resolve inside it; opening the folder once makes a
    /// new one), with their strings capped, and the merged index is newest first with one entry
    /// per id. Skipped and counted: names that are not ids, links, folders without a session,
    /// sessions over the cap or that are not a JSON object, a header or an index that does not
    /// decode. Export journals (`exports/`) and the legacy `bookmarks/` are not brought over.
    ///
    /// Throws when there is no `shoots/index.json` there, when the folder is this store, or when
    /// a write fails (what was written before stays, and running it again finishes the job).
    func importStore(from oldSupport: URL) throws -> ImportResult {
        let fm = FileManager.default
        let old = oldSupport.appendingPathComponent("shoots", isDirectory: true)
        guard Self.importKind(old) == .typeDirectory, Self.importKind(old.appendingPathComponent("index.json")) == .typeRegular else {
            throw SetsFileOps.Failure("no shoots/index.json there")
        }
        guard old.standardizedFileURL.resolvingSymlinksInPath().path != root.standardizedFileURL.resolvingSymlinksInPath().path else {
            throw SetsFileOps.Failure("that folder is this store")
        }
        var result = ImportResult()
        func skip(_ why: ImportSkip) { result.skipped[why, default: 0] += 1 }

        for name in ((try? fm.contentsOfDirectory(atPath: old.path)) ?? []).sorted() where name != "index.json" && !name.hasPrefix(".") {
            guard Self.isID(name) else { skip(.notAnID); continue }
            let from = old.appendingPathComponent(name, isDirectory: true)
            let sessionURL = from.appendingPathComponent("session.json")
            let folder = Self.importKind(from), file = folder == .typeDirectory ? Self.importKind(sessionURL) : nil
            guard folder != .typeSymbolicLink, file != .typeSymbolicLink else { skip(.link); continue }
            guard folder == .typeDirectory, file == .typeRegular else { skip(.noSession); continue }
            guard let data = Self.importBytes(sessionURL, limit: Self.importSessionBytes) else { skip(.tooBig); continue }
            guard String(data: data, encoding: .utf8) != nil, (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { skip(.unreadable); continue }
            if let here = session(name) {
                if here == data { result.alreadyHere += 1 } else { result.keptNewer += 1 }
                continue
            }
            // The header first: a session without its decoder pin would be pinned again on open.
            let headerURL = from.appendingPathComponent(LookShootHeader.fileName)
            if Self.importKind(headerURL) != nil, !fm.fileExists(atPath: root.appendingPathComponent(name).appendingPathComponent(LookShootHeader.fileName).path) {
                if let h = Self.importBytes(headerURL, limit: Self.importHeaderBytes), (try? LookShootHeader.decode(h)) != nil {
                    try SetsFileOps.replaceOwn(h, at: try dir(name).appendingPathComponent(LookShootHeader.fileName))
                    result.headers += 1
                } else { skip(.header) }
            }
            try saveSession(name, data)
            result.sessions += 1
        }

        // The index: entries this store does not have yet, without their bookmarks.
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let raw = Self.importBytes(old.appendingPathComponent("index.json"), limit: Self.importSessionBytes),
              let entries = try? dec.decode([ImportEntry].self, from: raw) else { skip(.index); return result }
        let mine = index()
        var known = Set(mine.map(\.id)), added: [Shoot] = []
        for e in entries {
            guard var s = e.shoot, Self.isID(s.id) else { skip(.entry); continue }
            guard known.insert(s.id).inserted else { continue }
            s.bookmark = nil
            s.title = String(s.title.prefix(Self.importNameCap))
            s.path = String(s.path.prefix(Self.importPathCap))
            s.volumeUUID = s.volumeUUID.map { String($0.prefix(Self.importVolumeCap)) }
            s.firstCapture = String(s.firstCapture.prefix(Self.importDateCap))
            s.last = s.last.map { String($0.prefix(Self.importNameCap)) }
            s.photos = max(0, s.photos); s.seen = s.seen.map { max(0, $0) }; s.keepers = s.keepers.map { max(0, $0) }
            if let p = s.place, !Self.isID(p) || p == s.id { s.place = nil }
            added.append(s)
        }
        guard !added.isEmpty else { return result }
        try write((mine + added).sorted { $0.opened != $1.opened ? $0.opened > $1.opened : $0.id < $1.id })
        result.recents = added.count
        return result
    }
}
