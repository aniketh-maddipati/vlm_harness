import AppKit
import Foundation

enum PhotoImageTier: Sendable {
    case grid
    case preview
    case proxy

    func path(for photo: PhotoRecord) -> String? {
        switch self {
        case .grid: photo.gridThumbPath ?? photo.thumbPath ?? photo.rawPath
        case .preview: photo.previewPath
        case .proxy: photo.proxyPath ?? photo.thumbPath ?? photo.gridThumbPath ?? photo.rawPath
        }
    }

    /// Display decode cap — avoids full-res JPEG decode in grids and filmstrips.
    var displayMaxPixelSize: Int? {
        switch self {
        case .grid: 512
        case .preview: 1600
        case .proxy: nil
        }
    }
}

/// Memory + async disk cache for sharp, Retina-aware photo display.
actor PhotoImageCache {
    static let shared = PhotoImageCache()

    private var memory: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    private static func cacheKey(path: String, maxPixelSize: Int?) -> String {
        if let maxPixelSize { return "\(path)@\(maxPixelSize)" }
        return path
    }

    func image(for path: String, maxPixelSize: Int? = nil) -> NSImage? {
        memory[Self.cacheKey(path: path, maxPixelSize: maxPixelSize)]
    }

    func load(path: String, maxPixelSize: Int? = nil) async -> NSImage? {
        let key = Self.cacheKey(path: path, maxPixelSize: maxPixelSize)
        if let cached = memory[key] { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<NSImage?, Never> {
            await LatencyMetrics.measureAsync("cache.load") {
                await Task.detached(priority: .userInitiated) {
                    Self.decode(path: path, maxPixelSize: maxPixelSize)
                }.value
            }
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { memory[key] = image }
        return image
    }

    func prefetch(_ paths: [String], maxPixelSize: Int? = nil) {
        for path in paths {
            let key = Self.cacheKey(path: path, maxPixelSize: maxPixelSize)
            guard memory[key] == nil, inflight[key] == nil else { continue }
            Task { _ = await load(path: path, maxPixelSize: maxPixelSize) }
        }
    }

    nonisolated private static func decode(path: String, maxPixelSize: Int?) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let cg: CGImage?
        if let maxPixelSize {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
        } else {
            cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let cg else { return NSImage(contentsOf: url) }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(
            width: CGFloat(cg.width) / scale,
            height: CGFloat(cg.height) / scale
        )
        return NSImage(cgImage: cg, size: size)
    }
}

enum PhotoImageLoader {
    static func ensureProxyPath(photo: PhotoRecord, projectName: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            DevelopEngine.ensureProxy(for: photo, projectName: projectName)?.path
        }.value
    }
}
