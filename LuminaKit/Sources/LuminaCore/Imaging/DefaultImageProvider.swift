import Foundation
import CoreGraphics
import ImageIO

// WP-4. The package's picture source: generated demo photos (no file, no network) and ImageIO
// for files, RAW included, with orientation applied (R-1D). Looks are approximated with Core
// Image (`LookRender`); the app's adapter renders through the real Look pipeline instead.
//
// Three queues, so thumbnails never hold up the Edit photo (R-81): big pictures, small ones
// (thumbnails, the low-res stage), and preloads. Decoded pictures sit in an LRU with a byte cap.

public enum ImageError: Error { case cannotOpen(String), injected }

public final class DefaultImageProvider: ImageProvider, PixelSizing, @unchecked Sendable {
    /// Requests up to this size are thumbnails.
    static let smallPixel = 480
    /// The demo card's photos are nominally this many pixels on their long side (16 MP at 3:2):
    /// on a 2× display in the 1100 × 760 window the photo fits 824pt wide, so 1:1 is 3× Fit
    /// there, the zoom the prototype's traces record for Z.
    public static let demoPixelLong = 4944.0

    private let cache: ImageCache
    private let big = OperationQueue(), small = OperationQueue(), ahead = OperationQueue()
    private let lock = NSLock()
    private var preloads: [String: Operation] = [:]
    private var sizes: [URL: CGSize] = [:]

