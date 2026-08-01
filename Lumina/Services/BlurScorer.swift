import AppKit
import Accelerate
import ImageIO

enum BlurScorer {
    /// Returns normalised sharpness in 0...1 (higher = sharper).
    static func score(imageURL: URL) -> Double {
        if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
                return score(cgImage: cg)
            }
        }
        guard let image = NSImage(contentsOf: imageURL),
              let cg = rasterisedCGImage(from: image) else {
            return 0
        }
        return score(cgImage: cg)
    }

    static func score(cgImage: CGImage) -> Double {
        let width = 320
        let height = Int(Double(cgImage.height) * (320.0 / Double(max(cgImage.width, 1))))
        guard height > 0,
              let resized = resize(cgImage, width: width, height: height),
              let gray = grayscale(resized) else {
            return 0
        }

        let variance = laplacianVariance(pixels: gray, width: width, height: height)
        // Empirical normalisation for embedded JPEG previews.
        let normalised = min(max(variance / 800.0, 0), 1)
        return normalised
    }

    private static func rasterisedCGImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func grayscale(_ image: CGImage) -> [Float]? {
        let width = image.width
        let height = image.height
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpp = image.bitsPerPixel / 8
        var gray = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * image.bytesPerRow + x * bpp
                let r = Float(ptr[offset])
                let g = Float(ptr[offset + 1])
                let b = Float(ptr[offset + 2])
                gray[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        return gray
    }

    private static func laplacianVariance(pixels: [Float], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let c = pixels[y * width + x]
                let lap = -4 * c
                    + pixels[(y - 1) * width + x]
                    + pixels[(y + 1) * width + x]
                    + pixels[y * width + (x - 1)]
                    + pixels[y * width + (x + 1)]
                let v = Double(lap)
                sum += v
                sumSq += v * v
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        return (sumSq / count) - (mean * mean)
    }
}
