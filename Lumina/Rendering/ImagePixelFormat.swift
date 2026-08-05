import CoreGraphics
import CoreVideo
import ImageIO
import Metal

/// Canonical browse-path pixel representation for Metal and Core Image.
///
/// - Storage: `kCVPixelFormatType_32BGRA` / `MTLPixelFormat.bgra8Unorm`
/// - Channel order in memory: B, G, R, A (little-endian BGRA)
/// - Alpha: straight alpha; opaque photograph pixels use A = 255
/// - Working space: sRGB for decode/blit when embedded ICC is absent
/// - Display: respects embedded ICC/profile through ImageIO decode; never `deviceRGB` as silent default
enum ImagePixelFormat {
    static let metalPixelFormat: MTLPixelFormat = .bgra8Unorm
    static let pixelBufferType: OSType = kCVPixelFormatType_32BGRA

    static let workingColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let displayColorSpace: CGColorSpace = {
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3) { return p3 }
        return workingColorSpace
    }()

    /// Reads oriented pixel dimensions after applying EXIF orientation exactly once via ImageIO.
    static func orientedPixelSize(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        var w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0 else { return nil }

        if let orientation = props[kCGImagePropertyOrientation] as? UInt32,
           (5...8).contains(orientation) {
            swap(&w, &h)
        }
        return (w, h)
    }

    /// Preferred color space for a decoded still — embedded profile when ImageIO exposes it.
    static func colorSpace(for image: CGImage) -> CGColorSpace {
        image.colorSpace ?? workingColorSpace
    }
}
