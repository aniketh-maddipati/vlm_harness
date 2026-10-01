import SwiftUI
import LuminaCore

// WP-3. Cull's pictures: decoded off the main thread at the size they are shown × the backing
// scale, kept in a cache with a byte limit, and only a few decodes at a time so a fast scroll
// through 5,000 photos never queues work for tiles that have already gone by.

@MainActor
final class CullThumbs {
    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private let cache = NSCache<NSString, Box>()
    /// The last size decoded per photo, so the preview can show something at once.
    private var lastSize: [String: Int] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let limit = clamp(2, ProcessInfo.processInfo.activeProcessorCount - 2, 6)

    init() {
        cache.totalCostLimit = 192 << 20     // decoded bytes
        cache.countLimit = 6000
    }

    /// Pixels on the longest side for a photo of `aspect` shown in a `box` (points), filling it or
    /// shown whole. Rounded up to 80 px steps so a small resize doesn't decode everything again.
    static func pixels(aspect: CGFloat, box: CGSize, fill: Bool, scale: CGFloat) -> Int {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1.5
        let wide = a >= box.width / max(box.height, 1)
        // Fill: the photo covers the box; whole: it fits inside.
        let size = fill == wide ? CGSize(width: box.height * a, height: box.height) : CGSize(width: box.width, height: box.width / a)
        let px = max(size.width, size.height) * max(scale, 1)
        return min(2400, max(80, Int((px / 80).rounded(.up)) * 80))
    }

    private func key(_ photo: Photo, _ px: Int) -> NSString { "\(photo.id)|\(photo.source.hashValue)|\(px)" as NSString }

    func cached(_ photo: Photo, px: Int) -> CGImage? { cache.object(forKey: key(photo, px))?.image }

    /// Whatever is already decoded for this photo, at any size.
    func anyCached(_ photo: Photo) -> CGImage? { lastSize[photo.id].flatMap { cached(photo, px: $0) } }

    /// The picture, from the cache or decoded now. Nil when the task was cancelled (the tile
    /// scrolled away) or the file won't open.
    func load(_ photo: Photo, px: Int, images: any ImageProvider) async -> CGImage? {
        if let c = cached(photo, px: px) { return c }
        await acquire()
        defer { release() }
        if Task.isCancelled { return nil }
        if let c = cached(photo, px: px) { return c }
        guard let image = try? await images.image(for: photo, maxPixel: px, look: nil) else { return nil }
        cache.setObject(Box(image), forKey: key(photo, px), cost: image.bytesPerRow * image.height)
        lastSize[photo.id] = px
        return image
    }

    private func acquire() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// The newest request goes first: it is the one on screen now.
    private func release() {
        if let next = waiting.popLast() { next.resume() } else { running -= 1 }
    }
}

extension AppModel {
    var cullThumbs: CullThumbs { feature(CullThumbs.self) { CullThumbs() } }
}
