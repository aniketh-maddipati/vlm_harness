import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Exact pixel comparison with photo masks. Tolerance 0 means byte-equal RGBA.
enum Pixels {
    struct Rect: Codable { let x: Double; let y: Double; let w: Double; let h: Double }
    struct Result: Encodable {
        let width: Int, height: Int
        let differing: Int
        let maskedOut: Int
        let sizeMismatch: Bool
        let bbox: [Int]?          // x, y, w, h of all differing pixels
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }

    /// `masks` are in CSS px; `scale` converts to image pixels. Masks from either side are unioned.
    static func diff(_ a: CGImage, _ b: CGImage, masks: [Rect], scale: Double, tolerance: Int = 0, heatmap: URL?) -> Result {
        guard a.width == b.width, a.height == b.height else {
            return Result(width: a.width, height: a.height, differing: -1, maskedOut: 0, sizeMismatch: true, bbox: nil)
        }
        let w = a.width, h = a.height
        var masked = [Bool](repeating: false, count: w * h)
        for m in masks {
            let x0 = max(0, Int((m.x * scale).rounded(.down))), y0 = max(0, Int((m.y * scale).rounded(.down)))
            let x1 = min(w, Int(((m.x + m.w) * scale).rounded(.up))), y1 = min(h, Int(((m.y + m.h) * scale).rounded(.up)))
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { masked[y * w + x] = true } }
        }
        let pa = rgba(a), pb = rgba(b)
        var heat = heatmap == nil ? [] : pa.map { $0 / 4 }
        var n = 0, nm = 0, minX = w, minY = h, maxX = -1, maxY = -1
        for i in 0..<(w * h) {
            if masked[i] { nm += 1; continue }
            let o = i * 4
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(pa[o + c]) - Int(pb[o + c]))) }
            guard d > tolerance else { continue }
            n += 1
            let x = i % w, y = i / w
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            if heatmap != nil { heat[o] = 255; heat[o + 1] = 0; heat[o + 2] = 64; heat[o + 3] = 255 }
        }
        if let heatmap, n > 0 {
            heat.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                if let img = ctx.makeImage() { try? writePNG(img, to: heatmap) }
            }
        }
        return Result(width: w, height: h, differing: n, maskedOut: nm, sizeMismatch: false,
                      bbox: n > 0 ? [minX, minY, maxX - minX + 1, maxY - minY + 1] : nil)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ProbeError("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ProbeError("cannot write \(url.path)") }
    }

    static func readPNG(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ProbeError("cannot read \(url.path)")
        }
        return img
    }
}
