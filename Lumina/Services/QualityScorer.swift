import Foundation
import ImageIO
import CoreGraphics

enum QualityScorer {
    /// 0…1 — high when histogram isn't heavily clipped.
    static func exposureHealth(imageURL: URL) -> Double {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return 0.5 }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }

        let w = cg.width
        let h = cg.height
        let bpp = max(cg.bitsPerPixel / 8, 1)
        var dark = 0
        var bright = 0
        var total = 0
        let step = max(1, (w * h) / 2000)

        var i = 0
        while i < w * h {
            let o = (i % w) * bpp + (i / w) * cg.bytesPerRow
            if o + 2 < CFDataGetLength(data) {
                let y = 0.299 * Double(ptr[o]) + 0.587 * Double(ptr[o + 1]) + 0.114 * Double(ptr[o + 2])
                if y < 12 { dark += 1 }
                if y > 243 { bright += 1 }
                total += 1
            }
            i += step
        }
        guard total > 0 else { return 0.5 }
        let clip = Double(dark + bright) / Double(total)
        return min(max(1.0 - clip * 2.5, 0), 1)
    }

    /// Exposure from an already-decoded thumbnail — avoids a second ImageIO pass.
    static func exposureHealth(cgImage: CGImage) -> Double {
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }

        let w = cgImage.width
        let h = cgImage.height
        let bpp = max(cgImage.bitsPerPixel / 8, 1)
        var dark = 0
        var bright = 0
        var total = 0
        let step = max(1, (w * h) / 2000)

        var i = 0
        while i < w * h {
            let o = (i % w) * bpp + (i / w) * cgImage.bytesPerRow
            if o + 2 < CFDataGetLength(data) {
                let y = 0.299 * Double(ptr[o]) + 0.587 * Double(ptr[o + 1]) + 0.114 * Double(ptr[o + 2])
                if y < 12 { dark += 1 }
                if y > 243 { bright += 1 }
                total += 1
            }
            i += step
        }
        guard total > 0 else { return 0.5 }
        let clip = Double(dark + bright) / Double(total)
        return min(max(1.0 - clip * 2.5, 0), 1)
    }
}
