import CoreGraphics
import Foundation
import ImageIO

/// Sensor dust across a shoot (`lumina.dust`): `LookDust` run on the photos' embedded previews as
/// stored, never a RAW decode. The bytes are the ones `SetsIngest` reads for the grid, so a pulled
/// card stops this as it stops every other read. Frames are grouped by stored size (one group per
/// body, in practice), since dust belongs to a sensor.
///
/// Positions come back twice: per group in the stored frame (where the dust is), and per photo
/// turned upright (where the page draws it).
///
/// Thread-safe. One search at a time at `.utility`; a new one waits for the last.
nonisolated final class SetsDust: @unchecked Sendable {
    /// The previews' long edge when measured. Sony's embedded previews are 1616 px wide, so this
    /// is about their own size: dust is a few pixels there and must not be scaled away.
    static let pixels = 1616
    /// The most frames one search reads (a few seconds each hundred at `.utility`).
    static let maxFrames = 400

    private let ingest: SetsIngest
    private let queue = OperationQueue()

    init(ingest: SetsIngest) {
        self.ingest = ingest
        queue.name = "lumina.dust"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
    }

    /// Finds dust across `previews` (the page picks them: one frame per stack, different scenes,
    /// stopped down where it can). Previews that can't be read are skipped and counted.
    func find(_ previews: [SetsIngest.Preview]) async -> [String: Any] {
        await withCheckedContinuation { (c: CheckedContinuation<[String: Any], Never>) in
            queue.addOperation { [weak self] in
                c.resume(returning: self?.run(Array(previews.prefix(Self.maxFrames))) ?? [:])
            }
        }
    }

    private func run(_ previews: [SetsIngest.Preview]) -> [String: Any] {
        struct Group { let acc: LookDust.Accumulator; var photos: [SetsIngest.Preview] }
        var groups: [String: Group] = [:]
        var order: [String] = []
        var unread = 0
        for p in previews {
            guard !ingest.isGone(p.rel), let jpeg = try? ingest.storedPreview(p), let luma = Self.luma(jpeg: jpeg) else { unread += 1; continue }
            let key = "\(luma.width)x\(luma.height)"
            if groups[key] == nil { groups[key] = Group(acc: LookDust.Accumulator(width: luma.width, height: luma.height), photos: []); order.append(key) }
            groups[key]?.acc.add(luma)
            groups[key]?.photos.append(p)
        }
        var outGroups: [[String: Any]] = []
        var photos: [String: [[String: Any]]] = [:]
        for key in order {
            guard let g = groups[key] else { continue }
            let spots = g.acc.spots()
            outGroups.append(["size": [g.acc.width, g.acc.height], "frames": g.acc.frames, "spots": spots.map(\.dictionary)])
            guard !spots.isEmpty else { continue }
            for p in g.photos { photos[p.rel] = spots.map { $0.upright(orientation: p.orientation).dictionary } }
        }
        let found = outGroups.reduce(0) { $0 + (($1["spots"] as? [Any])?.count ?? 0) }
        LuminaLog.app.info("dust: \(previews.count, privacy: .public) frames, \(unread, privacy: .public) unread, \(found, privacy: .public) spots")
        return ["frames": previews.count - unread, "unread": unread, "groups": outGroups, "photos": photos]
    }

    /// Linear luma of a JPEG as stored (not turned), at most `pixels` on the long edge.
    static func luma(jpeg: Data, pixels: Int = SetsDust.pixels) -> LookDust.Plane? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: false,
                                     kCGImageSourceThumbnailMaxPixelSize: pixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return luma(image)
    }

    /// Drawn into a linear grey float bitmap: Core Graphics converts from the JPEG's own colour space.
    /// Float components are big-endian unless the byte order says otherwise; Swift's Float is little.
    static func luma(_ image: CGImage) -> LookDust.Plane? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.linearGray) else { return nil }
        var px = [Float](repeating: 0, count: w * h)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.floatComponents.rawValue
                                                  | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? LookDust.Plane(width: w, height: h, px: px) : nil
    }
}
