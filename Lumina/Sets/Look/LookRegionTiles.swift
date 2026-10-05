import CoreImage
import Foundation
import Metal

/// RAW 9 on the visible region only (RAW 9 §2 loupe, §3, §5): the full-size decode of one photo is
/// rendered in explicit 512 × 512 tiles covering the region plus one tile of margin, each tile
/// into its own `rgba16Float` texture, cached per (rel, decoder version, noise reduction, tile)
/// under a 150 MB cap that is evicted before any base texture. Panning reuses the tiles it
/// already has. The tiles are look-independent: the look stages run on the composite.
///
/// `CIImageProcessorKernel` tiles were the plan; a Core Image processor can't drive
/// `CIRAWFilter`'s decode per output tile in a way that is cheaper than asking the RAW graph
/// for that rect directly, so each tile here is a cropped render of the RAW at scaleFactor 1
/// (the fallback the roadmap allows), which the decoder's own tiling keeps region-only.
nonisolated final class LookRegionTiles: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let rel: String
        let decoder: Int
        let nr: Int?
        let col: Int
        let row: Int
    }

    struct Tile: @unchecked Sendable {
        let image: CIImage           // origin at its place in the full frame (Core Image coordinates, y up)
        let rect: CGRect
        let bytes: Int
        let ms: Double
        let texture: MTLTexture?
    }

    /// What the model saw, for the facts line (RAW 9 §3): Laplacian variance and the clipped
    /// fraction of the region, from the tiles rather than the embedded JPEG.
    struct Facts: Codable, Equatable, Sendable {
        var sharpness: Double
        var clipHi: Double
        var clipLo: Double
        var source: String
    }

    struct Region: @unchecked Sendable {
        let rel: String
        let decoder: Int
        let roi: LookCanvasSchedule.ROI
        /// The quarter turn (`Look.rot`) the region was made for: `roi`, `photoSize`, `rect` and
        /// `image` are all in the turned picture. The tiles themselves are in the frame as shot.
        var rot: Int = 0
        let photoSize: CGSize
        let rect: CGRect             // the tiles' union, full-frame pixels
        let image: CIImage           // the composite, origin at rect.origin
        let asShot: Look.WhiteBalance
        let anchor: LookMath.ToneAnchor           // the photo's tone anchor, the same one its bases carry
        let tiles: Int
        let fromCache: Int
        let firstTileMs: Double
        let totalMs: Double
        let facts: Facts
    }

    struct Stats: Codable, Equatable, Sendable {
        var regions = 0
        var tiles = 0
        var cacheHits = 0
        var evicted = 0
        var bytes = 0
        var resident = 0
        var failures = 0
        var lastFirstTileMs = 0.0
        var lastRegionMs = 0.0
        var lastDecoder = 0
    }

    struct Cancelled: Error, CustomStringConvertible { var description: String { "region superseded" } }

    let pipeline: LookPipeline
    let device: MTLDevice?
    let tileSize: Int
    private let lock = NSLock()
    private var cache: LookByteCache<Key, Tile>
    private var developed: [String: LookPipeline.Developed] = [:]        // "rel|decoder|nr" → the full-size graph (lazy, no pixels)
    private var _stats = Stats()
    private var latest = 0
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.name = "lumina.look.tiles"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q
    }()

    init(pipeline: LookPipeline, byteCap: Int = LookRawPolicy.tileCacheBytes, tileSize: Int = LookRawPolicy.tileSize) {
        self.pipeline = pipeline
        self.device = pipeline.device
        self.tileSize = tileSize
        cache = LookByteCache(cap: byteCap)
    }

    var stats: Stats { lock.withLock { var s = _stats; s.bytes = cache.bytes; s.resident = cache.count; return s } }

    /// Memory pressure: the tiles go first (§5).
    @discardableResult
    func drop() -> Int { lock.withLock { let n = cache.count; _ = cache.removeAll(); developed = [:]; _stats.evicted += n; return n } }

    func forget(rel: String) { lock.withLock { _ = cache.removeAll { $0.rel == rel }; developed = developed.filter { !$0.key.hasPrefix(rel + "|") } } }

    /// A request number newer than every one handed out, which supersedes them all: queued or
    /// running regions with an older number stop at their next tile. Every caller (the canvas,
    /// the probe) takes its numbers here, so one caller's numbering can't starve another's.
    func nextSeq() -> Int { lock.withLock { latest += 1; return latest } }

    /// Stops the queued and running regions (leaving Edit, another photo, the loupe off).
    func cancel() { _ = nextSeq() }

    /// Renders the region on the tile queue. `seq` (from `nextSeq`) supersedes older requests (a
    /// pan, a new photo); `first` fires on the main thread when the first tile is ready, `done`
    /// with the composite. Failures name the decoder so the caller can fall back one version.
    /// `rot` is the look's quarter turn: `roi` is then a region of the turned picture, and the
    /// region comes back turned (the crop is not applied here, as before).
    func region(rel: String, url: URL, decoder: Int, nr: Double?, roi: LookCanvasSchedule.ROI, rot: Int = 0, seq: Int,
                first: @escaping (Double) -> Void, done: @escaping (Result<Region, Error>) -> Void) {
        lock.withLock { latest = max(latest, seq) }
        queue.addOperation { [self] in
            let r = Result { try self.render(rel: rel, url: url, decoder: decoder, nr: nr, roi: roi, rot: rot, seq: seq, first: first) }
            DispatchQueue.main.async { done(r) }
        }
    }

    private func stale(_ seq: Int) -> Bool { lock.withLock { latest > seq } }

    private func render(rel: String, url: URL, decoder: Int, nr: Double?, roi: LookCanvasSchedule.ROI, rot: Int, seq: Int, first: @escaping (Double) -> Void) throws -> Region {
        if stale(seq) { throw Cancelled() }
        let t0 = Date()
        let dkey = "\(rel)|\(decoder)|\(nr.map { Int($0.rounded()) } ?? -1)"
        let dev: LookPipeline.Developed
        if let d = lock.withLock({ developed[dkey] }) { dev = d } else {
            dev = try LookPipeline.develop(url: url, longEdge: nil, rules: pipeline.rules, decoderVersion: decoder, nr: nr)
            lock.withLock { developed = [dkey: dev] }          // one full-size graph at a time
        }
        let size = dev.extent.size
        let w = Int(size.width), h = Int(size.height)
        let wanted = LookRawPolicy.tiles(covering: LookRawPolicy.unturned(roi, rot: rot), width: w, height: h, tile: tileSize)
        guard !wanted.isEmpty else { throw LookPipeline.Failure("empty region") }
        var tiles: [Tile] = []
        var hits = 0, firstMs = 0.0, firstSent = false
        let nrKey = nr.map { Int($0.rounded()) }
        for (col, row) in wanted {
            if stale(seq) { throw Cancelled() }
            let key = Key(rel: rel, decoder: decoder, nr: nrKey, col: col, row: row)
            if let t = lock.withLock({ cache.get(key) }) { tiles.append(t); hits += 1 }
            else {
                let tt = Date()
                let t = try tile(dev.image, col: col, row: row, width: w, height: h)
                lock.withLock { _stats.tiles += 1; let gone = cache.set(key, t, bytes: t.bytes); _stats.evicted += gone.count }
                tiles.append(t)
                if !firstSent { firstMs = Date().timeIntervalSince(tt) * 1000 }
            }
            if !firstSent {
                firstSent = true
                let ms = firstMs
                lock.withLock { _stats.lastFirstTileMs = ms }
                DispatchQueue.main.async { first(ms) }
            }
        }
        let rect = tiles.dropFirst().reduce(tiles[0].rect) { $0.union($1.rect) }
        var img = CIImage(color: .clear).cropped(to: rect)
        for t in tiles { img = t.image.composited(over: img) }
        let composite = img.cropped(to: rect)
        let facts = facts(composite, rect: rect)
        let total = Date().timeIntervalSince(t0) * 1000
        lock.withLock { _stats.regions += 1; _stats.cacheHits += hits; _stats.lastRegionMs = total; _stats.lastDecoder = decoder }
        // The quarter turn: the composite and its place move with the whole frame's transform.
        let turn = LookPipeline.turnTransform(size: size, rot: rot)
        if !turn.isIdentity {
            return Region(rel: rel, decoder: decoder, roi: roi, rot: rot, photoSize: rot % 180 == 0 ? size : CGSize(width: size.height, height: size.width),
                          rect: rect.applying(turn), image: composite.transformed(by: turn), asShot: dev.asShot, anchor: dev.anchor,
                          tiles: tiles.count, fromCache: hits, firstTileMs: firstMs, totalMs: total, facts: facts)
        }
        return Region(rel: rel, decoder: decoder, roi: roi, photoSize: size, rect: rect, image: composite, asShot: dev.asShot, anchor: dev.anchor,
                      tiles: tiles.count, fromCache: hits, firstTileMs: firstMs, totalMs: total, facts: facts)
    }

    /// One tile of the full-size decode, rendered for its rect only.
    private func tile(_ full: CIImage, col: Int, row: Int, width w: Int, height h: Int) throws -> Tile {
        let t0 = Date()
        let x = col * tileSize, top = row * tileSize
        let tw = min(tileSize, w - x), th = min(tileSize, h - top)
        guard tw > 0, th > 0 else { throw LookPipeline.Failure("tile outside the frame") }
        // Rows count from the top; Core Image's y counts from the bottom.
        let rect = CGRect(x: x, y: h - top - th, width: tw, height: th)
        let bytes = tw * th * 8
        if let device {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: tw, height: th, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .private
            if let tex = device.makeTexture(descriptor: desc) {
                let dest = CIRenderDestination(mtlTexture: tex, commandBuffer: nil)
                dest.colorSpace = pipeline.workingSpace
                dest.alphaMode = .unpremultiplied
                try pipeline.context.startTask(toRender: full, from: rect, to: dest, at: .zero).waitUntilCompleted()
                if var img = CIImage(mtlTexture: tex, options: [.colorSpace: pipeline.workingSpace]) {
                    if let f = flips, f { img = img.oriented(.downMirrored) }
                    else if flips == nil, let f = try? probeFlip(device: device), f { img = img.oriented(.downMirrored) }
                    let placed = LookPipeline.atOrigin(img).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
                    return Tile(image: placed, rect: rect, bytes: bytes, ms: Date().timeIntervalSince(t0) * 1000, texture: tex)
                }
            }
        }
        guard let cg = pipeline.context.createCGImage(full, from: rect, format: .RGBAh, colorSpace: pipeline.workingSpace) else { throw LookPipeline.Failure("tile render failed") }
        let placed = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Tile(image: placed, rect: rect, bytes: cg.bytesPerRow * cg.height, ms: Date().timeIntervalSince(t0) * 1000, texture: nil)
    }

    /// Shared with the bases: whether a texture read back as an image is upside down.
    private var flips: Bool? { lock.withLock { _flips } }
    private var _flips: Bool?
    private func probeFlip(device: MTLDevice) throws -> Bool {
        let f = try LookBases(pipeline: pipeline, byteCap: 0).readbackFlips(device: device)
        lock.withLock { _flips = f }
        return f
    }

    /// Laplacian variance (sharpness) and the clipped fractions of the region, from a 512 px
    /// luma copy of the composite: cheap, and from the model's pixels, not the JPEG's.
    func facts(_ img: CIImage, rect: CGRect) -> Facts {
        let long = max(rect.width, rect.height)
        let s = min(1, 512 / max(1, long))
        let small = LookPipeline.atOrigin(img.transformed(by: CGAffineTransform(scaleX: s, y: s)))
        let w = max(2, Int(small.extent.width)), h = max(2, Int(small.extent.height))
        var px = [Float](repeating: 0, count: w * h * 4)
        pipeline.context.render(small, toBitmap: &px, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: pipeline.workingSpace)
        let lum = pipeline.rules.luma
        var y = [Float](repeating: 0, count: w * h)
        var hi = 0, lo = 0
        for i in 0..<(w * h) {
            let r = px[4 * i], g = px[4 * i + 1], b = px[4 * i + 2]
            y[i] = Float(lum[0]) * r + Float(lum[1]) * g + Float(lum[2]) * b
            if max(r, g, b) >= 0.995 { hi += 1 }
            if min(r, g, b) <= 0.002 { lo += 1 }
        }
        var sum = 0.0, sum2 = 0.0, n = 0.0
        for j in 1..<(h - 1) {
            for i in 1..<(w - 1) {
                let k = j * w + i
                let lap = Double(4 * y[k] - y[k - 1] - y[k + 1] - y[k - w] - y[k + w])
                sum += lap; sum2 += lap * lap; n += 1
            }
        }
        let mean = n > 0 ? sum / n : 0
        let variance = n > 0 ? sum2 / n - mean * mean : 0
        return Facts(sharpness: (variance * 1e4).rounded() / 1e4, clipHi: Double(hi) / Double(w * h), clipLo: Double(lo) / Double(w * h), source: "raw9-region")
    }
}
