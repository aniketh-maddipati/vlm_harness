import CoreGraphics
import Foundation

/// Port of `measure` from `design/handoff/lumina-cull/lumina-core.js`.
/// Preview → mean luminance 0–1, Laplacian variance (focus), % clipped pixels.
nonisolated struct CullCoreMeasure: Equatable {
    var luminance: Double
    var focus: Double
    var clip: Double

    /// Straight (un-premultiplied) RGBA8, row-major — what canvas `getImageData` returns.
    static func measure(rgba: [UInt8], width: Int, height: Int) -> CullCoreMeasure {
        let count = width * height
        var gray = [Float](repeating: 0, count: count)
        var sum = 0.0, clipped = 0
        for j in 0..<count {
            let i = j * 4
            let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
            let y = 0.299 * r + 0.587 * g + 0.114 * b
            gray[j] = Float(y)  // Float32Array store
            sum += y
            if rgba[i] >= 250 && rgba[i + 1] >= 250 && rgba[i + 2] >= 250 { clipped += 1 }
        }
        var m = 0.0, m2 = 0.0, k = 0.0
        if height > 2 && width > 2 {
            for yy in 1..<(height - 1) {
                for xx in 1..<(width - 1) {
                    let j = yy * width + xx
                    let l = 4 * Double(gray[j]) - Double(gray[j - 1]) - Double(gray[j + 1])
                        - Double(gray[j - width]) - Double(gray[j + width])
                    m += l; m2 += l * l; k += 1
                }
            }
        }
        let mean = m / k
        let pixels = Double(count)
        return CullCoreMeasure(luminance: sum / pixels / 255, focus: m2 / k - mean * mean, clip: 100 * Double(clipped) / pixels)
    }

    /// Draws the embedded preview into sRGB RGBA8 (as the prototype's canvas does) and measures it.
    /// ImageIO and Chrome decode JPEG slightly differently; the handoff allows 1% drift here.
    static func measure(_ image: CGImage) -> CullCoreMeasure? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? measure(rgba: rgba, width: width, height: height) : nil
    }
}
