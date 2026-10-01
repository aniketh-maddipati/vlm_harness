import Foundation

// WP-8. What a shoot's file holds, its version, and how an older file is read (migration).

/// State that must survive a relaunch but has no field in `Snapshot` yet (CONTRACT-REQUESTS/WP8.md).
/// It travels in the same file as the snapshot, so one atomic write covers both.
public struct SnapshotExtras: Codable, Sendable, Equatable {
    /// Edit's own position (`AppModel.editCur`); `Snapshot.cur` is Cull's.
    public var editCur: String?
    public init(editCur: String? = nil) { self.editCur = editCur }
}

/// A store that keeps `SnapshotExtras` next to each snapshot. Both of the package's stores do;
/// a store that doesn't loses only Edit's position (it lands on the first keeper).
public protocol SnapshotExtrasStore: PersistenceStore {
    func save(_ snapshot: Snapshot, extras: SnapshotExtras) throws
    func loadWithExtras(shootKey: String) throws -> (snapshot: Snapshot, extras: SnapshotExtras)?
}

/// One shoot's file: `{"v":1,"snapshot":{…},"extras":{…}}`.
public struct SnapshotFile: Codable, Sendable, Equatable {
    /// The format this build writes. Bump it with a step in `migrations`.
    public static let version = 1

    public var v: Int
    public var snapshot: Snapshot
    public var extras: SnapshotExtras?

    public init(snapshot: Snapshot, extras: SnapshotExtras? = nil) { v = Self.version; self.snapshot = snapshot; self.extras = extras }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// Reads a file of this version or any earlier one. A file from a newer build is read as far
    /// as this build understands it (`v` stays the file's, so the caller can keep a copy before
    /// it writes over it). `shootKey` fills the key in for files old enough not to carry one.
    public static func decode(_ data: Data, shootKey: String? = nil) throws -> SnapshotFile {
        if let f = try? JSONDecoder().decode(SnapshotFile.self, from: data), f.v >= version { return f }
        guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PersistenceError.unreadable("not a JSON object")
        }
        var v = (obj["v"] as? Int) ?? 0
        guard v < version else { throw PersistenceError.unreadable("version \(v) file doesn’t decode") }
        while v < version {
            guard let step = migrations[v] else { throw PersistenceError.unreadable("no migration from version \(v)") }
            obj = try step(obj, shootKey); v += 1
        }
        obj["v"] = version
        do { return try JSONDecoder().decode(SnapshotFile.self, from: JSONSerialization.data(withJSONObject: obj)) }
        catch { throw PersistenceError.unreadable("after migration: \(error)") }
    }

    /// The migration hook: `migrations[n]` turns a version-n file (as a JSON object) into version
    /// n + 1. Nothing a step doesn't understand is dropped before the next one sees it.
    static let migrations: [Int: ([String: Any], String?) throws -> [String: Any]] = [0: fromV0]

    /// Version 0: no `v`. Either a bare snapshot (the fields at the top level, any of them
    /// missing) or the prototype's shape (`done` as `{key: true}`, no step). Missing fields get
    /// the defaults of `Snapshot.init`; decisions, looks and tags are carried over as they are.
    private static func fromV0(_ obj: [String: Any], _ shootKey: String?) throws -> [String: Any] {
        var s = (obj["snapshot"] as? [String: Any]) ?? obj
        let extras = (obj["extras"] as? [String: Any]) ?? (s["editCur"] as? String).map { ["editCur": $0] }
        guard let key = (s["shootKey"] as? String) ?? shootKey else { throw PersistenceError.unreadable("version 0 file without a shoot") }
        s["shootKey"] = key
        if let done = s["done"] as? [String: Any] { s["done"] = done.filter { ($0.value as? Bool) != false }.keys.sorted() }
        let defaults: [String: Any] = ["step": Step.open.rawValue, "copied": 0, "keep": [String: Bool](), "looks": [String: Any](),
                                       "tags": [String: String](), "done": [String](), "fmt": SaveFormat.xmp.rawValue,
                                       "withEdits": true, "photoCount": 0, "revision": 0, "writer": ""]
        for (k, d) in defaults where s[k] == nil || s[k] is NSNull { s[k] = d }
        var out: [String: Any] = ["snapshot": s]
        if let extras { out["extras"] = extras }
        return out
    }
}

/// The "last shoot" pointer: `{"v":1,"shootKey":"…"}`.
struct LastPointer: Codable { var v = SnapshotFile.version; var shootKey: String }

// MARK: the Sets-era session (the web UI's `shoots/<id>/session.json`)

/// What can be carried from a Sets session into a snapshot without guessing: the decisions and
/// Cull's place. The session is keyed by path inside the opened folder, which is `Photo.rel`.
/// Its looks are look *strings* in the Sets pipeline's units (`Lumina/Sets/Look/LookString.swift`);
/// turning them into this UI's `Look` values needs that parser and a units table, so they are
/// left alone here (the session file itself is never changed or removed).
public enum SetsSessionMigration {
    /// Nil when `data` isn't a Sets session or nothing in it matches `shoot`.
    public static func snapshot(fromSession data: Data, shoot: Shoot) -> Snapshot? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let marks = obj["marks"] as? [String: Any] else { return nil }
        var idOf: [String: String] = [:]
        for p in shoot.photos { if let rel = p.rel { idOf[rel] = p.id } }
        var keep: [String: Bool] = [:]
        for (path, mark) in marks {
            guard let id = idOf[path], let m = mark as? String else { continue }
            if m == "keep" { keep[id] = true } else if m == "out" { keep[id] = false }
        }
        let cur = (obj["cur"] as? String).flatMap { idOf[$0] }
        guard !keep.isEmpty || cur != nil else { return nil }
        return Snapshot(shootKey: shoot.key, step: .cull, cur: cur, copied: shoot.photos.count, keep: keep,
                        folderName: shoot.local ? shoot.name : nil, photoCount: shoot.photos.count, writer: "sets-session")
    }
}
