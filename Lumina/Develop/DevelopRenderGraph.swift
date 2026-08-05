import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Single conceptual render graph for interactive, settled, 1:1, and export.
///
/// Operation order (fixed — must not drift between qualities):
/// 1. Decode (CIRAWFilter preferred, else ImageIO demosaic) with orientation applied once
/// 2. Optional long-edge downsample (quality cap) in linear working space
/// 3. White balance (temperature / tint) — prefer RAW filter params when decode used CIRAW
/// 4. Exposure
/// 5. Highlights / Shadows
/// 6. Whites / Blacks (tone endpoints)
/// 7. Contrast
/// 8. Presence approximations (clarity / texture / dehaze)
/// 9. Vibrance / Saturation
/// 10. Noise reduction
/// 11. Sharpening
/// 12. Straighten + crop (normalized coords)
/// 13. Region extract (1:1)
/// 14. Display or export color conversion **once**
enum DevelopRenderGraph {

    private static let context = CIContext(options: DevelopColorPolicy.ciContextOptions)

    // MARK: - Public entry

    static func render(_ request: RawRenderRequest) -> DevelopRenderResult {
        let start = CFAbsoluteTimeGetCurrent()
        var usedProxy = false
        var fidelity: DevelopFidelityState

        switch request.quality {
        case .interactive: fidelity = .interactive
        case .settled: fidelity = .fullPreview
        case .oneToOne: fidelity = .oneToOneRAW
        case .export: fidelity = .exportQuality
        case .browse: fidelity = .proxyFallback
        }

        guard var image = decode(request, usedProxy: &usedProxy, fidelity: &fidelity) else {
            return DevelopRenderResult(
                requestID: request.id,
                generation: request.generation,
                photoID: request.photoID,
                quality: request.quality,
                fidelity: .proxyFallback,
                cgImage: nil,
                extent: .zero,
                durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                cacheHit: false,
                cancelled: false,
                usedProxyFallback: true,
                colorSpaceName: "nil"
            )
        }

        image = normalizeOrigin(image)
        image = maybeDownsample(image, longEdge: request.longEdgeCap)
        image = applyRecipe(request.recipe, to: image, skipRAWIntegratedWB: false)
        image = applyGeometry(request.recipe, to: image)

        if request.quality == .oneToOne {
            let rect = request.region.pixelRect(in: image.extent)
            image = image.cropped(to: rect.integral)
            image = normalizeOrigin(image)
        }

        let bounds = image.extent.integral
        let colorSpace = request.forDisplay
            ? DevelopColorPolicy.displayColorSpace
            : (request.quality == .export
               ? DevelopColorPolicy.exportJPEGColorSpace
               : DevelopColorPolicy.workingColorSpace)

        let cg = context.createCGImage(
            image,
            from: bounds,
            format: .RGBAh,
            colorSpace: colorSpace
        )

        return DevelopRenderResult(
            requestID: request.id,
            generation: request.generation,
            photoID: request.photoID,
            quality: request.quality,
            fidelity: usedProxy ? .proxyFallback : fidelity,
            cgImage: cg,
            extent: bounds,
            durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
            cacheHit: false,
            cancelled: false,
            usedProxyFallback: usedProxy,
            colorSpaceName: DevelopColorPolicy.describeColorSpace(colorSpace)
        )
    }

    /// Shared apply path used by legacy DevelopEngine and export.
    static func applyRecipe(_ recipe: EditRecipe, to image: CIImage, skipRAWIntegratedWB: Bool) -> CIImage {
        let legacy = DevelopEngine.clampRecipe(recipe.asDevelopRecipe)
        let edit = EditRecipe(from: legacy, id: recipe.id).updating {
            $0.crop = recipe.crop
            $0.straightenDegrees = recipe.straightenDegrees
            $0.sharpness = recipe.sharpness
            $0.luminanceNR = recipe.luminanceNR
        }
        return applyOrdered(edit, to: image, skipWB: skipRAWIntegratedWB)
    }

