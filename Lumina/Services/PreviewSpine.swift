import AppKit
import Foundation
import ImageIO
import Observation
import os

/// Speed Contract browsing spine — cached JPEG → GPU texture only on the interactive path.
@MainActor
@Observable
final class PreviewSpine {
    static let shared = PreviewSpine()

    enum Tier: String, Sendable {
        case empty
        case silhouette
        case preview
    }

    // MARK: - Painted frame (canvas reads these only)

    private(set) var paintedPhotoID: UUID?
    private(set) var paintedTier: Tier = .empty
    private(set) var paintedJPEGPath: String?

    /// Ingest grid thumb for silhouette fallback — never a full preview decode.
    private(set) var paintedSilhouette: NSImage?

    // MARK: - Honest instrumentation

    /// Dictionary lookup + tier commit — NOT photon time.
    private(set) var lastPaintCommitMs: Double = 0
    private(set) var lastInputToPhotonMs: Double = 0
    private(set) var gpuPrefetchHits: Int = 0
    private(set) var gpuPrefetchMisses: Int = 0
    private(set) var droppedFrames: Int = 0
    private(set) var decodeQueueDepth: Int = 0
    private(set) var gpuTextureCount: Int = 0
    private(set) var silhouetteCount: Int = 0
    private(set) var direction: Int = 1
    private(set) var ripVelocity: Double = 0
    private(set) var embeddedCount: Int = 0
    private(set) var synthesizedCount: Int = 0
    private(set) var processedCount: Int = 0

    var gpuPrefetchHitRate: Double {
        let total = gpuPrefetchHits + gpuPrefetchMisses
        guard total > 0 else { return 1 }
        return Double(gpuPrefetchHits) / Double(total)
    }

    // MARK: - Caches

    private var silhouettes: [UUID: NSImage] = [:]
    private var photoOrder: [UUID] = []
    private var indexByID: [UUID: Int] = [:]
    /// Browse preview JPEG — never rawPath.
    private var previewPathByID: [UUID: String] = [:]
    /// Ingest grid thumb for silhouette tier.
    private var silhouettePathByID: [UUID: String] = [:]
    private var inflightSilhouette = Set<UUID>()
    private var inflightGPU = Set<UUID>()
    private(set) var generation = 0
    private var recentAdvanceTimes: [CFAbsoluteTime] = []
    private var pendingPhotonInputTime: CFAbsoluteTime?

    private let silhouetteMaxPx = 160
    private let aheadDefault = 12
    private let behindDefault = 4
    private let aheadHeld = 20
    private let aheadRip = 28

