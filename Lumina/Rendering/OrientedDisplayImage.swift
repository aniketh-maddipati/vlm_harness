import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Single orientation contract for every photograph that reaches Metal.
///
/// EXIF is baked into pixels **once** by ImageIO (`CreateThumbnailWithTransform`).
/// The CIImage wrapper never applies orientation again. Metal's
/// `CIRenderDestination.isFlipped` is the only remaining Y conversion
/// (Core Image is bottom-left; the drawable is top-left).
///
/// Click-through used to seed the drawable with a lazy file-backed CIImage
/// that still carried a pending orientation transform. Combined with the Metal
/// flip that presents inverted for a frame, then ImageIO pixels replace it,
/// then an unoriented RAW demosaic can swap landscape/portrait — the
/// upside-down flash and glitch.
nonisolated enum OrientedDisplayImage {

    private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    /// EXIF values that rotate the stored bitmap by 90° (width/height swap).
    static let swapDimensions: Set<UInt32> = [5, 6, 7, 8]

    struct FileOrientation: Equatable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let orientation: UInt32

        var orientedSize: (width: Int, height: Int) {
            OrientedDisplayImage.orientedSize(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                orientation: orientation
            )
        }
    }

    static func orientedSize(pixelWidth: Int, pixelHeight: Int, orientation: UInt32) -> (width: Int, height: Int) {
        if swapDimensions.contains(orientation) {
            return (pixelHeight, pixelWidth)
        }
        return (pixelWidth, pixelHeight)
    }

    static func fileOrientation(at url: URL) -> FileOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0 else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return FileOrientation(pixelWidth: w, pixelHeight: h, orientation: orientation)
    }

    /// ImageIO thumbnail with transform — pixels are already display-upright.
    static func cgImage(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        let ext = url.pathExtension.uppercased()
        guard !rawExtensions.contains(ext) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let source: CGImageSource? = {
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                return CGImageSourceCreateWithData(data as CFData, nil)
            }
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }()
        guard let source else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Wrap pixels that already have EXIF baked in. Do not apply the file
    /// orientation tag a second time — that is the inverted first-frame path.
    static func ciImage(fromOrientedPixels image: CGImage) -> CIImage {
        normalizeOrigin(CIImage(cgImage: image))
    }

    static func ciImage(at url: URL, maxPixelSize: Int? = nil) -> CIImage? {
        guard let cg = cgImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
        return ciImage(fromOrientedPixels: cg)
    }

    static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y
        ))
    }

    /// If a decoder left pixels in sensor space, rotate once to the file's EXIF.
    /// No-op when extent already matches the oriented display size.
    static func aligning(_ image: CIImage, toFile url: URL) -> CIImage {
        guard let file = fileOrientation(at: url), file.orientation != 1 else {
            return normalizeOrigin(image)
        }
        let current = image.extent
        guard current.width > 1, current.height > 1 else { return normalizeOrigin(image) }

        let oriented = file.orientedSize
        let orientedLong = CGFloat(max(oriented.width, oriented.height))
        guard orientedLong > 0 else { return normalizeOrigin(image) }
        let scale = max(current.width, current.height) / orientedLong
        let expectedW = CGFloat(oriented.width) * scale
        let expectedH = CGFloat(oriented.height) * scale
        if abs(current.width - expectedW) <= 2, abs(current.height - expectedH) <= 2 {
            return normalizeOrigin(image)
        }

        let sensorLong = CGFloat(max(file.pixelWidth, file.pixelHeight))
        guard sensorLong > 0 else { return normalizeOrigin(image) }
        let sensorScale = max(current.width, current.height) / sensorLong
        let sensorW = CGFloat(file.pixelWidth) * sensorScale
        let sensorH = CGFloat(file.pixelHeight) * sensorScale
        guard abs(current.width - sensorW) <= 2, abs(current.height - sensorH) <= 2 else {
            return normalizeOrigin(image)
        }
        guard let orientation = CGImagePropertyOrientation(rawValue: file.orientation) else {
            return normalizeOrigin(image)
        }
        return normalizeOrigin(image.oriented(orientation))
    }

    /// Keep the oriented browse frame on screen when a RAW promotion arrives
    /// in the opposite aspect (sensor-space demosaic). Quality may sharpen;
    /// the photograph may not rotate or stretch for a frame.
    static func stablePresent(promoted: CIImage?, fallback: CIImage?) -> CIImage? {
        guard let promoted else { return fallback }
        guard let fallback else { return promoted }
        let promotedPortrait = promoted.extent.width + 1 < promoted.extent.height
        let fallbackPortrait = fallback.extent.width + 1 < fallback.extent.height
        if promotedPortrait != fallbackPortrait {
            return fallback
        }
        return promoted
    }
}