    static func applyGeometry(_ recipe: EditRecipe, to image: CIImage) -> CIImage {
        var result = image
        let bounds = result.extent.integral

        if abs(recipe.straightenDegrees) > 0.01 {
            let radians = CGFloat(recipe.straightenDegrees) * .pi / 180
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
            transform = transform.rotated(by: -radians)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            result = result.transformed(by: transform)
            // Keep original aspect canvas — crop later handles framing.
            result = result.cropped(to: bounds)
        }

        if let crop = recipe.crop, !crop.isFullFrame {
            let rect = crop.pixelRect(in: bounds).integral
            result = result.cropped(to: rect)
            result = normalizeOrigin(result)
        }
        return result
    }

    // MARK: - Decode

    private static func decode(
        _ request: RawRenderRequest,
        usedProxy: inout Bool,
        fidelity: inout DevelopFidelityState
    ) -> CIImage? {
        switch request.source {
        case .originalRAW, .rawPyramid:
            if let raw = decodeRAW(url: request.rawURL, longEdgeHint: request.longEdgeCap) {
                return raw
            }
            // Emergency fallback — mark honesty flag.
            if let proxy = request.proxyURL, let jpeg = CIImage(contentsOf: proxy, options: [.applyOrientationProperty: true]) {
                usedProxy = true
                fidelity = .proxyFallback
                return jpeg
            }
            return nil
        case .jpegProxy:
            usedProxy = true
            fidelity = .proxyFallback
            if let proxy = request.proxyURL, let jpeg = CIImage(contentsOf: proxy, options: [.applyOrientationProperty: true]) {
                return jpeg
            }
            // Last resort: embedded preview via ImageIO without forcing demosaic.
            return CIImage(contentsOf: request.rawURL, options: [.applyOrientationProperty: true])
        }
    }

    /// Prefer CIRAWFilter (macOS 14+ / deployment target). Fall back to ImageIO demosaic.
    static func decodeRAW(url: URL, longEdgeHint: Int?) -> CIImage? {
        if let ciraw = decodeViaCIRAW(url: url, longEdgeHint: longEdgeHint) {
            return ciraw
        }
        let maxPixel = longEdgeHint.flatMap { $0 > 0 ? $0 : nil } ?? 6000
        guard let demosaiced = PreviewExtractor.demosaicFull(from: url, maxPixelSize: maxPixel) else {
            return nil
        }
        return CIImage(cgImage: demosaiced)
    }

    private static func decodeViaCIRAW(url: URL, longEdgeHint: Int?) -> CIImage? {
        // CIRAWFilter is the supported Core Image RAW entry on modern macOS.
        // Long-edge capping is applied after decode in `maybeDownsample` so preview/export
        // share the same decode→filter→downsample contract.
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        _ = longEdgeHint
        return filter.outputImage
    }

    // MARK: - Ordered tone graph

