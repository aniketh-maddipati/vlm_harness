import Foundation
import CoreGraphics
import ImageIO

// WP-4. The package's picture source: generated demo photos and ImageIO for files. No look
// rendering yet (`look` is ignored); the app's adapter renders through the Look pipeline.

public enum ImageError: Error { case cannotOpen(String), injected }

public final class DefaultImageProvider: ImageProvider, @unchecked Sendable {
    public init() {}

    public func image(for photo: Photo, maxPixel: Int, look: Look?) async throws -> CGImage {
        if Faults.shared.has(.imageLoadFail) { throw ImageError.injected }
        if let ms = Faults.shared.slowDecodeMs { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
        switch photo.source {
        case .demo(let seed, let bw):
            return Self.demo(seed: seed, bw: bw, aspect: photo.aspect, maxPixel: maxPixel)
        case .file(let url):
            let opts: [CFString: Any] = [kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            else { throw ImageError.cannotOpen(photo.file) }
            return img
        case .remote:
            throw ImageError.cannotOpen(photo.file)
        }
    }
    public func preload(_ photos: [Photo], maxPixel: Int) {}
    public func cancelPreloads() {}

    /// A deterministic picture per seed: a two-colour gradient with a soft disc, so photos are
    /// tellable apart and edits are visible. No file, no network.
    public static func demo(seed: Int, bw: Bool, aspect: Double, maxPixel: Int) -> CGImage {
        let m = max(8, min(maxPixel, 2400)), w = aspect >= 1 ? m : max(1, Int(Double(m) * aspect)), h = aspect >= 1 ? max(1, Int(Double(m) / aspect)) : m
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func colour(_ k: Int, _ v: CGFloat) -> CGColor {
            let hue = CGFloat((seed * 47 + k * 131) % 360) / 360
            if bw { return CGColor(gray: v, alpha: 1) }
            let i = Int(hue * 6), f = hue * 6 - CGFloat(i), s: CGFloat = 0.45, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
            let (r, g, b) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        }
        let g = CGGradient(colorsSpace: cs, colors: [colour(0, 0.78), colour(1, 0.32)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
        let d = CGFloat(min(w, h)) * 0.42, cx = CGFloat(w) * (0.3 + CGFloat(seed % 5) * 0.1), cy = CGFloat(h) * (0.35 + CGFloat(seed % 3) * 0.12)
        ctx.setFillColor(colour(2, 0.92)); ctx.setAlpha(0.85)
        ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
        return ctx.makeImage()!
    }
}
