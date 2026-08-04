import CoreGraphics
import simd

/// Shared aspect-fit contract for Metal and SwiftUI photograph frames.
///
/// Contract: photographs are never stretched, squeezed, or silently cropped.
/// Lumina may add matte space; the fitted image is centered at true oriented aspect ratio.
enum AspectFitGeometry {

    /// Pixel-space fitted rectangle (origin top-left).
    struct FittedRect: Equatable, Sendable {
        let origin: CGPoint
        let size: CGSize

        var cgRect: CGRect { CGRect(origin: origin, size: size) }

        /// Normalized 0…1 in drawable space (origin top-left).
        var normalizedInDrawable: CGRect {
            guard drawableSize.width > 0, drawableSize.height > 0 else { return .zero }
            return CGRect(
                x: origin.x / drawableSize.width,
                y: origin.y / drawableSize.height,
                width: size.width / drawableSize.width,
                height: size.height / drawableSize.height
            )
        }

        fileprivate let drawableSize: CGSize
    }

    /// Metal quad vertices for a fitted image inside a drawable.
    struct MetalQuad: Equatable, Sendable {
        let positions: [SIMD2<Float>] // triangle strip, 4 vertices
        let uvs: [SIMD2<Float>]
    }

    /// Computes centered aspect-fit bounds.
    ///
    /// `scale = min(drawableWidth / imageWidth, drawableHeight / imageHeight)`
    static func fit(
        imageSize: CGSize,
        drawableSize: CGSize,
        tolerance: CGFloat = 1e-4
    ) -> FittedRect {
        guard imageSize.width > tolerance, imageSize.height > tolerance,
              drawableSize.width > tolerance, drawableSize.height > tolerance else {
            return FittedRect(origin: .zero, size: .zero, drawableSize: drawableSize)
        }

        let scale = min(
            drawableSize.width / imageSize.width,
            drawableSize.height / imageSize.height
        )
        let fittedW = imageSize.width * scale
        let fittedH = imageSize.height * scale
        let x = (drawableSize.width - fittedW) * 0.5
        let y = (drawableSize.height - fittedH) * 0.5
        return FittedRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: fittedW, height: fittedH),
            drawableSize: drawableSize
        )
    }

    static func aspectRatioPreserved(
        imageSize: CGSize,
        drawableSize: CGSize,
        fitted: FittedRect,
        tolerance: CGFloat = 1e-3
    ) -> Bool {
        guard imageSize.width > 0, imageSize.height > 0,
              fitted.size.width > 0, fitted.size.height > 0 else { return false }
        let imageAspect = imageSize.width / imageSize.height
        let fittedAspect = fitted.size.width / fitted.size.height
        guard abs(imageAspect - fittedAspect) <= tolerance else { return false }
        guard fitted.size.width <= drawableSize.width + tolerance,
              fitted.size.height <= drawableSize.height + tolerance else { return false }
        let expectedW = imageSize.width * min(
            drawableSize.width / imageSize.width,
            drawableSize.height / imageSize.height
        )
        return abs(fitted.size.width - expectedW) <= tolerance
    }

    /// Builds a triangle-strip quad in Metal NDC (-1…1), Y-up, UV origin top-left of image.
    static func metalQuad(for fitted: FittedRect) -> MetalQuad {
        let n = fitted.normalizedInDrawable
        let x0 = Float(n.minX * 2 - 1)
        let x1 = Float(n.maxX * 2 - 1)
        // Drawable origin is top-left; Metal NDC Y increases upward.
        let yTop = Float(1 - n.minY * 2)
        let yBottom = Float(1 - n.maxY * 2)

        let positions: [SIMD2<Float>] = [
            SIMD2(x0, yBottom),
            SIMD2(x1, yBottom),
            SIMD2(x0, yTop),
            SIMD2(x1, yTop),
        ]
        let uvs: [SIMD2<Float>] = [
            SIMD2(0, 1),
            SIMD2(1, 1),
            SIMD2(0, 0),
            SIMD2(1, 0),
        ]
        return MetalQuad(positions: positions, uvs: uvs)
    }

    /// Oriented display aspect (width / height) from pixel dimensions after EXIF rotation.
    static func orientedAspectRatio(width: Int, height: Int) -> CGFloat {
        guard width > 0, height > 0 else { return 3.0 / 2.0 }
        return CGFloat(width) / CGFloat(height)
    }
}

