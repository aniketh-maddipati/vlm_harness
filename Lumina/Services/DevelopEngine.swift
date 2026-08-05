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

    /// Legacy synchronous proxy grading — JPEG/proxy input only, browse-grade,
    /// never labeled RAW. Authoritative RAW rendering goes through the async
    /// `DevelopRenderGraph.render` / `PreparedRawSession` path.
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
        guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        let edit = EditRecipe(from: clampRecipe(recipe.applying(offsets)))
        let original = DevelopRenderGraph.normalizeOrigin(source)
        var image = original

        if mix > 0.001 {
            image = DevelopRenderGraph.applyProxyApproximation(edit, to: original)
        }
        if mix < 0.999, mix > 0.001 {
            let bounds = image.extent.integral
            image = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: original,
                kCIInputMaskImageKey: CIImage(color: CIColor(red: mix, green: mix, blue: mix, alpha: 1))
                    .cropped(to: bounds),
            ]).cropped(to: bounds)
        }

        let bounds = image.extent.integral
        guard let cg = context.createCGImage(image, from: bounds) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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

    /// Full-resolution RAW develop for export (shared graph with settled preview).
    static func renderFullRAW(
        rawURL: URL,
        recipe: DevelopRecipe,
        offsets: DevelopAdjustments = .zero
    ) async -> CGImage? {
        let edit = EditRecipe(from: clampRecipe(recipe.applying(offsets)))
        return await DevelopRenderGraph.renderExportBitmap(rawURL: rawURL, photoID: UUID(), recipe: edit)
    }

    /// Export-quality render using an `EditRecipe` (crop/straighten included).
    static func renderExport(rawURL: URL, recipe: EditRecipe) async -> CGImage? {
        await DevelopRenderGraph.renderExportBitmap(rawURL: rawURL, photoID: UUID(), recipe: recipe)
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
