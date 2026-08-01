import CoreImage
import AppKit

/// Dual-path develop: GPU Core Image on 2048px proxies for interactive scrub
/// (Metal toolchain not required — CIContext uses Metal under the hood on macOS).
enum DevelopEngine {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: true,
    ])

    static func ensureProxy(for photo: PhotoRecord, projectName: String) -> URL? {
        if let proxy = photo.proxyPath, FileManager.default.fileExists(atPath: proxy) {
            return URL(fileURLWithPath: proxy)
        }
        guard let thumb = photo.thumbPath else { return nil }
        guard let proxyDir = try? ProjectStore.cacheDirectory(for: projectName, tier: "proxy2048") else {
            return URL(fileURLWithPath: thumb)
        }
        let stem = URL(fileURLWithPath: photo.rawPath).deletingPathExtension().lastPathComponent
        let dest = proxyDir.appendingPathComponent(stem + ".jpg")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if PreviewExtractor.downscaleJPEG(from: URL(fileURLWithPath: thumb), to: dest, maxPixelSize: 2048) {
            return dest
        }
        // Try extract from RAW at 2048
        if (try? PreviewExtractor.extract(to: dest, from: URL(fileURLWithPath: photo.rawPath), maxPixelSize: 2048)) != nil {
            return dest
        }
        return URL(fileURLWithPath: thumb)
    }

    static func render(
        url: URL,
        recipe: DevelopRecipe,
        offsets: DevelopAdjustments = .zero,
        mix: Double = 1.0
    ) -> NSImage? {
        guard let image = CIImage(contentsOf: url) else { return nil }
        let bounds = image.extent
        let graded = apply(recipe: recipe.applying(offsets), to: image).cropped(to: bounds)
        let mixed: CIImage
        if mix >= 0.999 {
            mixed = graded
        } else if mix <= 0.001 {
            mixed = image
        } else {
            mixed = graded.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: image,
                kCIInputTimeKey: 1.0 - mix,
            ]).cropped(to: bounds)
        }
        guard let cg = context.createCGImage(mixed, from: bounds) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: bounds.width, height: bounds.height))
    }

    static func apply(recipe: DevelopRecipe, to image: CIImage) -> CIImage {
        let bounds = image.extent
        var result = image

        if recipe.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.exposure, forKey: kCIInputEVKey)
            result = f.outputImage ?? result
        }

        if recipe.contrast != 0 || recipe.saturation != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            if recipe.contrast != 0 {
                f.setValue(1 + recipe.contrast / 100.0, forKey: kCIInputContrastKey)
            }
            if recipe.saturation != 0 {
                f.setValue(1 + recipe.saturation / 100.0, forKey: kCIInputSaturationKey)
            }
            result = f.outputImage ?? result
        }

        if recipe.vibrance != 0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(recipe.vibrance / 100.0, forKey: "inputAmount")
            result = f.outputImage ?? result
        }

        if recipe.highlights != 0 || recipe.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 - recipe.highlights / 100.0, forKey: "inputHighlightAmount")
            f.setValue(1 + recipe.shadows / 100.0, forKey: "inputShadowAmount")
            result = f.outputImage ?? result
        }

        // Clarity / texture approximation via unsharp + local contrast
        if recipe.clarity != 0 || recipe.texture != 0, let f = CIFilter(name: "CIUnsharpMask") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(2.5, forKey: kCIInputRadiusKey)
            f.setValue((recipe.clarity + recipe.texture) / 200.0, forKey: kCIInputIntensityKey)
            result = f.outputImage ?? result
        }

        if recipe.dehaze != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(1 + recipe.dehaze / 200.0, forKey: kCIInputContrastKey)
            f.setValue(1 + recipe.dehaze / 300.0, forKey: kCIInputSaturationKey)
            result = f.outputImage ?? result
        }

        if recipe.temperature != 6500 || recipe.tint != 0, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(result, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: recipe.temperature, y: recipe.tint), forKey: "inputTargetNeutral")
            result = f.outputImage ?? result
        }

        return result.cropped(to: bounds)
    }

    /// Full-resolution demosaic + develop for export (ImageIO RAW path).
    static func renderFullRAW(
        rawURL: URL,
        recipe: DevelopRecipe,
        offsets: DevelopAdjustments = .zero
    ) -> CGImage? {
        guard let demosaiced = PreviewExtractor.demosaicFull(from: rawURL, maxPixelSize: 6000) else {
            return nil
        }
        let ci = CIImage(cgImage: demosaiced)
        let graded = apply(recipe: recipe.applying(offsets), to: ci)
        return context.createCGImage(graded, from: graded.extent)
    }
}

/// Soft auto-render controller — animates mix 0→1.
@MainActor
@Observable
final class SoftRenderController {
    var mix: Double = 0
    private var task: Task<Void, Never>?

    func play(duration: Double = 0.22) {
        task?.cancel()
        mix = 0
        task = Task {
            let steps = 12
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                // ease-out
                mix = 1 - pow(1 - t, 2)
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
            }
            mix = 1
        }
    }

    func snapBefore() { task?.cancel(); mix = 0 }
    func snapAfter() { task?.cancel(); mix = 1 }
}

// Compatibility wrapper
enum PreviewRenderer {
    static func render(url: URL, profile: DevelopRecipe, offsets: DevelopAdjustments = .zero) -> NSImage? {
        DevelopEngine.render(url: url, recipe: profile, offsets: offsets, mix: 1)
    }

    static func apply(profile: DevelopRecipe, offsets: DevelopAdjustments, to image: CIImage) -> CIImage {
        DevelopEngine.apply(recipe: profile.applying(offsets), to: image)
    }
}
