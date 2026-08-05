import CoreImage
import AppKit

/// Dual-path develop facade.
/// Interactive scrub and export both route through `DevelopRenderGraph` so operation
/// ordering, recipe interpretation, geometry, and color transforms do not drift.
enum DevelopEngine {
    private static let context = DevelopRenderGraph.sharedContext

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
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            LatencyMetrics.record("develop.render", milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let edit = EditRecipe(from: recipe.applying(offsets))
        // Legacy interactive entry still accepts a JPEG/proxy URL; mark source honestly.
        let request = RawRenderRequest(
            generation: 0,
            photoID: UUID(),
            rawURL: url,
            proxyURL: url,
            recipe: edit,
            quality: .interactive,
            source: .jpegProxy
        )
        let result = DevelopRenderGraph.render(request)
        guard var graded = result.cgImage else { return nil }

        if mix < 0.999, mix > 0.001, let original = CIImage(contentsOf: url) {
            let gCI = CIImage(cgImage: graded)
            let bounds = gCI.extent.integral
            let mixed = gCI.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: DevelopRenderGraph.normalizeOrigin(original),
                kCIInputMaskImageKey: CIImage(color: CIColor(red: mix, green: mix, blue: mix, alpha: 1))
                    .cropped(to: bounds),
            ]).cropped(to: bounds)
            if let cg = context.createCGImage(mixed, from: bounds) {
                graded = cg
            }
        } else if mix <= 0.001, let original = CIImage(contentsOf: url) {
            let o = DevelopRenderGraph.normalizeOrigin(original)
            if let cg = context.createCGImage(o, from: o.extent.integral) {
                graded = cg
            }
        }

        return NSImage(cgImage: graded, size: NSSize(width: graded.width, height: graded.height))
    }

    /// Keep develop params in ranges Core Image handles without wild casts.
    static func clampRecipe(_ recipe: DevelopRecipe) -> DevelopRecipe {
        var r = recipe
        r.exposure = min(max(r.exposure, -3), 3)
        r.temperature = min(max(r.temperature == 0 ? 6500 : r.temperature, 2500), 10000)
        r.tint = min(max(r.tint, -50), 50)
        r.contrast = min(max(r.contrast, -100), 100)
        r.highlights = min(max(r.highlights, -100), 100)
        r.shadows = min(max(r.shadows, -100), 100)
        r.whites = min(max(r.whites, -100), 100)
        r.blacks = min(max(r.blacks, -100), 100)
        r.texture = min(max(r.texture, -100), 100)
        r.clarity = min(max(r.clarity, -100), 100)
        r.dehaze = min(max(r.dehaze, -100), 100)
        r.vibrance = min(max(r.vibrance, -100), 100)
        r.saturation = min(max(r.saturation, -100), 100)
        r.sharpness = min(max(r.sharpness, 0), 150)
        r.luminanceNR = min(max(r.luminanceNR, 0), 100)
        return r
    }

    static func apply(recipe: DevelopRecipe, to image: CIImage) -> CIImage {
        let edit = EditRecipe(from: clampRecipe(recipe))
        return DevelopRenderGraph.applyRecipe(edit, to: DevelopRenderGraph.normalizeOrigin(image), skipRAWIntegratedWB: false)
    }

    /// Full-resolution demosaic + develop for export (shared graph with settled preview).
    static func renderFullRAW(
        rawURL: URL,
        recipe: DevelopRecipe,
        offsets: DevelopAdjustments = .zero
    ) -> CGImage? {
        let edit = EditRecipe(from: clampRecipe(recipe.applying(offsets)))
        let request = RawRenderRequest(
            generation: 0,
            photoID: UUID(),
            rawURL: rawURL,
            recipe: edit,
            quality: .export,
            source: .originalRAW,
            longEdgeCap: 0,
            forDisplay: false
        )
        return DevelopRenderGraph.render(request).cgImage
    }

    /// Export-quality render using an `EditRecipe` (crop/straighten included).
    static func renderExport(rawURL: URL, recipe: EditRecipe) -> CGImage? {
        let request = RawRenderRequest(
            generation: 0,
            photoID: UUID(),
            rawURL: rawURL,
            recipe: recipe,
            quality: .export,
            source: .originalRAW,
            longEdgeCap: 0,
            forDisplay: false
        )
        return DevelopRenderGraph.render(request).cgImage
    }
}

/// Soft auto-render controller — animates mix 0→1.
@MainActor
@Observable
final class SoftRenderController {
    var mix: Double = 0
    private var task: Task<Void, Never>?

    func play(duration: Double = 0.55) {
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
