import AppKit
import CoreGraphics
import CoreImage

/// Histogram from the displayed, color-managed result (not the RAW mosaic).
enum DevelopHistogram {
    struct Bins: Sendable {
        var red: [Int]
        var green: [Int]
        var blue: [Int]
        var luminance: [Int]
        static let empty = Bins(red: Array(repeating: 0, count: 256), green: Array(repeating: 0, count: 256), blue: Array(repeating: 0, count: 256), luminance: Array(repeating: 0, count: 256))
    }

    /// Downsamples to a small working bitmap then accumulates 256-level channels.
    static func compute(from cgImage: CGImage, maxSampleEdge: Int = 512) -> Bins {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return .empty }
        let scale = min(1, CGFloat(maxSampleEdge) / CGFloat(max(w, h)))
        let sw = max(1, Int(CGFloat(w) * scale))
        let sh = max(1, Int(CGFloat(h) * scale))
        let cs = DevelopColorPolicy.displayColorSpace
        guard let ctx = CGContext(
            data: nil,
            width: sw,
            height: sh,
            bitsPerComponent: 8,
            bytesPerRow: sw * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .empty }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let data = ctx.data else { return .empty }

        var bins = Bins.empty
        let ptr = data.bindMemory(to: UInt8.self, capacity: sw * sh * 4)
        for i in 0..<(sw * sh) {
            let o = i * 4
            let r = Int(ptr[o])
            let g = Int(ptr[o + 1])
            let b = Int(ptr[o + 2])
            bins.red[r] += 1
            bins.green[g] += 1
            bins.blue[b] += 1
            let y = min(255, Int(0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)))
            bins.luminance[y] += 1
        }
        return bins
    }
}