    private let decodeQueue = DispatchQueue(
        label: "lumina.preview-spine.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let log = Logger(subsystem: "com.lumina.app", category: "PreviewSpine")

    private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    init() {
        NotificationCenter.default.addObserver(
            forName: .luminaTextureReady,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let id = note.userInfo?["photoID"] as? UUID else { return }
            Task { @MainActor in
                self.textureBecameReady(id: id)
            }
        }
    }

    // MARK: - Warm

    func warm(photos: [PhotoRecord], focus: UUID? = nil) {
        let newOrder = photos.map(\.id)
        let newPreviewPaths: [UUID: String] = Dictionary(uniqueKeysWithValues: photos.compactMap { photo -> (UUID, String)? in
            guard let path = photo.thumbPath ?? photo.gridThumbPath,
                  Self.isBrowseSafePath(path) else { return nil }
            return (photo.id, path)
        })
        let newSilhouettePaths: [UUID: String] = Dictionary(uniqueKeysWithValues: photos.compactMap { photo -> (UUID, String)? in
            guard let path = photo.gridThumbPath ?? photo.thumbPath,
                  Self.isBrowseSafePath(path) else { return nil }
            return (photo.id, path)
        })

        // Same order but paths arrived late (common while "Grouping similar…" still runs).
        if newOrder == photoOrder, !photoOrder.isEmpty {
            let pathsChanged = newPreviewPaths != previewPathByID || newSilhouettePaths != silhouettePathByID
            if pathsChanged {
                previewPathByID = newPreviewPaths
                silhouettePathByID = newSilhouettePaths
                let gen = generation
                for id in photoOrder where silhouettes[id] == nil {
                    enqueueSilhouette(id: id, generation: gen)
                }
                if let focus, let path = previewPathByID[focus], MetalPreviewPool.shared.texture(for: focus) == nil {
                    enqueueGPU(id: focus, path: path, generation: gen, distanceBias: 0)
                }
            }
            if let focus {
                paint(id: focus, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            }
            return
        }

        generation &+= 1
        let gen = generation
        photoOrder = newOrder
        indexByID = Dictionary(uniqueKeysWithValues: photoOrder.enumerated().map { ($0.element, $0.offset) })
        previewPathByID = newPreviewPaths
        silhouettePathByID = newSilhouettePaths

        embeddedCount = photos.filter { $0.previewOrigin == .embedded }.count
        synthesizedCount = photos.filter { $0.previewOrigin == .synthesized }.count
        processedCount = photos.filter { $0.previewOrigin == .processed }.count

        let alive = Set(photoOrder)
        silhouettes = silhouettes.filter { alive.contains($0.key) }
        silhouetteCount = silhouettes.count
        gpuTextureCount = photoOrder.filter { MetalPreviewPool.shared.texture(for: $0) != nil }.count

        for id in photoOrder where silhouettes[id] == nil {
            enqueueSilhouette(id: id, generation: gen)
        }

        let focusID = focus ?? photoOrder.first
        if let focusID {
            paint(id: focusID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
        }
    }

    func clear() {
        generation &+= 1
        silhouettes.removeAll()
        photoOrder.removeAll()
        indexByID.removeAll()
        previewPathByID.removeAll()
        silhouettePathByID.removeAll()
        inflightSilhouette.removeAll()
        inflightGPU.removeAll()
        paintedPhotoID = nil
        paintedSilhouette = nil
        paintedJPEGPath = nil
        paintedTier = .empty
        silhouetteCount = 0
        gpuTextureCount = 0
        decodeQueueDepth = 0
        embeddedCount = 0
        synthesizedCount = 0
        processedCount = 0
        ripVelocity = 0
        lastPaintCommitMs = 0
        lastInputToPhotonMs = 0
        gpuPrefetchHits = 0
        gpuPrefetchMisses = 0
    }

    /// Instant silhouette for Meet/Pick grids — never blocks; returns nil until decode lands.
    func silhouetteImage(for id: UUID) -> NSImage? {
        silhouettes[id]
    }

    /// Browse-safe JPEG path already registered in the warm spine.
    func previewJPEGPath(for id: UUID) -> String? {
        previewPathByID[id]
    }

    /// Single fidelity gateway for session photo pixels. PhotoImageCache stays internal.
    func fidelityImage(for photo: PhotoRecord, maxPixelSize: Int = PhotoImageTier.gridMaxPixelSize) async -> NSImage? {
        let candidates = [
            previewPathByID[photo.id],
            photo.gridThumbPath,
            photo.thumbPath,
            photo.proxyPath,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        for path in candidates {
            if Task.isCancelled { return nil }
            let outcome = await PhotoImageCache.shared.load(
                path: path,
                maxPixelSize: maxPixelSize,
                allowRAW: false
            )
            if case .image(let image) = outcome { return image }
        }
        return nil
    }

    /// Called by Metal canvas when a drawable is presented — true input→photon.
    func recordPhotonPresent(inputTime: CFAbsoluteTime) {
        let ms = (CFAbsoluteTimeGetCurrent() - inputTime) * 1000
        lastInputToPhotonMs = ms
        LatencyMetrics.record("spine.input_to_photon", milliseconds: ms)
        pendingPhotonInputTime = nil
        if ms > LatencyMetrics.navigationSLAms {
            droppedFrames &+= 1
        }
    }

    func pendingPhotonTime(for photoID: UUID) -> CFAbsoluteTime? {
        guard paintedPhotoID == photoID else { return nil }
        return pendingPhotonInputTime
    }

    // MARK: - Paint (sync commit — GPU texture or silhouette fallback)

    @discardableResult
    func paint(id: UUID, inputTime: CFAbsoluteTime, held: Bool = false) -> Tier {
        if let prev = paintedPhotoID, let a = indexByID[prev], let b = indexByID[id], a != b {
            direction = b >= a ? 1 : -1
        }

        paintedPhotoID = id
        paintedJPEGPath = previewPathByID[id]
        pendingPhotonInputTime = inputTime

        if MetalPreviewPool.shared.texture(for: id) != nil {
            paintedTier = .preview
            paintedSilhouette = nil
            gpuPrefetchHits &+= 1
        } else if let sil = silhouettes[id] {
            paintedTier = .silhouette
            paintedSilhouette = sil
            gpuPrefetchMisses &+= 1
            if let path = previewPathByID[id] {
                enqueueGPU(id: id, path: path, generation: generation, distanceBias: 0)
            }
        } else {
            paintedTier = .empty
            paintedSilhouette = nil
            gpuPrefetchMisses &+= 1
            enqueueSilhouette(id: id, generation: generation)
            if let path = previewPathByID[id] {
                enqueueGPU(id: id, path: path, generation: generation, distanceBias: 0)
            }
        }

        trackVelocity(at: inputTime)

        let ms = (CFAbsoluteTimeGetCurrent() - inputTime) * 1000
        lastPaintCommitMs = ms
        LatencyMetrics.record("spine.paint_commit", milliseconds: ms)

        reaim(around: id, held: held, generation: generation)
        return paintedTier
    }

    @discardableResult
    func advance(
        in photos: [PhotoRecord],
        from current: UUID?,
        delta: Int,
        inputTime: CFAbsoluteTime,
        held: Bool = false
    ) -> UUID? {
        guard !photos.isEmpty else { return nil }
        if photos.map(\.id) != photoOrder {
            warm(photos: photos, focus: current)
        }

        let idx: Int
        if let current, let i = indexByID[current] {
            idx = i
        } else {
            idx = 0
        }
        let next = min(max(idx + delta, 0), photoOrder.count - 1)
        direction = delta >= 0 ? 1 : -1
        let id = photoOrder[next]
        paint(id: id, inputTime: inputTime, held: held)
        return id
    }

    private func textureBecameReady(id: UUID) {
        gpuTextureCount = photoOrder.filter { MetalPreviewPool.shared.texture(for: $0) != nil }.count
        guard paintedPhotoID == id else { return }
        paintedTier = .preview
        paintedSilhouette = nil
    }

    private func trackVelocity(at time: CFAbsoluteTime) {
        recentAdvanceTimes.append(time)
        recentAdvanceTimes.removeAll { time - $0 > 0.45 }
        if recentAdvanceTimes.count >= 2, let first = recentAdvanceTimes.first {
            let dt = max(time - first, 0.001)
            ripVelocity = Double(recentAdvanceTimes.count - 1) / dt
        } else {
            ripVelocity = 0
        }
    }

    // MARK: - Prefetch (GPU textures only)

    private func reaim(around id: UUID, held: Bool, generation gen: Int) {
        guard let center = indexByID[id] else { return }
        let ripping = held || ripVelocity >= 8
        let ahead = ripping ? aheadRip : (held ? aheadHeld : aheadDefault)
        let behind = behindDefault
        let lo: Int
        let hi: Int
        if direction >= 0 {
            lo = max(0, center - behind)
            hi = min(photoOrder.count - 1, center + ahead)
        } else {
            lo = max(0, center - ahead)
            hi = min(photoOrder.count - 1, center + behind)
        }

        var order: [UUID] = [photoOrder[center]]
        if direction >= 0 {
            if center + 1 <= hi { order.append(contentsOf: photoOrder[(center + 1)...hi]) }
            if lo < center { order.append(contentsOf: photoOrder[lo..<center].reversed()) }
        } else {
            if lo < center { order.append(contentsOf: photoOrder[lo..<center].reversed()) }
            if center + 1 <= hi { order.append(contentsOf: photoOrder[(center + 1)...hi]) }
        }

        for (offset, pid) in order.enumerated() where MetalPreviewPool.shared.texture(for: pid) == nil {
            guard let path = previewPathByID[pid] else { continue }
            enqueueGPU(id: pid, path: path, generation: gen, distanceBias: offset)
        }
        MetalPreviewPool.shared.evictFar(from: center, order: photoOrder, keepRadius: ahead + behind + 2)
    }

    private func enqueueSilhouette(id: UUID, generation gen: Int) {
        guard let path = silhouettePathByID[id],
              silhouettes[id] == nil,
              !inflightSilhouette.contains(id) else { return }
        inflightSilhouette.insert(id)
        decodeQueueDepth = inflightSilhouette.count + inflightGPU.count

        decodeQueue.async { [weak self] in
            let image = Self.decodeSilhouette(path: path, maxPixelSize: self?.silhouetteMaxPx ?? 160)
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.inflightSilhouette.remove(id)
                self.decodeQueueDepth = self.inflightSilhouette.count + self.inflightGPU.count
                guard let image else { return }
                self.silhouettes[id] = image
                self.silhouetteCount = self.silhouettes.count
                if self.paintedPhotoID == id, self.paintedTier != .preview {
                    self.paintedSilhouette = image
                    self.paintedTier = .silhouette
                }
            }
        }
    }

    private func enqueueGPU(id: UUID, path: String, generation gen: Int, distanceBias: Int) {
        guard MetalPreviewPool.shared.texture(for: id) == nil,
              !inflightGPU.contains(id),
              Self.isBrowseSafePath(path) else { return }
        inflightGPU.insert(id)
        decodeQueueDepth = inflightSilhouette.count + inflightGPU.count
        let bias = distanceBias

        decodeQueue.async { [weak self] in
            _ = MetalPreviewPool.shared.upload(id: id, jpegPath: path, distanceBias: bias, generation: UInt64(gen))
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.inflightGPU.remove(id)
                self.decodeQueueDepth = self.inflightSilhouette.count + self.inflightGPU.count
                self.gpuTextureCount = self.photoOrder.filter { MetalPreviewPool.shared.texture(for: $0) != nil }.count
            }
        }
    }

    /// Grid/small JPEG only — never preview JPEG, never RAW.
    nonisolated private static func decodeSilhouette(path: String, maxPixelSize: Int) -> NSImage? {
        assertBrowseSafe(path)
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let scale: CGFloat = 2
        return NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        )
    }

    nonisolated private static func isBrowseSafePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.uppercased()
        return !rawExtensions.contains(ext)
    }

