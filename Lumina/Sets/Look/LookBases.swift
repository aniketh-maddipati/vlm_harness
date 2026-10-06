import CoreImage
import Foundation
import Metal

/// The cached bases per photo for the Edit canvas (addendum §1, §5, §6). On entering Edit for a
/// photo, the RAW stage (crop and straighten baked in) is rendered once into two GPU textures:
/// `base` at the canvas size in device pixels plus a 15 % margin for pan, and `small` at a
/// quarter of that on each edge, both `rgba16Float` in the working space. The look stages then
/// run on a texture, never on the RAW decode, per slider event. Keyed by (rel, decoder version,
/// crop, rotation, canvas size, noise reduction); evicted least recently used first under a byte
/// cap and a count of photos; the photo on the canvas is pinned. The previous and next photo in
/// the row are prefetched at `.utility`.
///
/// Without a Metal device (or when `CIImage(mtlTexture:)` can't be made) the same two images are
/// kept as half-float bitmaps in main memory, which Core Image uploads once: the image fallback
/// path's cache, and the Linux-free tests' path.
nonisolated final class LookBases: @unchecked Sendable {
    struct Key: Hashable, Sendable, CustomStringConvertible {
        let rel: String
        let decoder: Int?
        let crop: String            // "" for the whole frame, else the look's crop text
        let rotation: Double
        let rot: Int                // the quarter turn (`Look.rot`), baked into the base like the crop
        let width: Int             // the canvas, device px
        let height: Int
        let nr: Int?

        init(rel: String, decoder: Int?, look: Look, canvas: CGSize) {
            self.rel = rel
            self.decoder = decoder
            crop = look.crop.map { String(format: "%.4f,%.4f,%.4f,%.4f", $0.x, $0.y, $0.w, $0.h) } ?? ""
            rotation = look.crop?.rotate ?? 0
            rot = look.rot
            width = max(1, Int(canvas.width.rounded()))
            height = max(1, Int(canvas.height.rounded()))
            nr = look.nr.map { Int($0.rounded()) }
        }

        var description: String { "\(rel)|d\(decoder ?? 0)|\(crop)|r\(rotation)\(rot == 0 ? "" : "|q\(rot)")|\(width)x\(height)|nr\(nr ?? -1)" }

        /// The embedded JPEG's base for the same photo, crop and canvas: what the canvas shows
        /// while this key's RAW develops (`build(jpegOnly:)`). Decoder −1 is no RAW decoder's.
        var jpegFirst: Key { Key(self, decoder: Self.jpegDecoder) }
        static let jpegDecoder = -1

        private init(_ k: Key, decoder: Int?) {
            rel = k.rel; self.decoder = decoder; crop = k.crop; rotation = k.rotation; rot = k.rot; width = k.width; height = k.height; nr = k.nr
        }
    }

    /// `build(jpegOnly: true)`: straight to the embedded JPEG, no RAW develop.
    private struct JPEGFirst: Error {}

    /// The embedded JPEG's byte range, the stand-in when the RAW can't be developed.
    struct PreviewFallback: Sendable, Equatable { let offset: Int; let length: Int; let orientation: Int }

    /// One photo's bases. `base` and `small` are ready to be the `Developed.image` the look
    /// stages run on; both have their origin at (0, 0).
    struct Entry: @unchecked Sendable {
        let base: CIImage
        let small: CIImage
        let asShot: Look.WhiteBalance
        /// The photo's tone anchor (`LookPipeline.Developed.anchor`).
        let anchor: LookMath.ToneAnchor
        let baseSize: CGSize
        let smallSize: CGSize
        /// The photo's upright size after the crop, in the RAW's own pixels (the region tiles map to it).
        let photoSize: CGSize
        let bytes: Int
        let source: String          // "raw" (the RAW decoded) | "image" (a JPEG/PNG file) | "jpeg" (the RAW's embedded preview)
        let decoder: Int?
        let developMs: Double
        let onGPU: Bool
        let textures: [MTLTexture]
    }

    struct Stats: Codable, Equatable, Sendable {
        var built = 0
        var hits = 0
        var misses = 0
        var evicted = 0
        var prefetched = 0
        var failed = 0
        var bytes = 0
        var resident = 0
        var residentPhotos = 0
        var lastBuildMs = 0.0
        var lastSource = ""
        var flipsOnReadback = false
        var onGPU = false
    }

    let pipeline: LookPipeline
    let device: MTLDevice?
    private let lock = NSLock()
    private var cache: LookByteCache<Key, Entry>
    private var _stats = Stats()
    private var building: Set<Key> = []
    private var flips: Bool?
    let maxPhotos: Int
    private let buildQueue: OperationQueue = {
        let q = OperationQueue(); q.name = "lumina.look.bases"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q
    }()
    private let prefetchQueue: OperationQueue = {
        let q = OperationQueue(); q.name = "lumina.look.bases.prefetch"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q
    }()

    init(pipeline: LookPipeline, byteCap: Int = LookRawPolicy.baseCacheBytes, maxPhotos: Int = LookRawPolicy.basePhotos) {
        self.pipeline = pipeline
        self.device = pipeline.device
        self.maxPhotos = maxPhotos
        cache = LookByteCache(cap: byteCap)
        _stats.onGPU = device != nil
    }

    var stats: Stats { lock.withLock { var s = _stats; s.bytes = cache.bytes; s.resident = cache.count; s.residentPhotos = Set(cache.keys.map(\.rel)).count; return s } }

    // MARK: Lookup

    func entry(_ key: Key) -> Entry? {
        lock.withLock {
            let e = cache.get(key)
            if e != nil { _stats.hits += 1 } else { _stats.misses += 1 }
            return e
        }
    }

    /// A base made elsewhere joins the cache as if built here. The tests' seam: a photo whose
    /// base is "already developed" without a RAW file (`SetsCanvasAsShotTests`); `stats.built`
    /// still counts only real builds.
    func adopt(_ key: Key, _ entry: Entry) { lock.withLock { _ = cache.set(key, entry, bytes: entry.bytes) } }

    /// The photo on the canvas: never evicted while pinned.
    func pin(_ key: Key?) { lock.withLock { cache.pinned = key.map { [$0] } ?? [] } }

    /// Memory pressure (RAW 9 §5): everything but the pinned photo.
    @discardableResult
    func dropPrefetched() -> Int {
        lock.withLock {
            let pinned = cache.pinned
            let gone = cache.removeAll { !pinned.contains($0) }
            _stats.evicted += gone.count
            return gone.count
        }
    }

    func forget(rel: String? = nil) {
        lock.withLock {
            if let rel { _ = cache.removeAll { $0.rel == rel } } else { _ = cache.removeAll() }
        }
    }

    // MARK: Building

    /// The photo's bases, built now on the calling queue when not cached. `preview` is the
    /// embedded JPEG's range, used only when the RAW can't be developed.
    func build(_ key: Key, url: URL, look: Look, preview: PreviewFallback?, jpegOnly: Bool = false) throws -> Entry {
        if let e = entry(key) { return e }
        let t0 = Date()
        let margin = 1 + LookRawPolicy.baseMargin
        let canvas = CGSize(width: Double(key.width) * margin, height: Double(key.height) * margin)
        // Develop at the long edge that, once cropped, fits the canvas plus its margin.
        var source = LookPipeline.isRAW(url) ? "raw" : "image"
        let native = LookPipeline.isRAW(url) ? LookPipeline.nativeSize(url: url) : nil
        let cropped = Self.croppedSize(native ?? CGSize(width: 3, height: 2), look.crop, rot: look.rot)
        let fit = min(canvas.width / max(1, cropped.width), canvas.height / max(1, cropped.height))
        let px = native.map { Int((max($0.width, $0.height) * fit).rounded(.up)) }
        var dev: LookPipeline.Developed
        do {
            if jpegOnly { throw JPEGFirst() }
            dev = try LookPipeline.developAny(url: url, longEdge: px, rules: pipeline.rules, decoderVersion: key.decoder, nr: look.nr)
        } catch {
            guard let p = preview else { if !jpegOnly { lock.withLock { _stats.failed += 1 } }; throw error }
            source = "jpeg"
            dev = try LookPipeline.developPreview(url: url, offset: p.offset, length: p.length, orientation: p.orientation, longEdge: nil)
            let c = Self.croppedSize(dev.extent.size, look.crop, rot: look.rot)
            dev = LookPipeline.Developed(image: LookPipeline.scaled(dev.image, longEdge: Int((max(dev.extent.width, dev.extent.height) * min(canvas.width / max(1, c.width), canvas.height / max(1, c.height))).rounded(.up))), asShot: dev.asShot, anchor: dev.anchor)
        }
        let photoSize = Self.croppedSize(native ?? dev.extent.size, look.crop, rot: look.rot)
        // Crop, straighten and the quarter turn are baked in; the look runs with crop: false on top.
        var img = LookPipeline.atOrigin(pipeline.geometry(dev.image, look.crop, rot: look.rot))
        // A JPEG stand-in or a RAW larger than needed (a crop that fits by height): scale to the canvas.
        let e = img.extent
        let s = min(canvas.width / max(1, e.width), canvas.height / max(1, e.height))
        if s < 0.999 { img = LookPipeline.scaled(img, longEdge: Int((max(e.width, e.height) * s).rounded(.down))) }
        // Whole pixels only: a fractional extent would leave a half-covered row along one edge.
        let baseRect = CGRect(x: 0, y: 0, width: max(1, img.extent.width.rounded(.down)), height: max(1, img.extent.height.rounded(.down)))
        img = img.cropped(to: baseRect)
        let smallRect = CGRect(x: 0, y: 0, width: max(1, (baseRect.width / 4).rounded(.down)), height: max(1, (baseRect.height / 4).rounded(.down)))
        let smallImg = LookPipeline.atOrigin(img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: smallRect.width / baseRect.width, kCIInputAspectRatioKey: 1])).cropped(to: smallRect)
        let (base, small, textures, bytes) = try rasterise(img, baseRect, smallImg, smallRect)
        let entry = Entry(base: base, small: small, asShot: dev.asShot, anchor: dev.anchor, baseSize: baseRect.size, smallSize: smallRect.size, photoSize: photoSize,
                          bytes: bytes, source: source, decoder: source == "raw" ? key.decoder : nil, developMs: Date().timeIntervalSince(t0) * 1000,
                          onGPU: !textures.isEmpty, textures: textures)
        lock.withLock {
            _stats.built += 1
            _stats.lastBuildMs = entry.developMs
            _stats.lastSource = source
            let gone = cache.set(key, entry, bytes: bytes)
            _stats.evicted += gone.count
            // At most `maxPhotos` photos resident (the current one and its neighbours): the least
            // recently used photo goes, every size of it, never the pinned photo's entries.
            let pinnedRels = Set(cache.pinned.map(\.rel))
            var rels = Set(cache.keys.map(\.rel))
            while rels.count > maxPhotos, let old = cache.keys.first(where: { !pinnedRels.contains($0.rel) && $0.rel != key.rel }) {
                _ = cache.removeAll { $0.rel == old.rel }
                _stats.evicted += 1
                rels = Set(cache.keys.map(\.rel))
            }
        }
        return entry
    }

    /// Builds on the build queue; `done` on the main thread.
    func request(_ key: Key, url: URL, look: Look, preview: PreviewFallback?, jpegOnly: Bool = false, done: @escaping (Result<Entry, Error>) -> Void) {
        let started: Bool = lock.withLock { building.insert(key).inserted }
        guard started else { return }
        buildQueue.addOperation { [self] in
            let r = Result { try LookTrace.span("base build \(key.rel.split(separator: "/").last ?? "")") { try self.build(key, url: url, look: look, preview: preview, jpegOnly: jpegOnly) } }
            lock.withLock { _ = building.remove(key) }
            DispatchQueue.main.async { done(r) }
        }
    }

    /// Holds the neighbours' builds that haven't started (the canvas holds them while someone
    /// waits on it); a build already running finishes.
    var prefetchPaused: Bool {
        get { prefetchQueue.isSuspended }
        set { if prefetchQueue.isSuspended != newValue { prefetchQueue.isSuspended = newValue } }
    }

    /// The neighbours' bases, one at a time at `.utility`. A new call replaces the queue.
    func prefetch(_ items: [(key: Key, url: URL, look: Look, preview: PreviewFallback?)]) {
        prefetchQueue.cancelAllOperations()
        for i in items where lock.withLock({ cache.peek(i.key) == nil && !building.contains(i.key) }) {
            prefetchQueue.addOperation { [weak self] in
                guard let self else { return }
                guard self.lock.withLock({ self.cache.peek(i.key) == nil }) else { return }
                if (try? LookTrace.span("prefetch \(i.key.rel.split(separator: "/").last ?? "")") { try self.build(i.key, url: i.url, look: i.look, preview: i.preview) }) != nil { self.lock.withLock { self._stats.prefetched += 1 } }
            }
        }
    }

    // MARK: Textures

    private func rasterise(_ img: CIImage, _ rect: CGRect, _ small: CIImage, _ smallRect: CGRect) throws -> (CIImage, CIImage, [MTLTexture], Int) {
        if let device {
            do {
                let (b, bt) = try texture(img, rect, device: device)
                let (s, st) = try texture(small, smallRect, device: device)
                return (b, s, [bt, st], Self.bytes(bt) + Self.bytes(st))
            } catch {
                // The texture path failed (an odd device state): fall back to bitmaps for this photo.
            }
        }
        let (b, bb) = try pipeline.rasterised(LookPipeline.Developed(image: img, asShot: Look.WhiteBalance(kelvin: 0, tint: 0), anchor: .reference))
        let (s, sb) = try pipeline.rasterised(LookPipeline.Developed(image: small, asShot: Look.WhiteBalance(kelvin: 0, tint: 0), anchor: .reference))
        return (b.image, s.image, [], bb + sb)
    }

    private static func bytes(_ t: MTLTexture) -> Int { t.width * t.height * 8 }

    /// Renders `img` (its `rect`, origin 0) into a new `rgba16Float` texture and wraps it as an
    /// image at the origin. Core Image and Metal disagree on which way is up when a texture is
    /// read back as an image; `readbackFlips()` measures it once and the wrap compensates.
    private func texture(_ img: CIImage, _ rect: CGRect, device: MTLDevice) throws -> (CIImage, MTLTexture) {
        let w = max(1, Int(rect.width)), h = max(1, Int(rect.height))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc) else { throw LookPipeline.Failure("no texture \(w)×\(h)") }
        let dest = CIRenderDestination(mtlTexture: tex, commandBuffer: nil)
        dest.colorSpace = pipeline.workingSpace
        dest.alphaMode = .unpremultiplied
        try pipeline.context.startTask(toRender: img, from: rect, to: dest, at: .zero).waitUntilCompleted()
        var out = CIImage(mtlTexture: tex, options: [.colorSpace: pipeline.workingSpace]) ?? CIImage.empty()
        if out.extent.isEmpty { throw LookPipeline.Failure("texture wrap failed") }
        if try readbackFlips(device: device) { out = out.oriented(.downMirrored) }
        return (LookPipeline.atOrigin(out), tex)
    }

    /// Whether an image rendered into a texture comes back upside down when the texture is
    /// wrapped as a `CIImage` again. Measured once with a 4 × 4 image whose top row is white.
    func readbackFlips(device: MTLDevice) throws -> Bool {
        if let f = lock.withLock({ flips }) { return f }
        var data = [Float](repeating: 0, count: 4 * 4 * 4)
        for x in 0..<4 { for c in 0..<4 { data[4 * x + c] = 1 } }              // row 0 (the top) white
        for i in stride(from: 3, to: data.count, by: 4) { data[i] = 1 }         // alpha 1
        let bytes = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let probe = CIImage(bitmapData: bytes, bytesPerRow: 64, size: CGSize(width: 4, height: 4), format: .RGBAf, colorSpace: pipeline.workingSpace)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 4, height: 4, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc) else { throw LookPipeline.Failure("no probe texture") }
        let dest = CIRenderDestination(mtlTexture: tex, commandBuffer: nil)
        dest.colorSpace = pipeline.workingSpace
        dest.alphaMode = .unpremultiplied
        try pipeline.context.startTask(toRender: probe, from: probe.extent, to: dest, at: .zero).waitUntilCompleted()
        guard let back = CIImage(mtlTexture: tex, options: [.colorSpace: pipeline.workingSpace]) else { throw LookPipeline.Failure("probe wrap failed") }
        // In Core Image's coordinates the top row of a 4-tall image is y = 3.
        let top = pipeline.pixel(back, x: 1, y: 3).g, bottom = pipeline.pixel(back, x: 1, y: 0).g
        let f = bottom > top
        lock.withLock { flips = f; _stats.flipsOnReadback = f }
        return f
    }

    /// The upright size after the crop (fractions of the frame) and the quarter turn.
    static func croppedSize(_ size: CGSize, _ crop: Look.Crop?, rot: Int = 0) -> CGSize {
        let s = crop.map { CGSize(width: max(1, (size.width * $0.w).rounded()), height: max(1, (size.height * $0.h).rounded())) } ?? size
        return rot % 180 == 0 ? s : CGSize(width: s.height, height: s.width)
    }
}
