import AppKit
import Foundation

/// Byte budgets for `PhotoImageCache` — **proposal awaiting contract ruling (W6)**.
/// Values are named here and in the RAM-tier ledger; not sealed in `tokens.yaml`.
enum PhotoImageCacheBudget {
    /// Grid decode cap (`PhotoImageTier.gridMaxPixelSize` = 512).
    static let gridTierCeilingBytes = 48 * 1024 * 1024
    /// Preview / filmstrip decode cap (1600 px long edge).
    static let previewTierCeilingBytes = 96 * 1024 * 1024
    /// Proxy / unbounded decode path.
    static let proxyTierCeilingBytes = 128 * 1024 * 1024
    /// Combined LRU table ceiling across all tiers.
    static let totalCeilingBytes = 256 * 1024 * 1024

    /// Max concurrent prefetch decodes — width tied to `PreparedRawSession` capacity (4)
    /// doubled for grid+preview overlap without unbounded fan-out.
    static let prefetchConcurrencyWidth = 8

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