    nonisolated private static func assertBrowseSafe(_ path: String) {
        #if DEBUG
        precondition(isBrowseSafePath(path), "Interactive decode must never use RAW path: \(path)")
        #endif
    }

    func hudLines() -> [String] {
        let commitP50 = LatencyMetrics.percentile("spine.paint_commit", 0.50).map { String(format: "%.1f", $0) } ?? "—"
        let commitP95 = LatencyMetrics.percentile("spine.paint_commit", 0.95).map { String(format: "%.1f", $0) } ?? "—"
        let photonP50 = LatencyMetrics.percentile("spine.input_to_photon", 0.50).map { String(format: "%.1f", $0) } ?? "—"
        let photonP95 = LatencyMetrics.percentile("spine.input_to_photon", 0.95).map { String(format: "%.1f", $0) } ?? "—"
        let t = MetalPreviewPool.shared.lastTimings
        let decP50 = MetalPreviewPool.shared.p50Decode().map { String(format: "%.1f", $0) } ?? "—"
        let blitP50 = MetalPreviewPool.shared.p50Blit().map { String(format: "%.2f", $0) } ?? "—"
        let wrapP50 = MetalPreviewPool.shared.p50Wrap().map { String(format: "%.2f", $0) } ?? "—"
        let totalOrigin = max(embeddedCount + synthesizedCount + processedCount, 1)
        return [
            String(format: "paint_commit: %.1fms (p50 %@ · p95 %@)", lastPaintCommitMs, commitP50, commitP95),
            String(format: "in→photon: %.1fms (p50 %@ · p95 %@ · at present)", lastInputToPhotonMs, photonP50, photonP95),
            String(format: "GPU prefetch: %.0f%%  queue: %d  rip: %.0f/s", gpuPrefetchHitRate * 100, decodeQueueDepth, ripVelocity),
            "drops: \(droppedFrames)  tier: \(paintedTier.rawValue)  dir: \(direction > 0 ? "→" : "←")",
            String(format: "decode %.1fms · blit %.2fms · wrap %.2fms (p50 %@ · %@ · %@)",
                   t.decodeMs, t.blitMs, t.wrapMs, decP50, blitP50, wrapP50),
            "preview: emb \(embeddedCount) · synth \(synthesizedCount) · jpg \(processedCount)  (\(Int(100 * embeddedCount / totalOrigin))% emb)",
            "GPU tex \(gpuTextureCount) · sil \(silhouetteCount)",
        ]
    }
}
