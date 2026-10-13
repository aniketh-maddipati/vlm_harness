import Foundation

/// Skim's saved covers and first measures (STORAGE.md item 2), in the app's container: `skim/covers/`.
/// The page keeps the same records in IndexedDB in a browser; the app's web view is non-persistent, so here
/// the page sends them over (`skimCoverPut`) and asks for them back when the same clips are opened
/// (`skimCoverGet`), and the storage line reads the sizes (`skimCoverStat`) and clears shoots (`skimCoverDrop`).
///
/// One folder per shoot, named by a hash of the page's shoot key: `shoot.json` (the key, name, clip count,
/// when it was last opened, and each clip's record as the page's JSON text) and one `<hash>.jpg` per clip
/// (its cover, the JPEG the page made). Marks are never here.
///
/// Bounded: keys at most 512 characters, a record at most 16 KB, a cover at most 1 MB, at most 4,000 clips a
/// shoot, and `cap` bytes in all: over it, the shoot opened longest ago goes first, never the one being
/// written. Writes are atomic (a temp file, then a rename). Nothing outside `skim/covers/` is touched.
nonisolated struct SkimCovers: Sendable {
    static let maxKey = 512
    static let maxMeta = 16 << 10
    static let maxCover = 1 << 20
    static let maxClips = 4000
    static let defaultCap = 200_000_000

    let dir: URL
    let cap: Int

    init(dir: URL, cap: Int = SkimCovers.defaultCap) { self.dir = dir; self.cap = cap }

    struct Shoot: Codable, Equatable {
        var k: String
        var name: String
        var n: Int
        var at: Double
        var recs: [String: String]
    }

    /// What one shoot holds on disk.
    struct Held: Equatable { var k: String; var name: String; var at: Double; var bytes: Int; var n: Int }

    static func valid(key: String) -> Bool { !key.isEmpty && key.count <= maxKey && !key.contains("\0") }

    /// A file name for a key: FNV-1a 64, hex. Collisions only cost a cover (the record carries its key).
    static func hashName(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func folder(_ shoot: String) -> URL { dir.appendingPathComponent(Self.hashName(shoot), isDirectory: true) }

    func load(_ folder: URL) -> Shoot? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("shoot.json")), d.count <= Self.maxClips * (Self.maxMeta + Self.maxKey) else { return nil }
        return try? JSONDecoder().decode(Shoot.self, from: d)
    }

    func shoots() -> [(URL, Shoot)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { n in let u = dir.appendingPathComponent(n, isDirectory: true); return load(u).map { (u, $0) } }
    }

    /// The records and covers for the keys asked for: key → ["meta": the page's JSON, "cover": base64 JPEG].
    func get(_ keys: [String]) -> [String: [String: String]] {
        let want = Set(keys.filter(Self.valid))
        var out: [String: [String: String]] = [:]
        guard !want.isEmpty else { return out }
        for (u, s) in shoots() {
            for (k, meta) in s.recs where want.contains(k) && out[k] == nil {
                guard let jpg = try? Data(contentsOf: u.appendingPathComponent(Self.hashName(k) + ".jpg")), jpg.count <= Self.maxCover else { continue }
                out[k] = ["meta": meta, "cover": jpg.base64EncodedString()]
            }
        }
        return out
    }

    /// Marks a shoot as just opened (creates it with no clips when new).
    @discardableResult
    func touch(k: String, name: String, n: Int, now: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
        guard Self.valid(key: k) else { return false }
        let f = folder(k)
        var s = load(f) ?? Shoot(k: k, name: String(name.prefix(Self.maxKey)), n: n, at: now, recs: [:])
        s.name = String(name.prefix(Self.maxKey)); s.n = n; s.at = now
        return write(s, to: f)
    }

    enum PutResult: String { case saved, refused, full }

    /// Adds records to a shoot. `recs` are ["k": key, "meta": JSON text, "cover": base64 JPEG]; a record that
    /// breaks a bound is left out. `full` when the disk refused the write; the store is then as it was.
    func put(k: String, name: String, n: Int, recs: [[String: String]], now: Double = Date().timeIntervalSince1970 * 1000) -> PutResult {
        guard Self.valid(key: k) else { return .refused }
        let f = folder(k), fm = FileManager.default
        var s = load(f) ?? Shoot(k: k, name: String(name.prefix(Self.maxKey)), n: n, at: now, recs: [:])
        s.name = String(name.prefix(Self.maxKey)); s.n = n; s.at = now
        do {
            try fm.createDirectory(at: f, withIntermediateDirectories: true)
            for r in recs {
                guard let ck = r["k"], Self.valid(key: ck), let meta = r["meta"], meta.utf8.count <= Self.maxMeta,
                      let b64 = r["cover"], let jpg = Data(base64Encoded: b64), !jpg.isEmpty, jpg.count <= Self.maxCover,
                      s.recs[ck] != nil || s.recs.count < Self.maxClips else { continue }
                try jpg.write(to: f.appendingPathComponent(Self.hashName(ck) + ".jpg"), options: .atomic)
                s.recs[ck] = meta
            }
            guard write(s, to: f) else { return .full }
        } catch {
            return .full
        }
        let st = stat()
        let out = Self.evictOrder(st.shoots, keep: k, bytes: st.bytes, cap: cap)
        if !out.isEmpty { drop(out) }
        return .saved
    }

    /// Every shoot held and the bytes it takes, from the files themselves.
    func stat() -> (bytes: Int, shoots: [Held]) {
        var all: [Held] = [], tot = 0
        for (u, s) in shoots() {
            var b = 0
            if let names = try? FileManager.default.contentsOfDirectory(atPath: u.path) {
                for n in names { b += (try? FileManager.default.attributesOfItem(atPath: u.appendingPathComponent(n).path)[.size] as? Int) ?? 0 }
            }
            all.append(Held(k: s.k, name: s.name, at: s.at, bytes: b, n: s.recs.count)); tot += b
        }
        return (tot, all)
    }

    /// Removes shoots by key: their folder under `skim/covers/` and nothing else.
    @discardableResult
    func drop(_ keys: [String]) -> Bool {
        var ok = true
        for k in keys where Self.valid(key: k) {
            let f = folder(k)
            guard f.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL else { ok = false; continue }
            if FileManager.default.fileExists(atPath: f.path) { do { try FileManager.default.removeItem(at: f) } catch { ok = false } }
        }
        return ok
    }

    /// The page's own rule (`Component.evictOrder`): oldest opened first, never `keep`, until the rest fits.
    static func evictOrder(_ shoots: [Held], keep: String, bytes: Int, cap: Int) -> [String] {
        var out: [String] = [], left = bytes
        for s in shoots.filter({ $0.k != keep }).sorted(by: { $0.at < $1.at }) {
            if left <= cap { break }
            out.append(s.k); left -= s.bytes
        }
        return out
    }

    private func write(_ s: Shoot, to f: URL) -> Bool {
        guard let d = try? JSONEncoder().encode(s) else { return false }
        do {
            try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            try d.write(to: f.appendingPathComponent("shoot.json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
