import AppKit
import Foundation

/// Byte budgets for `PhotoImageCache` — **proposal awaiting contract ruling (W6)**.
/// Values are named here and in the RAM-tier ledger; not sealed in `tokens.yaml`.
nonisolated enum PhotoImageCacheBudget {
    /// Grid decode cap (`PhotoImageTier.gridMaxPixelSize` = 512).
    static let gridTierCeilingBytes = 48 * 1024 * 1024
    /// Preview / filmstrip decode cap (1600 px long edge).
    static let previewTierCeilingBytes = 96 * 1024 * 1024
    /// Proxy / unbounded decode path.
    static let proxyTierCeilingBytes = 128 * 1024 * 1024
    /// Combined LRU table ceiling across all tiers.
    static let totalCeilingBytes = 256 * 1024 * 1024

    /// The floor tier (`PhotoImageTier.floorLongEdge`, 256 px) — separate from
    /// the LRU above, evicted by distance from the viewport, never by recency.
    ///
    /// Why 64 MB. A 256 px 3:2 frame is ~175 KB, a square one ~262 KB, so the
    /// budget holds at least 256 frames and about 380 at 3:2. A 1280×800 table
    /// shows 20–40 tiles per screen, so that is six to nine screens either
    /// side of the viewport — well past the two screens the velocity prefetch
    /// looks ahead, and further than a flick travels before the tracker has a
    /// new centre. A 94-frame shoot fits whole (~16 MB); a 2000-frame shoot is
    /// a sliding window centred on the viewport. Bytes rather than a count so
    /// mixed aspects and squares stay bounded.
    static let floorCeilingBytes = 64 * 1024 * 1024
    /// Floor decodes in flight at once. Two keeps the warm of a 400-frame shoot
    /// under two seconds without starving the grid tier's decoders.
    static let floorDecodeWidth = 2

    /// Max concurrent prefetch decodes — width tied to `PreparedRawSession` capacity (4)
    /// doubled for grid+preview overlap without unbounded fan-out.
    static let prefetchConcurrencyWidth = 8
    /// Virtualized grid: visible cells plus this many items on each side.
    static let visiblePrefetchPadding = 8

    static func tierCeiling(maxPixelSize: Int?) -> Int {
        guard let maxPixelSize else { return proxyTierCeilingBytes }
        if maxPixelSize <= PhotoImageTier.gridMaxPixelSize { return gridTierCeilingBytes }
        if maxPixelSize <= 1600 { return previewTierCeilingBytes }
        return proxyTierCeilingBytes
    }

    static func memoryCost(of image: NSImage) -> Int {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return rep.bytesPerRow * rep.pixelsHigh
        }
        let w = max(image.size.width, 1)
        let h = max(image.size.height, 1)
        return Int(w * h * 4)
    }
}
