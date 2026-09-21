import AppKit
import Foundation
import ImageIO
import Metal

/// One decode owner for contact-sheet, focused-preview, and Metal browse pixels.
///
/// Runtime browse requests are JPEG-only. The service coalesces identical
/// ImageIO work, keeps a byte-bounded LRU, and hands the same decoded CGImage to
/// AppKit and Metal so opening a photograph cannot trigger two disk decodes.
actor BrowsePixelService {
    static let shared = BrowsePixelService()

    nonisolated enum Tier: Int, Sendable {
        case grid = 0
        case focused = 1

        var maxPixelSize: Int {
            switch self {
            case .grid: PhotoImageTier.gridMaxPixelSize
            case .focused: PhotoImageTier.focusedPreviewLongEdge
            }
        }
    }

    nonisolated final class Pixel: @unchecked Sendable {
        let cgImage: CGImage
        let nsImage: NSImage
        let decodeMs: Double

        init(cgImage: CGImage, decodeMs: Double) {
            self.cgImage = cgImage
            self.decodeMs = decodeMs
            let scale: CGFloat = 2
            self.nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )
            )
        }

        var byteEstimate: Int { cgImage.bytesPerRow * cgImage.height }
    }

    nonisolated struct Diagnostics: Sendable {
        let residentBytes: Int
        let residentCount: Int
        let inflightCount: Int
        let cacheHits: Int
        let cacheMisses: Int
    }

    private struct Key: Hashable {
        let path: String
        let maxPixelSize: Int
    }

    private struct Inflight {
        let id: UUID
        let epoch: UInt64
        let task: Task<Pixel?, Never>
    }

    private var pixels: [Key: Pixel] = [:]
    private var order: [Key] = []
    private var residentBytes = 0
    private var inflight: [Key: Inflight] = [:]
    private var epoch: UInt64 = 0
    private var pinnedPaths: Set<String> = []
    private var cacheHits = 0
    private var cacheMisses = 0

    nonisolated private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    func pinFocused(paths: [String]) {
        pinnedPaths = Set(paths)
    }

    func clearFocusedPin() {
        pinnedPaths.removeAll()
    }

    func image(path: String, tier: Tier) async -> NSImage? {
        await pixel(path: path, tier: tier)?.nsImage
    }

    func image(path: String, maxPixelSize: Int) async -> NSImage? {
        await pixel(path: path, maxPixelSize: maxPixelSize)?.nsImage
    }

    func pixel(path: String, tier: Tier) async -> Pixel? {
        await pixel(path: path, maxPixelSize: tier.maxPixelSize, priority: tier == .focused ? .userInitiated : .utility)
    }

    func pixel(path: String, maxPixelSize: Int) async -> Pixel? {
        await pixel(path: path, maxPixelSize: maxPixelSize, priority: .userInitiated)
    }

    private func pixel(
        path: String,
        maxPixelSize: Int,
        priority: TaskPriority
    ) async -> Pixel? {
        let key = Key(path: path, maxPixelSize: maxPixelSize)
        if let hit = pixels[key] {
            cacheHits &+= 1
            touch(key)
            LatencyMetrics.record("browse.pixel.cache_hit", milliseconds: 0)
            return hit
        }
        if let pending = inflight[key] {
            let decoded = await pending.task.value
            guard pending.epoch == epoch else { return nil }
            return decoded
        }

        cacheMisses &+= 1
        let requestID = UUID()
        let requestEpoch = epoch
        let task = Task.detached(priority: priority) {
            Self.decode(path: path, maxPixelSize: maxPixelSize)
        }
        inflight[key] = Inflight(id: requestID, epoch: requestEpoch, task: task)
        let decoded = await task.value
        if inflight[key]?.id == requestID {
            inflight[key] = nil
        }
        guard requestEpoch == epoch, let decoded else { return nil }
        store(decoded, for: key)
        LatencyMetrics.record("browse.pixel.decode_ms", milliseconds: decoded.decodeMs)
        return decoded
    }

    /// Decode once and upload the same pixels to the shared Metal pool.
    func prepareTexture(
        assetID: UUID,
        path: String,
        tier: Tier,
        generation: UInt64,
        distanceBias: Int = 0
    ) async {
        if let info = MetalPreviewPool.shared.textureInfo(for: assetID),
           generation == 0 || info.generation == generation {
            return
        }
        guard let decoded = await pixel(path: path, tier: tier) else { return }
        _ = await Task.detached(priority: tier == .focused ? .userInitiated : .utility) {
            MetalPreviewPool.shared.upload(
                id: assetID,
                decoded: decoded.cgImage,
                distanceBias: distanceBias,
                generation: generation,
                decodeMs: decoded.decodeMs
            )
        }.value
    }

    func prefetch(_ requests: [(assetID: UUID, path: String)], tier: Tier) {
        prefetch(paths: requests.map(\.path), maxPixelSize: tier.maxPixelSize)
    }

    func prefetch(paths: [String], tier: Tier) {
        prefetch(paths: paths, maxPixelSize: tier.maxPixelSize)
    }

    func prefetch(paths: [String], maxPixelSize: Int) {
        for path in Set(paths) {
            Task(priority: .utility) {
                _ = await pixel(path: path, maxPixelSize: maxPixelSize, priority: .utility)
            }
        }
    }

    func trimForMemoryPressure() {
        for key in order where !pinnedPaths.contains(key.path) {
            remove(key)
        }
    }

    func removeAll() {
        epoch &+= 1
        inflight.values.forEach { $0.task.cancel() }
        inflight.removeAll()
        pixels.removeAll()
        order.removeAll()
        pinnedPaths.removeAll()
        residentBytes = 0
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(
            residentBytes: residentBytes,
            residentCount: pixels.count,
            inflightCount: inflight.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses
        )
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func store(_ pixel: Pixel, for key: Key) {
        if let previous = pixels[key] {
            residentBytes -= previous.byteEstimate
        }
        pixels[key] = pixel
        residentBytes += pixel.byteEstimate
        touch(key)

        while residentBytes > PhotoImageCacheBudget.totalCeilingBytes,
              let candidate = order.first(where: { !pinnedPaths.contains($0.path) }) {
            remove(candidate)
        }
    }

    private func remove(_ key: Key) {
        order.removeAll { $0 == key }
        if let removed = pixels.removeValue(forKey: key) {
            residentBytes -= removed.byteEstimate
        }
    }

    nonisolated private static func decode(path: String, maxPixelSize: Int) -> Pixel? {
        autoreleasepool {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.uppercased()
            // PhotoRecord preview candidates may deliberately fall back to the
            // source path. Decline that candidate; BrowsePixelService must never
            // demosaic RAW, but a missing JPEG tier is not a programmer error.
            guard !rawExtensions.contains(ext) else { return nil }
            guard FileManager.default.fileExists(atPath: path) else { return nil }

            let started = CFAbsoluteTimeGetCurrent()
            let source: CGImageSource? = {
                if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    return CGImageSourceCreateWithData(data as CFData, nil)
                }
                return CGImageSourceCreateWithURL(url as CFURL, nil)
            }()
            guard let source else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else { return nil }
            return Pixel(
                cgImage: image,
                decodeMs: (CFAbsoluteTimeGetCurrent() - started) * 1000
            )
        }
    }
}
