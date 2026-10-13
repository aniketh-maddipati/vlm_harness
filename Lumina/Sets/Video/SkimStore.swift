import Foundation

/// Skim's saved shoots, one JSON file in the app's container: `skim/store.json`. Each entry is what the
/// page keeps for one shoot (its marks, dismissed facts, gap cut, profile answer, name, count, size), under
/// the page's own key `lumina-skim:<shoot>-<count>`, kept as the page's JSON text.
///
/// The page holds the same entries in its localStorage for the session, which the app's non-persistent
/// web view forgets on quit. So on load it asks for all of them (`skimStore`) and makes its own match, and it
/// sends every change here (`skimSave`). Only Debug builds show Skim (`SetsPage`, `LUMINA_PAGE=skim`).
///
/// Bounded: keys start with `lumina-skim:` and are at most 512 characters, a value is at most 256 KB, at
/// most 512 shoots and 4 MB in all. Writes are atomic (a temp file, then a rename).
nonisolated struct SkimStore: Sendable {
    static let prefix = "lumina-skim:"
    static let maxKey = 512
    static let maxValue = 256 << 10
    static let maxKeys = 512
    static let maxBytes = 4 << 20

    let file: URL

    init(dir: URL) { file = dir.appendingPathComponent("store.json") }

    /// Every entry. An unreadable, oversized or malformed file reads as empty (and is replaced by the next write).
    func all() -> [String: String] {
        guard let d = try? Data(contentsOf: file), d.count <= Self.maxBytes,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o.filter { Self.valid(key: $0.key, value: $0.value) }
    }

    static func valid(key: String, value: String?) -> Bool {
        guard key.hasPrefix(prefix), key.count <= maxKey, !key.contains("\0") else { return false }
        return (value?.utf8.count ?? 0) <= maxValue
    }

    /// Sets one entry, or removes it when `value` is nil. False when it is refused (key, size, count) or
    /// the write fails; the file is then as it was.
    @discardableResult
    func set(_ key: String, _ value: String?) -> Bool {
        guard Self.valid(key: key, value: value) else { return false }
        var o = all()
        if let value { o[key] = value } else { o.removeValue(forKey: key) }
        guard o.count <= Self.maxKeys,
              let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), d.count <= Self.maxBytes else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
