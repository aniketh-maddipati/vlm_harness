import AppKit
import Foundation

enum PhotoImageTier: Sendable {
    case grid
    case preview
    case proxy

    func path(for photo: PhotoRecord) -> String? {
        switch self {
        case .grid: photo.gridThumbPath ?? photo.thumbPath
        case .preview: photo.previewPath
        case .proxy: photo.proxyPath ?? photo.thumbPath ?? photo.gridThumbPath
        }
    }
}

/// Memory + async disk cache for sharp, Retina-aware photo display.
actor PhotoImageCache {
    static let shared = PhotoImageCache()

    private var memory: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    func image(for path: String) -> NSImage? {
        memory[path]
    }

    func load(path: String) async -> NSImage? {
        if let cached = memory[path] { return cached }
        if let task = inflight[path] { return await task.value }

        let task = Task<NSImage?, Never> {
            await Task.detached(priority: .userInitiated) {
                Self.decode(path: path)
            }.value
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image { memory[path] = image }
        return image
    }

    func prefetch(_ paths: [String]) {
        for path in paths where memory[path] == nil && inflight[path] == nil {
            Task { _ = await load(path: path) }
        }
    }

    nonisolated private static func decode(path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return NSImage(contentsOf: url)
        }
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