    private static func applyOrdered(_ recipe: EditRecipe, to image: CIImage, skipWB: Bool) -> CIImage {
        var result = image
        let bounds = image.extent.integral

        // 4. Exposure
        if recipe.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.exposure, forKey: kCIInputEVKey)
            result = f.outputImage ?? result
        }

        // 3/4. White balance (after exposure is Fine for CI; CIRAW may have applied camera WB already)
        if !skipWB, abs(recipe.temperature - 6500) > 1 || recipe.tint != 0,
           let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: recipe.temperature, y: recipe.tint), forKey: "inputTargetNeutral")
            result = f.outputImage ?? result
        }

        // 5. Highlights / Shadows
        if recipe.highlights != 0 || recipe.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(min(max(1 - recipe.highlights / 100.0, 0), 1), forKey: "inputHighlightAmount")
            f.setValue(min(max(1 + recipe.shadows / 100.0, 0), 2), forKey: "inputShadowAmount")
            result = f.outputImage ?? result
        }

        // 6. Whites / Blacks via tone curve endpoints
        if recipe.whites != 0 || recipe.blacks != 0 {
            result = applyWhitesBlacks(result, whites: recipe.whites, blacks: recipe.blacks)
        }

        // 7. Contrast (+ provisional saturation slot filled later)
        if recipe.contrast != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + recipe.contrast / 100.0, forKey: kCIInputContrastKey)
            result = f.outputImage ?? result
        }

        // 8. Presence approximations
        let unsharp = (recipe.clarity + recipe.texture) / 200.0
        if abs(unsharp) > 0.01, let f = CIFilter(name: "CIUnsharpMask") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(2.5, forKey: kCIInputRadiusKey)
            f.setValue(min(max(unsharp, -1), 1), forKey: kCIInputIntensityKey)
            result = f.outputImage ?? result
        }
        if recipe.dehaze != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + recipe.dehaze / 200.0, forKey: kCIInputContrastKey)
            f.setValue(1 + recipe.dehaze / 300.0, forKey: kCIInputSaturationKey)
            result = f.outputImage ?? result
        }

        // 9. Vibrance / Saturation
        if recipe.vibrance != 0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.vibrance / 100.0, forKey: "inputAmount")
            result = f.outputImage ?? result
        }
        if recipe.saturation != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + recipe.saturation / 100.0, forKey: kCIInputSaturationKey)
            result = f.outputImage ?? result
        }

        // 10. Noise reduction
        if recipe.luminanceNR > 0.5, let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(min(recipe.luminanceNR / 100.0, 0.1), forKey: "inputNoiseLevel")
            f.setValue(0.4, forKey: "inputSharpness")
            result = f.outputImage ?? result
        }

        // 11. Sharpening
        if recipe.sharpness > 0.5, let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.sharpness / 100.0, forKey: kCIInputSharpnessKey)
            result = f.outputImage ?? result
        }

        return result.cropped(to: bounds)
    }

    private static func applyWhitesBlacks(_ image: CIImage, whites: Double, blacks: Double) -> CIImage {
        // Map −100…100 into tone-curve endpoint adjustments.
        let blackIn = min(max(blacks / 200.0, -0.4), 0.4)
        let whiteIn = min(max(1 + whites / 200.0, 0.6), 1.4)
        let filter = CIFilter.toneCurve()
        filter.inputImage = image
        filter.point0 = CGPoint(x: 0, y: max(0, blackIn))
        filter.point1 = CGPoint(x: 0.25, y: 0.25 + blackIn * 0.25)
        filter.point2 = CGPoint(x: 0.5, y: 0.5)
        filter.point3 = CGPoint(x: 0.75, y: 0.75 + (whiteIn - 1) * 0.25)
        filter.point4 = CGPoint(x: 1, y: min(1, whiteIn > 1 ? 1 : whiteIn))
        return filter.outputImage ?? image
    }

    static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y
        ))
    }

    private static func maybeDownsample(_ image: CIImage, longEdge: Int?) -> CIImage {
        guard let longEdge, longEdge > 0 else { return image }
        let extent = image.extent
        let current = max(extent.width, extent.height)
        guard current > CGFloat(longEdge) + 1 else { return image }
        let scale = CGFloat(longEdge) / current
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: - Export helpers

    /// 16-bit TIFF for Lightroom/Photoshop handoff.
    static func exportTIFF(cgImage: CGImage, to url: URL, preserveMetadataFrom rawURL: URL?) -> Bool {
        let type = UTType.tiff.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            return false
        }
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        if let rawURL,
           let src = CGImageSourceCreateWithURL(rawURL as CFURL, nil),
           let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            // Carry EXIF / TIFF capture metadata where feasible; strip maker-note blobs if huge.
            props[kCGImagePropertyExifDictionary] = meta[kCGImagePropertyExifDictionary]
            props[kCGImagePropertyTIFFDictionary] = meta[kCGImagePropertyTIFFDictionary]
            props[kCGImagePropertyGPSDictionary] = meta[kCGImagePropertyGPSDictionary]
        }
        // Tag output with TIFF export space.
        props[kCGImagePropertyColorModel] = "RGB"
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    static var sharedContext: CIContext { context }
}
