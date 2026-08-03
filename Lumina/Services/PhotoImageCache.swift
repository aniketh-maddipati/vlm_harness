import AppKit
import Foundation
import CryptoKit

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

    /// Display decode cap — avoids full-res JPEG decode in grids and filmstrips.
    var displayMaxPixelSize: Int? {
        switch self {
        case .grid: 512
        case .preview: 1600
        case .proxy: nil
        }
    }

    /// Grid/preview tiers must never demosaic RAW on the interactive path.
    var allowsRAWFallback: Bool {
        switch self {
        case .grid, .preview: false
        case .proxy: true
        }
    }
}

enum PhotoLoadOutcome: Sendable {
    case image(NSImage)
    case missing
    case failed
}

/// Session-scoped image cache: memory LRU + optional session disk + async writes off the hot path.
actor PhotoImageCache {
    static let shared = PhotoImageCache()

    private var memory: [String: NSImage] = [:]
    private var memoryOrder: [String] = []
    private var inflight: [String: Task<PhotoLoadOutcome, Never>] = [:]
    private var sessionID: UUID?
    private var sessionDiskRoot: URL?
    private var projectName: String?
    private var pendingDiskWrites: [String: DispatchWorkItem] = [:]
    private let memoryCap = 320
    private let diskWriteQueue = DispatchQueue(label: "lumina.image-cache.disk", qos: .utility)

    private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    private static func cacheKey(path: String, maxPixelSize: Int?) -> String {
        if let maxPixelSize { return "\(path)@\(maxPixelSize)" }
        return path
    }

    // MARK: - Session lifecycle

    func beginSession(projectName: String) {
        endSession()
        let id = UUID()
        sessionID = id
        self.projectName = projectName
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            sessionDiskRoot = caches
                .appendingPathComponent("Lumina/sessions", isDirectory: true)
                .appendingPathComponent("\(projectName)-\(id.uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: sessionDiskRoot!, withIntermediateDirectories: true)
        }
        ThumbCache.shared.resetSession()
    }

    func endSession() {
        memory.removeAll()
        memoryOrder.removeAll()
        inflight.removeAll()
        pendingDiskWrites.values.forEach { $0.cancel() }
        pendingDiskWrites.removeAll()
        if let root = sessionDiskRoot {
            diskWriteQueue.async {
                try? FileManager.default.removeItem(at: root)
            }
        }
        sessionDiskRoot = nil
        sessionID = nil
        projectName = nil
        ThumbCache.shared.resetSession()
    }

    func image(for path: String, maxPixelSize: Int? = nil) -> NSImage? {
        memory[Self.cacheKey(path: path, maxPixelSize: maxPixelSize)]
    }

    func load(path: String, maxPixelSize: Int? = nil, allowRAW: Bool = true) async -> PhotoLoadOutcome {
        let key = Self.cacheKey(path: path, maxPixelSize: maxPixelSize)
        if let cached = memory[key] { return .image(cached) }
        if let task = inflight[key] { return await task.value }

        let task = Task<PhotoLoadOutcome, Never> {
            if !Self.fileExists(path) { return .missing }
            if !allowRAW, Self.isRAW(path) { return .missing }

            if let disk = await self.loadFromSessionDisk(key: key) {
                await self.storeInMemory(key: key, image: disk)
                return .image(disk)
            }

            let decoded = await LatencyMetrics.measureAsync("cache.load") {
                await Task.detached(priority: .userInitiated) {
                    Self.decode(path: path, maxPixelSize: maxPixelSize, allowRAW: allowRAW)
                }.value
            }

            switch decoded {
            case .image(let img):
                await self.storeInMemory(key: key, image: img)
                await self.scheduleDiskWrite(key: key, image: img)
                return .image(img)
            case .missing, .failed:
                return decoded
            }
        }
        inflight[key] = task
        let outcome = await task.value
        inflight[key] = nil
        return outcome
    }

    func prefetch(_ paths: [String], maxPixelSize: Int? = nil, allowRAW: Bool = false) {
        for path in paths {
            let key = Self.cacheKey(path: path, maxPixelSize: maxPixelSize)
            guard memory[key] == nil, inflight[key] == nil else { continue }
            Task { _ = await load(path: path, maxPixelSize: maxPixelSize, allowRAW: allowRAW) }
        }
    }

    // MARK: - Memory LRU

    private func storeInMemory(key: String, image: NSImage) {
        memory[key] = image
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        while memoryOrder.count > memoryCap {
            let evict = memoryOrder.removeFirst()
            memory.removeValue(forKey: evict)
        }
    }

    // MARK: - Session disk (async write, sync read on miss)

    private func sessionDiskURL(for key: String) -> URL? {
        guard let root = sessionDiskRoot else { return nil }
        let hash = SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(hash.prefix(32)).jpg")
    }

    private func loadFromSessionDisk(key: String) async -> NSImage? {
        guard let url = sessionDiskURL(for: key),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await Task.detached(priority: .utility) {
            NSImage(contentsOf: url)
        }.value
    }

    private func scheduleDiskWrite(key: String, image: NSImage) {
        guard sessionDiskRoot != nil, let url = sessionDiskURL(for: key) else { return }
        pendingDiskWrites[key]?.cancel()
        // Encode on diskWriteQueue — keep TIFF/JPEG work off the actor.
        let work = DispatchWorkItem {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { return }
            try? jpeg.write(to: url, options: .atomic)
        }
        pendingDiskWrites[key] = work
        diskWriteQueue.async(execute: work)
    }

    // MARK: - Decode

    nonisolated private static func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    nonisolated private static func isRAW(_ path: String) -> Bool {
        rawExtensions.contains(URL(fileURLWithPath: path).pathExtension.uppercased())
    }

    nonisolated private static func decode(path: String, maxPixelSize: Int?, allowRAW: Bool) -> PhotoLoadOutcome {
        if !fileExists(path) { return .missing }
        if !allowRAW, isRAW(path) { return .missing }

        let url = URL(fileURLWithPath: path)
        let source: CGImageSource? = {
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                return CGImageSourceCreateWithData(data as CFData, nil)
            }
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }()
        guard let source else { return .failed }

        let cg: CGImage?
        if let maxPixelSize {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailFromImageAlways: false,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
            ]
            cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let cg else { return .failed }

        let scale: CGFloat = 2
        let size = NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        return .image(NSImage(cgImage: cg, size: size))
    }
}

