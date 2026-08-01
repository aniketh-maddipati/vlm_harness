import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PreviewExtractor {
    /// Fast native preview extract — avoids spawning exiftool per file.
    static func extract(to destURL: URL, from rawURL: URL) throws {
        if extractWithImageIO(to: destURL, from: rawURL) {
            return
        }
        try ExifToolService.extractPreview(from: rawURL, to: destURL)
    }

    @discardableResult
    private static func extractWithImageIO(to destURL: URL, from rawURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil) else {
            return false
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }

        return writeJPEG(cgImage: image, to: destURL, quality: 0.85)
    }

    private static func writeJPEG(cgImage: CGImage, to url: URL, quality: CGFloat) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        let opts = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, cgImage, opts)
        return CGImageDestinationFinalize(dest)
    }
}
