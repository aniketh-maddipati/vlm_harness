import CoreGraphics
import CoreImage
import Foundation

/// The geometry that puts a photograph on the drawable, plus a headless probe of
/// the pixels that geometry produces.
///
/// `DevelopMetalView` calls `positioned(_:in:zoom:panOffset:backingScale:)` on its
/// draw path, so the transform a test inspects is the transform the drawable gets.
/// Without that shared definition a proof can only check a copy of the math, and a
/// copy is exactly what stops being true.
///
/// `probe` renders into a CPU bitmap through a `CIRenderDestination` with
/// `isFlipped = true` — the same destination flag `DevelopMetalView` sets — so row
/// zero of the buffer is the top of the photograph as displayed. A quadrant that
/// reads bright here is bright in that corner on screen.
nonisolated enum PhotoPresentProof {

    /// Aspect-fit into `drawableSize`, then optional 1:1 zoom and pan.
    ///
    /// `panOffset` is in points and `backingScale` converts it to drawable pixels;
    /// `y` is negated because the pan gesture is top-down and Core Image is bottom-up.
    static func positioned(
        _ image: CIImage,
        in drawableSize: CGSize,
        zoom: CGFloat = 1,
        panOffset: CGSize = .zero,
        backingScale: CGFloat = 1
    ) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              drawableSize.width > 1, drawableSize.height > 1 else { return nil }

        let fit = min(drawableSize.width / extent.width, drawableSize.height / extent.height)
        let scale = fit * zoom
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (drawableSize.width - scaled.extent.width) / 2 + panOffset.width * backingScale
        let dy = (drawableSize.height - scaled.extent.height) / 2 - panOffset.height * backingScale
        return scaled.transformed(by: CGAffineTransform(
            translationX: dx - scaled.extent.origin.x,
            y: dy - scaled.extent.origin.y
        ))
    }

    #if !LUMINA_SHIPPING_APP

    /// What a drawable of `drawableSize` would actually show, reduced to numbers.
    ///
    /// Quadrants are in display order — `[topLeft, topRight, bottomLeft, bottomRight]` —
    /// so an upside-down photograph swaps the top pair with the bottom pair.
    struct Probe: Equatable, Sendable {
        let width: Int
        let height: Int
        /// Mean luminance per display quadrant, over covered pixels only.
        let quadrants: [Double]
        /// Mean alpha over the whole drawable — how much of it the photograph covers.
        let coverage: Double
        /// Mean luminance over covered pixels.
        let mean: Double
        /// Spread between the brightest and darkest quadrant.
        let contrast: Double

        /// Nothing reached the drawable, or what reached it is a flat field.
        /// An empty well and a photograph that failed to decode both land here.
        var isBlank: Bool { coverage < 0.05 || contrast < 0.01 }

        /// Index into `quadrants`; `0` is the top-left of the photograph on screen.
        var brightestQuadrant: Int {
            var best = 0
            for index in quadrants.indices where quadrants[index] > quadrants[best] {
                best = index
            }
            return best
        }
    }

    private static let probeContext = CIContext(options: DevelopColorPolicy.ciContextOptions)

    /// Render `image` the way the develop view would and measure the result.
    /// Returns nil only when the render itself could not be started.
    static func probe(
        _ image: CIImage,
        drawableSize: CGSize,
        zoom: CGFloat = 1,
        panOffset: CGSize = .zero
    ) -> Probe? {
        guard let positioned = positioned(
            image,
            in: drawableSize,
            zoom: zoom,
            panOffset: panOffset
        ) else { return nil }

        let width = Int(drawableSize.width.rounded())
        let height = Int(drawableSize.height.rounded())
        guard width > 1, height > 1 else { return nil }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let destination = CIRenderDestination(
                bitmapData: base,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                format: .RGBA8
            )
            destination.colorSpace = DevelopColorPolicy.displayColorSpace
            // The drawable's own flag. Row zero is the top of the photograph.
            destination.isFlipped = true
            do {
                let task = try probeContext.startTask(toRender: positioned, to: destination)
                try task.waitUntilCompleted()
            } catch {
                return false
            }
            return true
        }
        guard rendered else { return nil }

        var sums = [Double](repeating: 0, count: 4)
        var counts = [Double](repeating: 0, count: 4)
        var alpha = 0.0
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            let half = y < height / 2 ? 0 : 2
            for x in 0..<width {
                let i = rowStart + x * 4
                let a = Double(bytes[i + 3]) / 255
                alpha += a
                guard a > 0.5 else { continue }
                let luminance = (
                    0.2126 * Double(bytes[i])
                        + 0.7152 * Double(bytes[i + 1])
                        + 0.0722 * Double(bytes[i + 2])
                ) / 255
                let quadrant = half + (x < width / 2 ? 0 : 1)
                sums[quadrant] += luminance
                counts[quadrant] += 1
            }
        }

        let quadrants = (0..<4).map { counts[$0] > 0 ? sums[$0] / counts[$0] : 0 }
        let covered = counts.reduce(0, +)
        return Probe(
            width: width,
            height: height,
            quadrants: quadrants,
            coverage: alpha / Double(width * height),
            mean: covered > 0 ? sums.reduce(0, +) / covered : 0,
            contrast: (quadrants.max() ?? 0) - (quadrants.min() ?? 0)
        )
    }

    #endif
}