#if DEBUG
enum EXIFOrientationFixture {
    /// Expected dimension treatment when ImageIO applies `kCGImagePropertyOrientation`.
    static let swapDimensionsForOrientations: Set<UInt32> = [5, 6, 7, 8]

    static func orientedSize(rawWidth: Int, rawHeight: Int, orientation: UInt32) -> (Int, Int) {
        if swapDimensionsForOrientations.contains(orientation) {
            return (rawHeight, rawWidth)
        }
        return (rawWidth, rawHeight)
    }
}

enum AspectFitGeometrySelfTest {
    @discardableResult
    static func runAll() -> Bool {
        var ok = true
        ok = testLandscape() && ok
        ok = testPortrait() && ok
        ok = testSquare() && ok
        ok = testPanorama() && ok
        ok = testNarrowDrawable() && ok
        ok = runEXIFOrientationFixtures() && ok
        return ok
    }

    static func runEXIFOrientationFixtures() -> Bool {
        let raw = (4000, 6000)
        for orientation in UInt32(1)...UInt32(8) {
            let (w, h) = EXIFOrientationFixture.orientedSize(
                rawWidth: raw.0,
                rawHeight: raw.1,
                orientation: orientation
            )
            let aspect = AspectFitGeometry.orientedAspectRatio(width: w, height: h)
            let expectPortrait = [5, 6, 7, 8].contains(Int(orientation)) ? (6000.0 / 4000.0) : (4000.0 / 6000.0)
            if abs(aspect - expectPortrait) > 1e-3 { return false }
        }
        return true
    }

    private static func testLandscape() -> Bool {
        let image = CGSize(width: 3000, height: 2000)
        let drawable = CGSize(width: 1200, height: 800)
        let fitted = AspectFitGeometry.fit(imageSize: image, drawableSize: drawable)
        return AspectFitGeometry.aspectRatioPreserved(imageSize: image, drawableSize: drawable, fitted: fitted)
    }

    private static func testPortrait() -> Bool {
        let image = CGSize(width: 2000, height: 3000)
        let drawable = CGSize(width: 400, height: 900)
        let fitted = AspectFitGeometry.fit(imageSize: image, drawableSize: drawable)
        return AspectFitGeometry.aspectRatioPreserved(imageSize: image, drawableSize: drawable, fitted: fitted)
    }

    private static func testSquare() -> Bool {
        let image = CGSize(width: 1000, height: 1000)
        let drawable = CGSize(width: 800, height: 600)
        let fitted = AspectFitGeometry.fit(imageSize: image, drawableSize: drawable)
        return fitted.size.width == fitted.size.height
            && AspectFitGeometry.aspectRatioPreserved(imageSize: image, drawableSize: drawable, fitted: fitted)
    }

    private static func testPanorama() -> Bool {
        let image = CGSize(width: 6000, height: 1500)
        let drawable = CGSize(width: 1400, height: 700)
        let fitted = AspectFitGeometry.fit(imageSize: image, drawableSize: drawable)
        return abs(fitted.size.width - drawable.width) < 1
            && AspectFitGeometry.aspectRatioPreserved(imageSize: image, drawableSize: drawable, fitted: fitted)
    }

    private static func testNarrowDrawable() -> Bool {
        let image = CGSize(width: 1600, height: 900)
        let drawable = CGSize(width: 320, height: 900)
        let fitted = AspectFitGeometry.fit(imageSize: image, drawableSize: drawable)
        return abs(fitted.size.width - drawable.width) < 1
    }
}
#endif

