import Foundation

/// `lumina.auto(rel)` (BRIDGE-v0.02 §1): AutoDevelop on the photo's RAW, answered as
/// `{look: {ev, wb?, tint?, hl, sh, wh, bl}, version}` in the Edit page's slider units, or nil.
///
/// One answer per file and AutoDevelop version: the cache key is the file's path, size and
/// modification date plus `AutoDevelop.version`, so a file changed on disk or a new AutoDevelop
/// measures again and nothing else does. Failures (not a RAW Core Image reads, a damaged file)
/// are remembered the same way, so a broken file is not decoded on every A press.
///
/// `answer` blocks on the RAW decode: SetsBridge calls it from a detached task, never on the main
/// thread. Foundation only (the measure is handed in), so it runs in the Linux sandbox too.
nonisolated final class SetsAuto: @unchecked Sendable {
    /// Distinct files remembered; past it the cache starts over (a shoot is far smaller).
    static let capacity = 20_000

    private let measure: @Sendable (URL) throws -> ImageStats
    private let lock = NSLock()
    private var cache: [String: [String: Any]?] = [:]
    private var decodes = 0

    /// How many times a file was measured (cache misses), for tests and the probe.
    var measured: Int { lock.lock(); defer { lock.unlock() }; return decodes }

    init(measure: @escaping @Sendable (URL) throws -> ImageStats) {
        self.measure = measure
    }

    /// The page's `rel` as the op accepts it: a non-empty string of at most `maxBytes` UTF-8
    /// bytes with no NUL. Anything else (a number, an object, 10 MB of text) is nil.
    static func rel(_ v: Any?, maxBytes: Int) -> String? {
        guard let s = v as? String, !s.isEmpty, s.utf8.count <= maxBytes, !s.contains("\u{0}") else { return nil }
        return s
    }

    /// A fresh URL for the same path: a URL keeps the resource values it read once (NSURL's cache), so
    /// asking the caller's URL again would miss a file rewritten since.
    private static func fresh(_ url: URL) -> URL { URL(fileURLWithPath: url.path) }

    static func key(_ url: URL) -> String {
        let v = try? fresh(url).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(url.standardizedFileURL.path)|\(v?.fileSize ?? -1)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(AutoDevelop.version)"
    }

    /// What the bridge returns for these stats.
    static func answer(_ stats: ImageStats) -> [String: Any] {
        ["look": AutoDevelop.recipe(for: stats).look, "version": AutoDevelop.version]
    }

    /// The answer for a resolved file, measured once per key. Nil when it can't be measured, and
    /// at once (no decode, nothing cached) when it is not a regular file that is there now.
    func answer(url: URL) -> [String: Any]? {
        guard (try? Self.fresh(url).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        let k = Self.key(url)
        lock.lock()
        let hit = cache[k]
        lock.unlock()
        if let hit { return hit }
        let out: [String: Any]?
        do { out = Self.answer(try measure(url)) } catch { out = nil }
        lock.lock()
        if cache.count >= Self.capacity { cache.removeAll() }
        cache[k] = .some(out)
        decodes += 1
        lock.unlock()
        return out
    }
}
