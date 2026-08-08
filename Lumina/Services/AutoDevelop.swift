import CoreGraphics
import Foundation
import ImageIO

/// Histogram-based auto edit.
///
/// Downsamples the photograph, computes luminance percentiles and mean
/// saturation on the CPU, and derives conservative tone targets:
/// median-anchored exposure, clip-aware highlight recovery, black-point
/// shadow lift, spread-based contrast, and a gentle vibrance floor.
/// White balance reuses the gray-world estimate. All values are absolute
/// targets from neutral — callers convert to offsets against the base recipe.
enum AutoDevelop {
    struct Suggestion: Sendable {
        var exposure: Double      // stops
        var contrast: Double      // -100...100
        var highlights: Double    // -100...100
        var shadows: Double       // -100...100
        var vibrance: Double      // -100...100
        var kelvin: Double        // absolute Kelvin
        var tint: Double          // -50...50
    }

    static func suggest(imagePath: String) async -> Suggestion? {
        await Task.detached(priority: .userInitiated) { () -> Suggestion? in
            computeSuggestion(imagePath: imagePath)
        }.value
    }

    private static func computeSuggestion(imagePath: String) -> Suggestion? {
        guard let stats = ImageStats(imagePath: imagePath, maxSide: 128) else { return nil }

        // Exposure: bring the median toward a mid-tone anchor (0.42 sRGB).
        let exposure = clamp(log2(0.42 / max(stats.p50, 0.01)), -1.5, 1.5)

        // Highlights: recover only when the bright tail is genuinely near clip.
        let highlights = stats.p95 > 0.92 ? -clamp((stats.p95 - 0.92) * 450, 0, 60) : 0

        // Shadows: lift crushed blacks, never past a gentle ceiling.
        let shadows = stats.p05 < 0.06 ? clamp((0.06 - stats.p05) * 500, 0, 45) : 0

        // Contrast: expand a flat tonal spread; leave punchy images alone.
        let spread = stats.p95 - stats.p05
        let contrast = spread < 0.62 ? clamp((0.62 - spread) * 90, 0, 30) : 0

        // Vibrance: nudge muted color; never touch already-saturated frames.
        let vibrance = stats.meanSaturation < 0.16
            ? clamp((0.16 - stats.meanSaturation) * 180, 0, 20)
            : 0

        // Gray-world white balance from the channel averages (shared heuristic).
        let wb = AutoWhiteBalance.grayWorld(r: stats.rAvg, g: stats.gAvg, b: stats.bAvg)

        return Suggestion(
            exposure: exposure,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            vibrance: vibrance,
            kelvin: wb.kelvin,
            tint: wb.tint
        )
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    // MARK: - Pixel statistics

    private struct ImageStats {
        var p05: Double
        var p50: Double
        var p95: Double
        var meanSaturation: Double
        var rAvg: Double
        var gAvg: Double
        var bAvg: Double

        init?(imagePath: String, maxSide: Int) {
            let url = URL(fileURLWithPath: imagePath) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxSide,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }

            let w = cg.width, h = cg.height
            guard w > 2, h > 2 else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(
                data: &buffer,
                width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            var lumas: [Double] = []
            lumas.reserveCapacity(w * h)
            var satSum = 0.0, rSum = 0.0, gSum = 0.0, bSum = 0.0
            for i in stride(from: 0, to: buffer.count, by: 4) {
                let r = Double(buffer[i]) / 255
                let g = Double(buffer[i + 1]) / 255
                let b = Double(buffer[i + 2]) / 255
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                let mx = max(r, g, b)
                satSum += mx > 0.02 ? (mx - min(r, g, b)) / mx : 0
                rSum += r; gSum += g; bSum += b
            }
            guard !lumas.isEmpty else { return nil }
            lumas.sort()
            let n = Double(lumas.count)
            func percentile(_ p: Double) -> Double {
                lumas[min(Int(p * n), lumas.count - 1)]
            }
            p05 = percentile(0.05)
            p50 = percentile(0.50)
            p95 = percentile(0.95)
            meanSaturation = satSum / n
            rAvg = rSum / n
            gAvg = gSum / n
            bAvg = bSum / n
            guard rAvg + gAvg + bAvg > 0.03 else { return nil }
        }
    }
}
