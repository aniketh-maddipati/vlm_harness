import CoreGraphics
import CoreVideo
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
        OrientedDisplayImage.fileOrientation(at: url)?.orientedSize
    }

    /// Preferred color space for a decoded still — embedded profile when ImageIO exposes it.
    static func colorSpace(for image: CGImage) -> CGColorSpace {
        image.colorSpace ?? workingColorSpace
    }
}
