import CoreGraphics
import Foundation

/// Deterministic per-frame measurements that `AutoDevelop` turns into a recipe.
///
/// Everything here is an observation, never a decision: no field depends on the
/// photographer's cull, recipe, or taste. Stats are computed once from the
/// interactive-tier RAW render and cached on `AssetRecord.imageStats`, so the
/// same frame always yields the same numbers and therefore the same auto recipe.
nonisolated struct ImageStats: Codable, Hashable, Sendable {
    static let binCount = 32
    /// Clip thresholds in 0…1, matching the 6/255 and 249/255 the design specifies.
    static let shadowClipThreshold = 6.0 / 255.0
    static let highlightClipThreshold = 249.0 / 255.0

    /// Luminance histogram, `binCount` bins over 0…1 (Rec.709 weights).
    var luminanceBins: [Int]
    /// Fraction of sampled pixels below `shadowClipThreshold`.
    var shadowClipFraction: Double
    /// Fraction of sampled pixels above `highlightClipThreshold`.
    var highlightClipFraction: Double
    /// Mean luminance in 0…1.
    var mean: Double
    /// As-shot white balance from the RAW decoder, when the file carries one.
    var nativeTemperature: Double?
    /// Horizon tilt in degrees from Vision, when it found one confidently.
    var horizonAngle: Double?

    init(
        luminanceBins: [Int] = Array(repeating: 0, count: ImageStats.binCount),
        shadowClipFraction: Double = 0,
        highlightClipFraction: Double = 0,
        mean: Double = 0,
        nativeTemperature: Double? = nil,
        horizonAngle: Double? = nil
    ) {
        self.luminanceBins = luminanceBins
        self.shadowClipFraction = shadowClipFraction
        self.highlightClipFraction = highlightClipFraction
        self.mean = mean
        self.nativeTemperature = nativeTemperature
        self.horizonAngle = horizonAngle
    }

    var sampleCount: Int { luminanceBins.reduce(0, +) }

    /// Measures a color-managed bitmap. Returns nil when there is nothing to measure.
    ///
    /// The caller decides which tier's pixels to hand over; this does no decoding of
    /// its own so it stays off the render data plane's actor.
    static func measure(cgImage: CGImage, maxSampleEdge: Int = 256) -> ImageStats? {
        let scale = min(
            1.0,
            Double(maxSampleEdge) / Double(max(cgImage.width, cgImage.height, 1))
        )
        let width = max(1, Int((Double(cgImage.width) * scale).rounded()))
        let height = max(1, Int((Double(cgImage.height) * scale).rounded()))
        guard width > 1, height > 1 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: DevelopColorPolicy.displayColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var bins = [Int](repeating: 0, count: binCount)
        var lowClipped = 0
        var highClipped = 0
        var luminanceSum = 0.0
        var samples = 0

        for index in stride(from: 0, to: buffer.count, by: 4) {
            let r = Double(buffer[index]) / 255
            let g = Double(buffer[index + 1]) / 255
            let b = Double(buffer[index + 2]) / 255
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let bin = min(binCount - 1, max(0, Int(luminance * Double(binCount))))
            bins[bin] += 1
            if luminance < shadowClipThreshold { lowClipped += 1 }
            if luminance > highlightClipThreshold { highClipped += 1 }
            luminanceSum += luminance
            samples += 1
        }

        guard samples > 0 else { return nil }
        let total = Double(samples)
        return ImageStats(
            luminanceBins: bins,
            shadowClipFraction: Double(lowClipped) / total,
            highlightClipFraction: Double(highClipped) / total,
            mean: luminanceSum / total
        )
    }

    /// Returns a copy carrying the decoder's as-shot Kelvin and a Vision horizon estimate.
    func withCameraContext(nativeTemperature: Double?, horizonAngle: Double?) -> ImageStats {
        var copy = self
        copy.nativeTemperature = nativeTemperature
        copy.horizonAngle = horizonAngle
        return copy
    }
}
