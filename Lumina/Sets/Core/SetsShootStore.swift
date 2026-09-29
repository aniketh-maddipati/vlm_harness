import Foundation

/// Per-shoot memory in Application Support (README "What the prototype environment does for you":
/// session memory → per-shoot database, removable). One folder per shoot:
///   shoots/<id>/session.json   the page's decisions, keyed by file path (not by position)
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

    func index() -> [Shoot] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: root.appendingPathComponent("index.json")),
              let list = try? dec.decode([Shoot].self, from: data) else { return [] }
        return list.sorted { $0.opened > $1.opened }
    }

    func upsert(_ shoot: Shoot) throws {
        var list = index().filter { $0.id != shoot.id }
        list.insert(shoot, at: 0)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list), at: root.appendingPathComponent("index.json"))
    }

    func session(_ id: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("session.json"))
    }

    func saveSession(_ id: String, _ json: Data) throws {
        try SetsFileOps.replaceOwn(json, at: root.appendingPathComponent(id).appendingPathComponent("session.json"))
    }

    /// "Remove Lumina's working files" for one shoot: its session and index entry. Never RAWs or .xmp.
    func remove(_ id: String) throws {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id))
        let list = index().filter { $0.id != id }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(list), at: root.appendingPathComponent("index.json"))
    }

    func bytes(_ id: String) -> Int64 {
        let dir = root.appendingPathComponent(id)
        let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
