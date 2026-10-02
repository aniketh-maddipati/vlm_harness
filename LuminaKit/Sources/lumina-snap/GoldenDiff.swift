import Foundation
import CoreGraphics
import ImageIO

/// Golden vs native, pixel for pixel (CoreGraphics only). Both are drawn into the golden's pixel
/// size in sRGB over black, so a native capture at another size is scaled to it (and says so).
/// The rule is the manifest's: a pixel differs when any channel moves by more than `threshold`/255.
struct GoldenDiff {
    /// Mean absolute difference over R, G and B, 0…255.
    let mean: Double
    /// Share of pixels that differ, 0…1.
    let over: Double
    /// The native image was not at the golden's pixel size.
    let resized: Bool
    /// golden | native | diff, side by side. The diff is the golden dimmed, the differing pixels red.
    let sideBySide: CGImage

    init?(golden: CGImage, native: CGImage, threshold: Int = 16) {
        let w = golden.width, h = golden.height
        guard w > 0, h > 0, let a = Self.pixels(golden, w, h), let b = Self.pixels(native, w, h) else { return nil }
        var diff = [UInt8](repeating: 0, count: w * h * 4)
        var bad = 0, sum = 0
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in diff.withUnsafeMutableBufferPointer { pd in
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                let dr = abs(Int(pa[i]) - Int(pb[i])), dg = abs(Int(pa[i + 1]) - Int(pb[i + 1])), db = abs(Int(pa[i + 2]) - Int(pb[i + 2]))
                sum += dr + dg + db
                if max(dr, dg, db) > threshold { bad += 1; pd[i] = 255; pd[i + 1] = 0; pd[i + 2] = 0 }
                else { pd[i] = pa[i] / 4; pd[i + 1] = pa[i + 1] / 4; pd[i + 2] = pa[i + 2] / 4 }
                pd[i + 3] = 255
            }
        } } }
        mean = Double(sum) / Double(w * h * 3)
        over = Double(bad) / Double(w * h)
        resized = native.width != w || native.height != h
        guard let diffImage = Self.image(&diff, w, h), let side = Self.sideBySide([golden, native, diffImage], w, h) else { return nil }
        sideBySide = side
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let info = CGImageAlphaInfo.noneSkipLast.rawValue

    /// RGBX bytes of `image` drawn at w×h over black.
    private static func pixels(_ image: CGImage, _ w: Int, _ h: Int) -> [UInt8]? {
        var d = [UInt8](repeating: 0, count: w * h * 4)
        let ok = d.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB, bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? d : nil
    }

    private static func image(_ bytes: inout [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB, bitmapInfo: info)?.makeImage()
        }
    }

    private static func sideBySide(_ images: [CGImage], _ w: Int, _ h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w * images.count, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .high
        for (i, img) in images.enumerated() { ctx.draw(img, in: CGRect(x: i * w, y: 0, width: w, height: h)) }
        return ctx.makeImage()
    }
}
