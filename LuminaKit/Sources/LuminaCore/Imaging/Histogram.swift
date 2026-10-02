import Foundation
import CoreGraphics

// The Edit histogram's data (README §3, prototype `data-lumina="histogram"`). Optional, like
// `PixelSizing`: a provider that can measure a picture says so by conforming; without it Edit
// shows the prototype's estimate (`EditHistogram.estimate`).

/// A provider that can measure the luma histogram of a photo with a look applied.
public protocol HistogramProviding: AnyObject, Sendable {
    /// `LumaHistogram.bins` counts of the photo's luma with `look` applied, as shares of the
    /// pixels (they sum to 1). Nil when the photo can't be measured. Never on the main thread's time.
    func histogram(for photo: Photo, look: Look?) async -> [Float]?
}

public enum LumaHistogram {
    /// One bin per 8-bit level.
    public static let bins = 256
    /// Pictures are measured at this size on their longest side: enough for the shape and the clipping.
    public static let measurePixel = 256

    /// The luma histogram of `image` (Rec. 709 weights on the encoded values), as shares of the
    /// pixels. Drawn into an 8-bit sRGB buffer at most `maxPixel` on its longest side first.
    public static func compute(_ image: CGImage, maxPixel: Int = measurePixel) -> [Float]? {
        let w0 = image.width, h0 = image.height
        guard w0 > 0, h0 > 0 else { return nil }
        let k = min(1, Double(max(8, maxPixel)) / Double(max(w0, h0)))
        let w = max(1, Int((Double(w0) * k).rounded())), h = max(1, Int((Double(h0) * k).rounded()))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var counts = [Int](repeating: 0, count: bins)
        for i in 0..<(w * h) {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            // 0.2126 / 0.7152 / 0.0722 in 1/1024ths, rounded to the nearest level.
            let y = (218 * r + 732 * g + 74 * b + 512) >> 10
            counts[min(bins - 1, y)] += 1
        }
        let n = Float(w * h)
        return counts.map { Float($0) / n }
    }
}

extension DefaultImageProvider: HistogramProviding {
    /// The picture as the canvas would show it, small (the decode is cached like any other).
    public func histogram(for photo: Photo, look: Look?) async -> [Float]? {
        guard let img = try? await image(for: photo, maxPixel: LumaHistogram.measurePixel, look: look), !Task.isCancelled else { return nil }
        return LumaHistogram.compute(img)
    }
}
