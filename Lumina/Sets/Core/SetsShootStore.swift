import Foundation

/// Per-shoot memory in Application Support (README "What the prototype environment does for you":
/// session memory → per-shoot database, removable). One folder per shoot:
///   shoots/<id>/session.json   the page's decisions, keyed by file path (not by position)
///   shoots/<id>/Lumina.json    the shoot header: the RAW decoder map per body and the pinned
///                              decoder version (LookShootHeader, RAW 9 §1 and §7)
///   shoots/index.json          recent shoots for the Open screen, newest first
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
        var bookmark: Data?
        /// For the Open screen's recent cards (the page's own recents shape): rows seen, keepers,
        /// the last photo. Updated with every saved session; absent in older indexes.
        var seen: Int?
        var keepers: Int?
        var last: String?
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

    func index() -> [Shoot] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: root.appendingPathComponent("index.json")),
              let list = try? dec.decode([Shoot].self, from: data) else { return [] }
        return list.sorted { $0.opened > $1.opened }
    }

    func upsert(_ shoot: Shoot) throws {
        let all = index()
        var shoot = shoot
        if let old = all.first(where: { $0.id == shoot.id }) {
            shoot.seen = shoot.seen ?? old.seen; shoot.keepers = shoot.keepers ?? old.keepers; shoot.last = shoot.last ?? old.last
        }
        var list = all.filter { $0.id != shoot.id }
        list.insert(shoot, at: 0)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list), at: root.appendingPathComponent("index.json"))
    }

    func session(_ id: String) -> Data? {
        try? Data(contentsOf: dir(id).appendingPathComponent("session.json"))
    }

    func saveSession(_ id: String, _ json: Data) throws {
        try SetsFileOps.replaceOwn(json, at: try dir(id).appendingPathComponent("session.json"))
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
        guard list[i] != before else { return }
        try write(list)
    }

    private func write(_ list: [Shoot]) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list), at: root.appendingPathComponent("index.json"))
    }

    /// "Remove Lumina's working files" for one shoot: its session and index entry. Never RAWs or .xmp.
    /// A refused id throws before anything is removed or the index is rewritten.
    func remove(_ id: String) throws {
        let folder = try dir(id)
        try? FileManager.default.removeItem(at: folder)
        let list = index().filter { $0.id != id }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list), at: root.appendingPathComponent("index.json"))
    }

    func bytes(_ id: String) -> Int64 {
        guard let folder = try? dir(id) else { return 0 }
        let files = (FileManager.default.enumerator(at: folder,includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
