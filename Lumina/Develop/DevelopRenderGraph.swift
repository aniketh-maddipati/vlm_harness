import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Single conceptual render graph for interactive, RAW-settled, 1:1, and export.
///
/// Stage order (fixed — must not drift between tiers):
/// 1. RAW stage — `CIRAWFilter` owns demosaic, camera/neutral white balance,
///    RAW exposure, RAW noise reduction and capture sharpening. Applied through
///    `PreparedRawSession`; reduced scale goes through `CIRAWFilter.scaleFactor`
///    so a full-size image is never decoded just to be thrown away.
/// 2. Look stage — scene-linear Core Image graph for the small honest set:
///    highlights/shadows (documented approximation), contrast, vibrance, saturation.
///    Whites/blacks/clarity/texture/dehaze are **not rendered**; their controls
///    are disabled and their stored values migrate without effect.
/// 3. Geometry — straighten + crop in normalized coordinates.
/// 4. Region extract (1:1).
/// 5. Output conversion **once** — display profile at the Metal destination, or
///    export space during encode.
enum DevelopRenderGraph {

    /// Long-lived shared contexts — never allocate per frame.
    private static let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
    private static let exportContext = CIContext(options: DevelopColorPolicy.ciContextOptions)

    static var sharedContext: CIContext { context }
    static var sharedExportContext: CIContext { exportContext }

    // MARK: - Public entry

    static func render(_ request: RawRenderRequest) async -> DevelopRenderResult {
        let start = CFAbsoluteTimeGetCurrent()
        var usedProxy = false
        var rawStageCacheHit = false
        var fidelity: DevelopFidelityState

        switch request.quality {
        case .interactive: fidelity = .interactive
        case .settled: fidelity = .rawSettled
        case .oneToOne: fidelity = .oneToOneRAW
        case .export: fidelity = .exportQuality
        case .browse: fidelity = .proxyFallback
        }

        guard var image = await decode(
            request,
            usedProxy: &usedProxy,
            fidelity: &fidelity,
            rawStageCacheHit: &rawStageCacheHit
        ) else {
            return DevelopRenderResult(
                requestID: request.id,
                generation: request.generation,
                photoID: request.photoID,
                preparedSessionID: request.preparedSessionID,
                recipeRevision: request.recipeRevision,
                displayProfileID: request.displayProfileID,
                quality: request.quality,
                fidelity: .proxyFallback,
                ciImage: nil,
                cgImage: nil,
                extent: .zero,
                durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                cacheHit: false,
                rawStageCacheHit: false,
                cancelled: false,
                usedProxyFallback: true,
                colorSpaceName: "nil",
                inputEventAt: request.inputEventAt
            )
        }

        image = normalizeOrigin(image)
        image = maybeDownsample(image, longEdge: request.longEdgeCap)

        if usedProxy {
            // Rendered compatibility fallback: approximate the whole recipe with
            // generic CI filters (includes retouch). Never labeled RAW-settled
            // or export-equivalent.
            image = applyProxyApproximation(request.recipe, to: image)
        } else {
            // RAW stage already carries RawIntent — apply look, then heal spots.
            image = applyLook(request.recipe.lookIntent, to: image)
            image = applyRetouch(request.recipe.retouch, to: image)
        }
        image = applyGeometry(request.recipe, to: image)

        if request.quality == .oneToOne {
            let rect = request.region.pixelRect(in: image.extent)
            image = image.cropped(to: rect.integral)
            image = normalizeOrigin(image)
        }

        let bounds = image.extent.integral

        // Display path stays CIImage → Metal; CGImage is materialized only where
        // a bitmap is genuinely needed (export encode, histogram on settled).
        var cg: CGImage?
        var colorSpaceName = "linear-working (deferred display conversion)"
        if !request.forDisplay {
            let space = request.quality == .export
                ? DevelopColorPolicy.exportTIFFColorSpace
                : DevelopColorPolicy.workingColorSpace
            cg = exportContext.createCGImage(image, from: bounds, format: .RGBA16, colorSpace: space)
            colorSpaceName = DevelopColorPolicy.describeColorSpace(space)
        } else if request.quality == .settled || request.quality == .oneToOne {
            // Small settled bitmap for histogram / harness use.
            let space = DevelopColorPolicy.displayColorSpace
            cg = context.createCGImage(image, from: bounds, format: .RGBAh, colorSpace: space)
            colorSpaceName = DevelopColorPolicy.describeColorSpace(space)
        }

        return DevelopRenderResult(
            requestID: request.id,
            generation: request.generation,
            photoID: request.photoID,
            preparedSessionID: request.preparedSessionID,
            recipeRevision: request.recipeRevision,
            displayProfileID: request.displayProfileID,
            quality: request.quality,
            fidelity: usedProxy ? .proxyFallback : fidelity,
            ciImage: image,
            cgImage: cg,
            extent: bounds,
            durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
            cacheHit: false,
            rawStageCacheHit: rawStageCacheHit,
            cancelled: false,
            usedProxyFallback: usedProxy,
            colorSpaceName: colorSpaceName,
            inputEventAt: request.inputEventAt
        )
    }

