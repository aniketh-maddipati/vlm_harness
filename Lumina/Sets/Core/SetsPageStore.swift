import Foundation

/// The few things the page keeps in `localStorage` that have to outlive a launch: that the tour was
/// seen, shoot names, the seen-before memory, the "before you open" tick, the phone page's choice.
/// The web view's own storage is not persistent (nothing the page stores may outlive the app's say),
/// so plumbing.js mirrors exactly these keys here and seeds them back before the page starts.
/// One JSON file in Application Support. Only the keys below, each under a size cap: a key the
/// page invents later is not stored until it is named here.
nonisolated struct SetsPageStore {
    /// `lumina-v4-seen` is the large one: up to 20,000 photos at about 120 bytes.
    static let keys: [String: Int] = [
        "lumina-v4-toured": 16,
        "lumina-v4-pre-ok": 16,
        "lumina-v4-names": 256 << 10,
        "lumina-v4-seen": 4 << 20,
        "lumina-phone-kind": 64,
        "lumina-phone-used": 16,
        "lumina.edit.intro.v1": 16,
    ]

    let file: URL

    init(supportDir: URL) { file = supportDir.appendingPathComponent("page-store.json") }

    /// What is stored, without anything that is no longer an allowed key or is over its cap.
    func all() -> [String: String] {
        guard let data = try? Data(contentsOf: file), data.count <= 8 << 20,
              let any = try? JSONSerialization.jsonObject(with: data), let map = any as? [String: String] else { return [:] }
        return map.filter { Self.allows($0.key, $0.value) }
    }

    static func allows(_ key: String, _ value: String) -> Bool {
        guard let cap = keys[key] else { return false }
        return value.utf8.count <= cap
    }

    /// Stores `value` under `key` (nil removes it). False, and nothing changed, for a key that is
    /// not allowed or a value over its cap.
    @discardableResult
    func set(_ key: String, _ value: String?) -> Bool {
        guard Self.keys[key] != nil else { return false }
        var map = all()
        if let value {
            guard Self.allows(key, value) else { return false }
            map[key] = value
        } else {
            map[key] = nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]) else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SetsFileOps.replaceOwn(data, at: file)
            return true
        } catch { return false }
    }
}