    /// `cacheBytes`: the most decoded pixels kept in memory.
    public init(cacheBytes: Int) {
        cache = ImageCache(limit: cacheBytes)
        big.maxConcurrentOperationCount = 2; big.qualityOfService = .userInitiated
        small.maxConcurrentOperationCount = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)); small.qualityOfService = .utility
        ahead.maxConcurrentOperationCount = 1; ahead.qualityOfService = .utility
    }
    public convenience init() { self.init(cacheBytes: 192 << 20) }

    /// Bytes of decoded pictures held right now (tests, R-92).
    public var cachedBytes: Int { cache.bytes }

    public func image(for photo: Photo, maxPixel: Int, look: Look?) async throws -> CGImage {
        let px = max(8, min(maxPixel, 3600))
        let look = look.flatMap { $0.isEmpty ? nil : $0 }
        let key = Self.key(photo, px, look)
        if !Faults.shared.has(.imageLoadFail), let hit = cache.get(key) { return hit }
        return try await run(on: px <= Self.smallPixel ? small : big) { [self] in
            try render(photo, px: px, look: look, key: key)
        }
    }

    public func preload(_ photos: [Photo], maxPixel: Int) {
        let px = max(8, min(maxPixel, 3600))
        for p in photos {
            let key = Self.key(p, px, nil)
            if cache.get(key) != nil { continue }
            let op = BlockOperation()
            op.addExecutionBlock { [weak self, weak op] in
                guard let self, let op, !op.isCancelled else { return }
                _ = try? self.render(p, px: px, look: nil, key: key)
                self.lock.withLock { if self.preloads[key] === op { self.preloads[key] = nil } }
            }
            let stale: Operation? = lock.withLock { let old = preloads[key]; preloads[key] = op; return old }
            stale?.cancel()
            ahead.addOperation(op)
        }
    }

    public func cancelPreloads() {
        let ops: [Operation] = lock.withLock { let o = Array(preloads.values); preloads.removeAll(); return o }
        ops.forEach { $0.cancel() }
    }

    /// The real pixel size after orientation (the demo card's is nominal).
    public func pixelSize(for photo: Photo) -> CGSize? {
        switch photo.source {
        case .demo:
            let l = Self.demoPixelLong, a = max(photo.aspect, 1e-6)
            return a >= 1 ? CGSize(width: l, height: (l / a).rounded()) : CGSize(width: (l * a).rounded(), height: l)
        case .file(let url):
            if let s = lock.withLock({ sizes[url] }) { return s }
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue, let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { return nil }
            let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let s = o >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
            lock.withLock { sizes[url] = s }
            return s
        case .remote:
            return nil
        }
    }

    // MARK: decoding

    static func key(_ p: Photo, _ px: Int, _ look: Look?) -> String {
        let source: String
        switch p.source {
        case .demo(let seed, let bw): source = "demo:\(seed):\(bw):\(String(format: "%.4f", p.aspect))"
        case .file(let u): source = u.path
        case .remote(let path): source = "remote:" + path
        }
        return "\(source)|\(px)|\(LookRender.key(look))"
    }

    private func run(on queue: OperationQueue, _ work: @escaping @Sendable () throws -> CGImage) async throws -> CGImage {
        let op = BlockOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<CGImage, Error>) in
                op.addExecutionBlock { [weak op] in
                    if op?.isCancelled ?? true { c.resume(throwing: CancellationError()); return }
                    do { c.resume(returning: try work()) } catch { c.resume(throwing: error) }
                }
                queue.addOperation(op)
            }
        } onCancel: { op.cancel() }
    }

    /// Decode (or take from the cache) and apply the look. Runs on one of the queues.
    private func render(_ photo: Photo, px: Int, look: Look?, key: String) throws -> CGImage {
        if Faults.shared.has(.imageLoadFail) { throw ImageError.injected }
        if let hit = cache.get(key) { return hit }
        // A slow decode is the sharp picture's; the small one still shows at once (R-42).
        if px > Self.smallPixel, let ms = Faults.shared.slowDecodeMs { Thread.sleep(forTimeInterval: Double(ms) / 1000) }
        guard let look else {
            let img = try decode(photo, px: px)
            cache.set(key, img); return img
        }
        // The base is decoded larger when a crop will cut it down, so the result is still sharp.
        let box = CropBox(look), grow = 1 / max(0.25, max(box.w, box.h))
        let basePx = min(3600, px <= Self.smallPixel ? Int(Double(px) * grow) : Int((Double(px) * grow / 400).rounded(.up)) * 400)
        let baseKey = Self.key(photo, basePx, nil)
        let base: CGImage
        if let hit = cache.get(baseKey) { base = hit } else { base = try decode(photo, px: basePx); cache.set(baseKey, base) }
        guard let out = LookRender.apply(look, to: base, maxPixel: px) else { throw ImageError.cannotOpen(photo.file) }
        cache.set(key, out)
        return out
    }

    private func decode(_ photo: Photo, px: Int) throws -> CGImage {
        switch photo.source {
        case .demo(let seed, let bw):
            // The prototype's picsum picture when this Mac has it cached (DemoPhotos), else the generated one.
            if let url = DemoPhotos.url(seed: seed, aspect: photo.aspect, bw: bw), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceThumbnailMaxPixelSize: px, kCGImageSourceCreateThumbnailWithTransform: true,
                                                                     kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary) {
                return img
            }
            return Self.demo(seed: seed, bw: bw, aspect: photo.aspect, maxPixel: px)
        case .file(let url):
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else { throw ImageError.cannotOpen(photo.file) }
            var opts: [CFString: Any] = [kCGImageSourceThumbnailMaxPixelSize: px, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
            // Small pictures: the preview the camera embedded, when it is big enough (a RAW's
            // full decode takes a second; its embedded JPEG takes milliseconds).
            if px <= Self.smallPixel {
                opts[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
                if let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary), max(img.width, img.height) * 10 >= px * 9 { return img }
                opts[kCGImageSourceCreateThumbnailFromImageIfAbsent] = nil
            }
            opts[kCGImageSourceCreateThumbnailFromImageAlways] = true
            guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw ImageError.cannotOpen(photo.file) }
            return img
        case .remote:
            throw ImageError.cannotOpen(photo.file)
        }
    }

    /// A deterministic picture per seed: a sky, a sun, hills and a striped foreground, so photos
    /// are tellable apart, zoom has something to look at and edits are visible. No file, no network.
    public static func demo(seed: Int, bw: Bool, aspect: Double, maxPixel: Int) -> CGImage {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1.5
        let m = max(8, min(maxPixel, 3600)), w = a >= 1 ? m : max(1, Int(Double(m) * a)), h = a >= 1 ? max(1, Int(Double(m) / a)) : m
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func colour(_ k: Int, _ v: CGFloat, _ s: CGFloat = 0.45) -> CGColor {
            let hue = CGFloat((seed * 47 + k * 131) % 360) / 360
            if bw { return CGColor(gray: v, alpha: 1) }
            let i = Int(hue * 6), f = hue * 6 - CGFloat(i), p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
            let (r, g, b) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        }
        let W = CGFloat(w), H = CGFloat(h), unit = min(W, H)
        let g = CGGradient(colorsSpace: cs, colors: [colour(0, 0.78), colour(1, 0.32)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
        // Sun.
        let d = unit * 0.42, cx = W * (0.3 + CGFloat(seed % 5) * 0.1), cy = H * (0.35 + CGFloat(seed % 3) * 0.12)
        ctx.setFillColor(colour(2, 0.92)); ctx.setAlpha(0.85)
        ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
        // Hills along the bottom (CG's origin is bottom-left), then foreground stripes.
        ctx.setAlpha(0.9)
        for k in 0..<3 {
            let hw = W * (0.55 + CGFloat((seed + k * 3) % 4) * 0.12), hh = H * (0.22 + CGFloat((seed + k) % 3) * 0.07)
            let hx = W * (CGFloat((seed * 7 + k * 37) % 100) / 100) - hw / 2
            ctx.setFillColor(colour(3 + k, 0.22 + CGFloat(k) * 0.07, 0.35))
            ctx.fillEllipse(in: CGRect(x: hx, y: -hh, width: hw, height: hh * 2))
        }
        ctx.setAlpha(0.35); ctx.setFillColor(colour(6, 0.95, 0.2))
        let stripes = 14, sw = max(1, unit / 260)
        for k in 0..<stripes {
            let x = W * (CGFloat(k) + 0.5) / CGFloat(stripes) + CGFloat((seed + k) % 3) * sw
            ctx.fill(CGRect(x: x, y: 0, width: sw, height: H * (0.04 + CGFloat((seed + k * 5) % 5) * 0.012)))
        }
        return ctx.makeImage()!
    }
}

/// Decoded pictures, least recently used out first, under a byte cap.
final class ImageCache: @unchecked Sendable {
    private struct Entry { var image: CGImage; var cost: Int; var tick: UInt64 }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var total = 0, tick: UInt64 = 0
    let limit: Int
    init(limit: Int) { self.limit = max(1, limit) }

    var bytes: Int { lock.withLock { total } }

    func get(_ key: String) -> CGImage? {
        lock.withLock {
            guard var e = entries[key] else { return nil }
            tick += 1; e.tick = tick; entries[key] = e
            return e.image
        }
    }

    func set(_ key: String, _ image: CGImage) {
        let cost = image.bytesPerRow * image.height
        lock.withLock {
            if let old = entries[key] { total -= old.cost }
            tick += 1; entries[key] = Entry(image: image, cost: cost, tick: tick); total += cost
            while total > limit, entries.count > 1, let oldest = entries.min(by: { $0.value.tick < $1.value.tick }), oldest.key != key {
                total -= oldest.value.cost; entries[oldest.key] = nil
            }
        }
    }
}
