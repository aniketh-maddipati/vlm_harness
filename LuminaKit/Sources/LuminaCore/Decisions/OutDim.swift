import Foundation
import CoreGraphics

// WP-3. An Out photo's look (README §2 "Tiles", tokens `outDim`): `grayscale(1) brightness(0.7)`,
// baked into the pixels. SwiftUI's `.saturation` is a Core Animation filter, and a layer filter
// is not drawn by `cacheDisplay` (lumina-snap, the goldens), so the grey has to be in the picture
// itself to show everywhere. The views cross-fade to this picture over the 120 ms of `outDim`.

public enum OutDim {
    /// `brightness(0.7)`.
    public static let brightness: CGFloat = 0.7

    /// The picture in grey at 70 % brightness, same size. Nil only when a context can't be made.
    public static func image(_ source: CGImage) -> CGImage? {
        let w = source.width, h = source.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.interpolationQuality = .none
        ctx.draw(source, in: rect)                       // colour → grey by Core Graphics' conversion
        ctx.setFillColor(gray: 0, alpha: 1 - brightness) // × 0.7
        ctx.fill(rect)
        return ctx.makeImage()
    }
}