    // MARK: - Decode

    private static func decode(
        _ request: RawRenderRequest,
        usedProxy: inout Bool,
        fidelity: inout DevelopFidelityState,
        rawStageCacheHit: inout Bool
    ) async -> CIImage? {
        switch request.source {
        case .originalRAW, .rawPyramid:
            let session = await PreparedRawSessionRegistry.shared.session(
                for: request.photoID,
                rawURL: request.rawURL
            )
            let tier: PreparedRawSession.Tier = request.quality == .interactive ? .interactive : .authoritative
            let target = (request.longEdgeCap ?? 0) > 0 ? request.longEdgeCap : nil
            if let staged = await session.rawStageImage(
                intent: request.recipe.rawIntent,
                targetLongEdge: target,
                tier: tier
            ) {
                rawStageCacheHit = staged.cacheHit
                return staged.image
            }
            // ImageIO rendered fallback — honest proxy fidelity, not RAW developing.
            if let rendered = PreviewExtractor.renderedFallback(
                from: request.rawURL,
                maxPixelSize: request.longEdgeCap.flatMap { $0 > 0 ? $0 : nil } ?? 6000
            ) {
                usedProxy = true
                fidelity = .proxyFallback
                return CIImage(cgImage: rendered)
            }
            if let proxy = request.proxyURL,
               let jpeg = CIImage(contentsOf: proxy, options: [.applyOrientationProperty: true]) {
                usedProxy = true
                fidelity = .proxyFallback
                return jpeg
            }
            return nil
        case .jpegProxy:
            usedProxy = true
            fidelity = .proxyFallback
            if let proxy = request.proxyURL,
               let jpeg = CIImage(contentsOf: proxy, options: [.applyOrientationProperty: true]) {
                return jpeg
            }
            return CIImage(contentsOf: request.rawURL, options: [.applyOrientationProperty: true])
        }
    }

    // MARK: - Look stage (scene-linear, honest subset)

    static func applyLook(_ look: LookIntent, to image: CIImage) -> CIImage {
        guard !look.isNeutral else { return image }
        var result = image
        let bounds = image.extent.integral

        // Highlights / Shadows — CIHighlightShadowAdjust, documented approximation
        // (not Lightroom Highlights/Shadows; validated visually in the lab).
        if look.highlights != 0 || look.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(min(max(1 - look.highlights / 100.0, 0), 1), forKey: "inputHighlightAmount")
            f.setValue(min(max(1 + look.shadows / 100.0, 0), 2), forKey: "inputShadowAmount")
            result = f.outputImage ?? result
        }

