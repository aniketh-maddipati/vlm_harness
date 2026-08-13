import CoreImage
import Foundation

/// Gray-world auto white balance estimate.
///
/// Averages the image (CIAreaAverage), then derives a Kelvin/tint target from
/// the red/blue and green imbalance. This is the classic gray-world
/// assumption — a documented heuristic, not camera-metadata WB — and it is
/// labeled "Auto" in the UI accordingly.
enum AutoWhiteBalance {
    struct Estimate: Sendable {
        let kelvin: Double
        let tint: Double
    }

    static func estimate(imagePath: String) async -> Estimate? {
        let url = URL(fileURLWithPath: imagePath)
        return await Task.detached(priority: .userInitiated) { () -> Estimate? in
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                return nil
            }
            return estimate(from: image)
        }.value
    }

    static func estimate(from image: CIImage) -> Estimate? {
        let extent = image.extent
        guard extent.width > 4, extent.height > 4, extent.isInfinite == false else { return nil }

        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = DevelopRenderGraph.sharedContext
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255
        return estimate(r: r, g: g, b: b)
    }

    /// Gray-world Kelvin/tint from normalized channel averages (0…1).
    /// Rejects near-black samples (CI-area path).
    static func estimate(r: Double, g: Double, b: Double) -> Estimate? {
        guard r + g + b > 0.03 else { return nil }
        return grayWorld(r: r, g: g, b: b)
    }

    /// Shared gray-world formula used by CI-area and CPU-downsample auto paths.
    static func grayWorld(r: Double, g: Double, b: Double) -> Estimate {
        // Warm cast (r > b) → target cooler than neutral; cool cast → warmer.
        // ~130K per 1% channel imbalance, clamped to a plausible range.
        let neutral = EditRecipe.neutralTemperature
        let rbImbalance = (r - b) / max((r + b) / 2, 0.001)
        let kelvin = min(max(neutral - rbImbalance * neutral * 0.55, 3000), 9500)

        // Green/magenta: green above the r/b mean → push tint toward magenta.
        let gImbalance = (g - (r + b) / 2) / max((r + g + b) / 3, 0.001)
        let tint = min(max(-gImbalance * 120, -40), 40)

        return Estimate(kelvin: kelvin, tint: tint)
    }
}
