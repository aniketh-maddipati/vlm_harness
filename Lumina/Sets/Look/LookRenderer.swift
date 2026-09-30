import CoreImage
import Foundation

/// Previews for `lumina://render/<rel>?look=&px=&seq=`: the developed RAW cached per (rel, px)
/// under a byte cap, the look stages re-run per request, one render at a time, and requests a
/// newer sequence number has overtaken dropped before they render (roadmap §7).
nonisolated final class LookRenderer: @unchecked Sendable {
    struct Stale: Error, CustomStringConvertible { var description: String { "superseded" } }

    struct Stats: Codable, Equatable, Sendable {
        var renders = 0
        var developed = 0
        var cacheHits = 0
        var stale = 0
        var evicted = 0
        var cacheBytes = 0
        var lastRenderMs = 0.0
        var lastDevelopMs = 0.0
    }

    private struct Entry { let dev: LookPipeline.Developed; let bytes: Int }

    let pipeline: LookPipeline
    let byteCap: Int
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var order: [String] = []                  // least recently used first
    private var latest: [String: Int] = [:]           // rel → newest seq asked for
    private var _stats = Stats()
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.name = "lumina.look.render"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q
    }()

    var stats: Stats { lock.withLock { _stats } }

    init(rules: LookRules, byteCap: Int = 384 << 20) throws {
        pipeline = try LookPipeline(rules: rules)
        self.byteCap = byteCap
    }

    // MARK: sequence numbers

    /// The page asked for `rel` with `seq`; anything older for the same photo is now stale.
    func requested(rel: String, seq: Int) {
        lock.withLock { latest[rel] = max(latest[rel] ?? Int.min, seq) }
    }

    func isStale(rel: String, seq: Int) -> Bool {
        lock.withLock { (latest[rel] ?? Int.min) > seq }
    }

    /// Runs `work` on the render queue; `done` gets the result on the main thread.
    func enqueue(_ work: @escaping () throws -> Data, done: @escaping (Result<Data, Error>) -> Void) {
        queue.addOperation {
            let r = Result { try work() }
            DispatchQueue.main.async { done(r) }
        }
    }

    // MARK: the developed cache

    private static func key(_ rel: String, _ px: Int, _ decoder: Int?, _ nr: Double?) -> String { "\(rel)|\(px)|\(decoder ?? 0)|\(nr.map { Int($0.rounded()) } ?? -1)" }

    func developed(url: URL, rel: String, px: Int, decoder: Int? = nil, nr: Double? = nil, preview: LookBases.PreviewFallback? = nil) throws -> LookPipeline.Developed {
        let key = Self.key(rel, px, decoder, nr)
        let hit: Entry? = lock.withLock { () -> Entry? in
            guard let e = cache[key] else { return nil }
            order.removeAll { $0 == key }; order.append(key); _stats.cacheHits += 1
            return e
        }
        if let hit { return hit.dev }
        let t0 = Date()
        let raw: LookPipeline.Developed
        do {
            raw = try LookPipeline.developAny(url: url, longEdge: px, rules: pipeline.rules, decoderVersion: decoder, nr: nr)
        } catch {
            // The RAW can't be developed: its embedded JPEG stands in when the page gave its range (as the canvas's bases do).
            guard let p = preview else { throw error }
            raw = try LookPipeline.developPreview(url: url, offset: p.offset, length: p.length, orientation: p.orientation, longEdge: px)
        }
        let (dev, bytes) = try pipeline.rasterised(raw)
        lock.withLock {
            _stats.developed += 1
            _stats.lastDevelopMs = Date().timeIntervalSince(t0) * 1000
            cache[key] = Entry(dev: dev, bytes: bytes)
            order.removeAll { $0 == key }; order.append(key)
            _stats.cacheBytes += bytes
            while _stats.cacheBytes > byteCap, order.count > 1, let old = order.first {
                order.removeFirst()
                if let e = cache.removeValue(forKey: old) { _stats.cacheBytes -= e.bytes; _stats.evicted += 1 }
            }
        }
        return dev
    }

    /// Drops every cached size of one photo (its file changed or went away), or everything.
    func forget(rel: String? = nil) {
        lock.withLock {
            let keys = rel.map { r in cache.keys.filter { $0.hasPrefix(r + "|") } } ?? Array(cache.keys)
            for k in keys { if let e = cache.removeValue(forKey: k) { _stats.cacheBytes -= e.bytes } }
            order.removeAll { keys.contains($0) }
        }
    }

    // MARK: rendering

    /// The preview JPEG. Throws `Stale` when a newer request for `rel` arrived before this one
    /// rendered (checked before the develop and again before the encode). `decoder` is the
    /// canvas tier's version (the image fallback path renders what the native canvas would).
    func renderJPEG(url: URL, rel: String, look: String, px: Int, seq: Int, quality: Double = 0.9, decoder: Int? = nil, preview: LookBases.PreviewFallback? = nil) throws -> Data {
        if isStale(rel: rel, seq: seq) { lock.withLock { _stats.stale += 1 }; throw Stale() }
        let parsed = try Look.parse(look)
        let dev = try developed(url: url, rel: rel, px: px, decoder: decoder, nr: parsed.nr, preview: preview)
        if isStale(rel: rel, seq: seq) { lock.withLock { _stats.stale += 1 }; throw Stale() }
        let t0 = Date()
        let out = pipeline.apply(parsed, to: dev)
        let data = try pipeline.jpeg(out, quality: quality)
        lock.withLock { _stats.renders += 1; _stats.lastRenderMs = Date().timeIntervalSince(t0) * 1000 }
        return data
    }
}