        if look.contrast != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + look.contrast / 100.0, forKey: kCIInputContrastKey)
            result = f.outputImage ?? result
        }

        if look.vibrance != 0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(look.vibrance / 100.0, forKey: "inputAmount")
            result = f.outputImage ?? result
        }
        if look.saturation != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + look.saturation / 100.0, forKey: kCIInputSaturationKey)
            result = f.outputImage ?? result
        }

        return result.cropped(to: bounds)
    }

    /// Proxy/JPEG fallback grading — approximates RAW-domain operations with
    /// generic CI filters because no RAW domain exists. Only ever displayed
    /// under the Proxy fidelity label.
    static func applyProxyApproximation(_ recipe: EditRecipe, to image: CIImage) -> CIImage {
        var result = image
        let bounds = image.extent.integral

        if recipe.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.exposure, forKey: kCIInputEVKey)
            result = f.outputImage ?? result
        }
        if abs(recipe.temperature - 6500) > 1 || recipe.tint != 0,
           let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: recipe.temperature, y: recipe.tint), forKey: "inputTargetNeutral")
            result = f.outputImage ?? result
        }
        result = applyLook(recipe.lookIntent, to: result)
        result = applyRetouch(recipe.retouch, to: result)
        return result.cropped(to: bounds)
    }

    /// Legacy shared apply path (JPEG proxy grading in the workbench).
    static func applyRecipe(_ recipe: EditRecipe, to image: CIImage, skipRAWIntegratedWB: Bool) -> CIImage {
        let legacy = DevelopEngine.clampRecipe(recipe.asDevelopRecipe)
        let edit = EditRecipe(from: legacy, id: recipe.id).updating {
            $0.crop = recipe.crop
            $0.straightenDegrees = recipe.straightenDegrees
            $0.sharpness = recipe.sharpness
            $0.luminanceNR = recipe.luminanceNR
        }
        if skipRAWIntegratedWB {
            return applyLook(edit.lookIntent, to: image)
        }
        return applyProxyApproximation(edit, to: image)
    }

    // MARK: - Retouch (clone heal)

    /// Clone-based heal: for each spot, pixels from a nearby donor region are
    /// composited over the target through a feathered radial mask. Classic
    /// clone-stamp healing — not generative fill — so preview, 1:1 and export
    /// all produce identical results at any resolution.
    static func applyRetouch(_ spots: [RetouchSpot], to image: CIImage) -> CIImage {
        guard !spots.isEmpty else { return image }
        var result = image
        let bounds = image.extent.integral
        guard bounds.width > 1, bounds.height > 1 else { return image }

        for spot in spots {
            let radius = CGFloat(spot.radius) * bounds.width
            guard radius > 0.5 else { continue }
            // Normalized coords are top-left origin; CIImage is bottom-up.
            let cx = bounds.minX + CGFloat(spot.x) * bounds.width
            let cy = bounds.maxY - CGFloat(spot.y) * bounds.height
            let dxPixels = CGFloat(spot.sourceDX) * bounds.width
            let dyPixels = -CGFloat(spot.sourceDY) * bounds.height

            // Donor pixels shifted so the source region lands on the spot center.
            let donor = result
                .transformed(by: CGAffineTransform(translationX: -dxPixels, y: -dyPixels))
                .clampedToExtent()

            guard let gradient = CIFilter(name: "CIRadialGradient") else { continue }
            gradient.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
            gradient.setValue(radius * 0.55, forKey: "inputRadius0")
            gradient.setValue(radius, forKey: "inputRadius1")
            gradient.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            gradient.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            guard let mask = gradient.outputImage?.cropped(to: bounds) else { continue }

            guard let blend = CIFilter(name: "CIBlendWithMask") else { continue }
            blend.setValue(donor, forKey: kCIInputImageKey)
            blend.setValue(result, forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            result = blend.outputImage?.cropped(to: bounds) ?? result
        }
        return result
    }

    // MARK: - Geometry

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
            result = result.cropped(to: bounds)
        }

        if let crop = recipe.crop, !crop.isFullFrame {
            let rect = crop.pixelRect(in: bounds).integral
            result = result.cropped(to: rect)
            result = normalizeOrigin(result)
        }
        return result
    }

    static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y
        ))
    }

    /// Post-decode downsample — only reached on proxy fallback paths; RAW decode
    /// scales through `CIRAWFilter.scaleFactor` inside the session.
    private static func maybeDownsample(_ image: CIImage, longEdge: Int?) -> CIImage {
        guard let longEdge, longEdge > 0 else { return image }
        let extent = image.extent
        let current = max(extent.width, extent.height)
        guard current > CGFloat(longEdge) + 1 else { return image }
        let scale = CGFloat(longEdge) / current
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: - Export encode

    /// 16-bit ProPhoto RGB TIFF with embedded ICC profile and ZIP (Deflate)
    /// compression, for Lightroom/Photoshop handoff.
    static func exportTIFF(cgImage: CGImage, to url: URL, preserveMetadataFrom rawURL: URL?) -> Bool {
        let type = UTType.tiff.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            return false
        }
        var tiffDict: [CFString: Any] = [
            // 8 = Adobe Deflate (ZIP) — lossless.
            kCGImagePropertyTIFFCompression: 8,
        ]
        var props: [CFString: Any] = [:]
        if let rawURL,
           let src = CGImageSourceCreateWithURL(rawURL as CFURL, nil),
           let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            props[kCGImagePropertyExifDictionary] = meta[kCGImagePropertyExifDictionary]
            if let sourceTIFF = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiffDict.merge(sourceTIFF) { current, _ in current }
                tiffDict[kCGImagePropertyTIFFCompression] = 8
            }
            props[kCGImagePropertyGPSDictionary] = meta[kCGImagePropertyGPSDictionary]
        }
        props[kCGImagePropertyTIFFDictionary] = tiffDict
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Full-resolution authoritative export render → 16-bit ProPhoto CGImage.
    static func renderExportBitmap(rawURL: URL, photoID: UUID, recipe: EditRecipe) async -> CGImage? {
        let request = RawRenderRequest(
            generation: 0,
            photoID: photoID,
            rawURL: rawURL,
            recipe: recipe,
            quality: .export,
            source: .originalRAW,
            longEdgeCap: 0,
            forDisplay: false
        )
        return await render(request).cgImage
    }
}