/// Deduped prefetch front-end — used by grid overview and Pick phase.
final class ThumbCache: @unchecked Sendable {
    static let shared = ThumbCache()
    private var warm = Set<String>()
    private let lock = NSLock()

    private init() {}

    func resetSession() {
        lock.lock()
        warm.removeAll()
        lock.unlock()
    }

    func prefetch(_ path: String, maxPixelSize: Int? = 512, allowRAW: Bool = false) {
        lock.lock()
        let key = maxPixelSize.map { "\(path)@\($0)" } ?? path
        let fresh = warm.insert(key).inserted
        lock.unlock()
        guard fresh else { return }
        Task { await PhotoImageCache.shared.prefetch([path], maxPixelSize: maxPixelSize, allowRAW: allowRAW) }
    }

    func prefetchPhotos(_ photos: [PhotoRecord], maxPixelSize: Int? = 512) {
        for photo in photos {
            guard let path = photo.gridThumbPath ?? photo.thumbPath else { continue }
            prefetch(path, maxPixelSize: maxPixelSize, allowRAW: false)
        }
    }

    func prefetchPaths(_ paths: [String], maxPixelSize: Int? = 512, allowRAW: Bool = false) {
        for path in paths {
            prefetch(path, maxPixelSize: maxPixelSize, allowRAW: allowRAW)
        }
    }
}

enum PhotoImageLoader {
    static func ensureProxyPath(photo: PhotoRecord, projectName: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            DevelopEngine.ensureProxy(for: photo, projectName: projectName)?.path
        }.value
    }
}

/// Evicts runtime browse caches after an editing session — ingest disk tiers are untouched.
enum SessionCache {
    @MainActor
    static func beginEditingSession(projectName: String) {
        Task { await PhotoImageCache.shared.beginSession(projectName: projectName) }
        LatencyMetrics.resetSession()
        MetalCanvasLifecycle.beginSession()
    }

    @MainActor
    static func endEditingSession(clearBrowseSpine: Bool = true) {
        Task { await PhotoImageCache.shared.endSession() }
        if clearBrowseSpine {
            PreviewSpine.shared.clear()
            MetalPreviewPool.shared.evictAll()
        }
        LatencyMetrics.resetSession()
    }
}
