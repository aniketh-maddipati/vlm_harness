import Foundation

/// A byte-capped cache with least-recently-used eviction: the `base` / `small` textures per
/// photo (`LookBases`), the RAW 9 region tiles (`LookRegionTiles`) and the preview renderer's
/// developed rasters. Keys in `pinned` are never evicted (the photo on the canvas); `trim` and
/// `set` return what was evicted so the owner can release GPU memory.
nonisolated struct LookByteCache<Key: Hashable & Sendable, Value>: @unchecked Sendable {
    struct Entry { let value: Value; let bytes: Int }

    private(set) var cap: Int
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []            // least recently used first
    private(set) var bytes = 0
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var evictions = 0
    var pinned: Set<Key> = []

    init(cap: Int) { self.cap = max(0, cap) }

    var count: Int { entries.count }
    var keys: [Key] { order }
    func contains(_ key: Key) -> Bool { entries[key] != nil }
    func bytes(for key: Key) -> Int { entries[key]?.bytes ?? 0 }

    /// The value, marking it as just used.
    mutating func get(_ key: Key) -> Value? {
        guard let e = entries[key] else { misses += 1; return nil }
        touch(key)
        hits += 1
        return e.value
    }

    /// Without touching the order (a lookup that is not a use).
    func peek(_ key: Key) -> Value? { entries[key]?.value }

    /// Stores and evicts down to the cap (never the new entry itself, never a pinned one).
    @discardableResult
    mutating func set(_ key: Key, _ value: Value, bytes n: Int) -> [Value] {
        var out: [Value] = []
        if let old = entries.removeValue(forKey: key) { bytes -= old.bytes; out.append(old.value) }
        entries[key] = Entry(value: value, bytes: max(0, n))
        bytes += max(0, n)
        touch(key)
        out += trim(to: cap, keep: [key])
        return out
    }

    @discardableResult
    mutating func remove(_ key: Key) -> Value? {
        guard let e = entries.removeValue(forKey: key) else { return nil }
        bytes -= e.bytes
        order.removeAll { $0 == key }
        return e.value
    }

    @discardableResult
    mutating func removeAll(where drop: (Key) -> Bool) -> [Value] {
        var out: [Value] = []
        for k in order where drop(k) { if let v = remove(k) { out.append(v) } }
        return out
    }

    @discardableResult
    mutating func removeAll() -> [Value] {
        let out = order.compactMap { entries[$0]?.value }
        entries = [:]; order = []; bytes = 0
        return out
    }

    mutating func setCap(_ n: Int) -> [Value] { cap = max(0, n); return trim(to: cap) }

    /// Evicts least recently used entries until the total is at most `limit`. Pinned keys and
    /// `keep` stay whatever the limit.
    @discardableResult
    mutating func trim(to limit: Int, keep: Set<Key> = []) -> [Value] {
        var out: [Value] = []
        var i = 0
        while bytes > limit, i < order.count {
            let k = order[i]
            if pinned.contains(k) || keep.contains(k) { i += 1; continue }
            if let v = remove(k) { out.append(v); evictions += 1 }
        }
        return out
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
