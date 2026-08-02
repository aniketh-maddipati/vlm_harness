import AppKit
import Foundation
import ImageIO
import Observation
import os

/// Speed Contract browsing spine — embedded JPEG only, never RAW demosaic on the interactive path.
/// Paint is sync from warm memory; decode/IO live off the main thread.
@MainActor
@Observable
final class PreviewSpine {
    static let shared = PreviewSpine()

    enum Tier: String, Sendable {
        case empty
        case silhouette
        case preview
    }

    // MARK: - Painted frame

    private(set) var paintedPhotoID: UUID?
    private(set) var paintedImage: NSImage?
    private(set) var paintedTier: Tier = .empty

    // MARK: - Contract instrumentation

    private(set) var lastInputToPhotonMs: Double = 0
    private(set) var lastGPUUploadMs: Double = 0
    private(set) var prefetchHits: Int = 0
    private(set) var prefetchMisses: Int = 0
    private(set) var droppedFrames: Int = 0
    private(set) var decodeQueueDepth: Int = 0
    private(set) var silhouetteCount: Int = 0
    private(set) var previewCount: Int = 0
    private(set) var direction: Int = 1
    private(set) var ripVelocity: Double = 0
    private(set) var embeddedCount: Int = 0
    private(set) var synthesizedCount: Int = 0
    private(set) var processedCount: Int = 0

    /// JPEG path currently painted (for Metal canvas).
    private(set) var paintedJPEGPath: String?

    var prefetchHitRate: Double {
        let total = prefetchHits + prefetchMisses
        guard total > 0 else { return 1 }
        return Double(prefetchHits) / Double(total)
    }

    var silhouetteMB: Double { Double(silhouetteApproxBytes) / 1_048_576 }
    var previewMB: Double { Double(previewApproxBytes) / 1_048_576 }

    // MARK: - Caches

    private var silhouettes: [UUID: NSImage] = [:]
    private var previews: [UUID: NSImage] = [:]
    private var photoOrder: [UUID] = []
    private var indexByID: [UUID: Int] = [:]
    private var sourcePathByID: [UUID: String] = [:]
    private var originByID: [UUID: PreviewOrigin] = [:]
    private var inflightSilhouette = Set<UUID>()
    private var inflightPreview = Set<UUID>()
    private var silhouetteApproxBytes = 0
    private var previewApproxBytes = 0
    private var generation = 0
    private var recentAdvanceTimes: [CFAbsoluteTime] = []

    private let silhouetteMaxPx = 160
    private let previewMaxPx = 2400
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

    // MARK: - Warm

    func warm(photos: [PhotoRecord], focus: UUID? = nil) {
        let newOrder = photos.map(\.id)
        if newOrder == photoOrder, !photoOrder.isEmpty {
            if let focus {
                paint(id: focus, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            }
            return
        }
        generation &+= 1
        let gen = generation
        photoOrder = newOrder
        indexByID = Dictionary(uniqueKeysWithValues: photoOrder.enumerated().map { ($0.element, $0.offset) })
        sourcePathByID = Dictionary(uniqueKeysWithValues: photos.map { photo in
            (photo.id, photo.thumbPath ?? photo.gridThumbPath ?? photo.rawPath)
        })
        originByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.previewOrigin) })
        embeddedCount = photos.filter { $0.previewOrigin == .embedded }.count
        synthesizedCount = photos.filter { $0.previewOrigin == .synthesized }.count
        processedCount = photos.filter { $0.previewOrigin == .processed }.count

        let alive = Set(photoOrder)
        silhouettes = silhouettes.filter { alive.contains($0.key) }
        previews = previews.filter { alive.contains($0.key) }
        silhouetteCount = silhouettes.count
        previewCount = previews.count

        for id in photoOrder where silhouettes[id] == nil {
            enqueueDecode(id: id, tier: .silhouette, generation: gen)
        }

        let focusID = focus ?? photoOrder.first
        if let focusID {
            paint(id: focusID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
        }
    }

    func clear() {
        generation &+= 1
        silhouettes.removeAll()
        previews.removeAll()
        photoOrder.removeAll()
        indexByID.removeAll()
        sourcePathByID.removeAll()
        inflightSilhouette.removeAll()
        inflightPreview.removeAll()
        paintedPhotoID = nil
        paintedImage = nil
        paintedJPEGPath = nil
        paintedTier = .empty
        silhouetteApproxBytes = 0
        previewApproxBytes = 0
        silhouetteCount = 0
        previewCount = 0
        decodeQueueDepth = 0
        embeddedCount = 0
        synthesizedCount = 0
        processedCount = 0
        ripVelocity = 0
        lastGPUUploadMs = 0
    }

    // MARK: - Paint (sync — 50ms contract)

    @discardableResult
    func paint(id: UUID, inputTime: CFAbsoluteTime, held: Bool = false) -> Tier {
        if let prev = paintedPhotoID, let a = indexByID[prev], let b = indexByID[id], a != b {
            direction = b >= a ? 1 : -1
        }

        paintedPhotoID = id
        paintedJPEGPath = sourcePathByID[id]

        if let preview = previews[id] {
            paintedImage = preview
            paintedTier = .preview
            prefetchHits &+= 1
            if MetalPreviewPool.shared.texture(for: id) != nil {
                lastGPUUploadMs = 0
            } else {
                // Never block paint on GPU fill — prefetch/canvas will catch up.
                lastGPUUploadMs = -1
                enqueueDecode(id: id, tier: .preview, generation: generation)
            }
        } else if let sil = silhouettes[id] {
            paintedImage = sil
            paintedTier = .silhouette
            prefetchMisses &+= 1
            enqueueDecode(id: id, tier: .preview, generation: generation)
        } else {
            paintedImage = nil
            paintedTier = .empty
            prefetchMisses &+= 1
            enqueueDecode(id: id, tier: .silhouette, generation: generation)
            enqueueDecode(id: id, tier: .preview, generation: generation)
        }

        trackVelocity(at: inputTime)

        let ms = (CFAbsoluteTimeGetCurrent() - inputTime) * 1000
        lastInputToPhotonMs = ms
        LatencyMetrics.record("spine.input_to_photon", milliseconds: ms)
        if ms > LatencyMetrics.navigationSLAms {
            droppedFrames &+= 1
            log.warning("input-to-photon \(ms, format: .fixed(precision: 1))ms SLA breach")
        }

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

    // MARK: - Prefetch

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

        for (offset, pid) in order.enumerated() where previews[pid] == nil || MetalPreviewPool.shared.texture(for: pid) == nil {
            enqueueDecode(id: pid, tier: .preview, generation: gen, distanceBias: offset)
        }
        MetalPreviewPool.shared.evictFar(from: center, order: photoOrder, keepRadius: ahead + behind + 2)
    }

    private func enqueueDecode(id: UUID, tier: Tier, generation gen: Int, distanceBias: Int = 0) {
        guard let path = sourcePathByID[id] else { return }
        let maxPx: Int
        switch tier {
        case .silhouette:
            guard silhouettes[id] == nil, !inflightSilhouette.contains(id) else { return }
            inflightSilhouette.insert(id)
            maxPx = silhouetteMaxPx
        case .preview:
            let needsCPU = previews[id] == nil
            let needsGPU = MetalPreviewPool.shared.texture(for: id) == nil
            guard (needsCPU || needsGPU), !inflightPreview.contains(id) else { return }
            inflightPreview.insert(id)
            maxPx = previewMaxPx
        case .empty:
            return
        }
        decodeQueueDepth = inflightSilhouette.count + inflightPreview.count
        let bias = distanceBias

        decodeQueue.async { [weak self] in
            let image = Self.decodeEmbedded(path: path, maxPixelSize: maxPx)
            let uploadMs: Double = {
                guard tier == .preview else { return 0 }
                return MetalPreviewPool.shared.upload(id: id, jpegPath: path, distanceBias: bias)
            }()
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                switch tier {
                case .silhouette: self.inflightSilhouette.remove(id)
                case .preview: self.inflightPreview.remove(id)
                case .empty: break
                }
                self.decodeQueueDepth = self.inflightSilhouette.count + self.inflightPreview.count
                if tier == .preview {
                    self.lastGPUUploadMs = max(0, uploadMs)
                }
                guard let image else { return }

                let bytes = Int(image.size.width * image.size.height * 4)
                if tier == .silhouette {
                    if self.silhouettes[id] == nil { self.silhouetteApproxBytes += bytes }
                    self.silhouettes[id] = image
                    self.silhouetteCount = self.silhouettes.count
                    if self.paintedPhotoID == id, self.paintedTier != .preview {
                        self.paintedImage = image
                        self.paintedTier = .silhouette
                    }
                } else {
                    if self.previews[id] == nil { self.previewApproxBytes += bytes }
                    self.previews[id] = image
                    self.previewCount = self.previews.count
                    if self.paintedPhotoID == id {
                        self.paintedImage = image
                        self.paintedTier = .preview
                        self.paintedJPEGPath = path
                    }
                }
            }
        }
    }

    nonisolated private static func decodeEmbedded(path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        // Tier 3: prefer mmap so a miss is map-and-decode, not a full file copy.
        let source: CGImageSource? = {
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                return CGImageSourceCreateWithData(data as CFData, nil)
            }
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }()
        guard let source else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        let scale: CGFloat = 2
        return NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        )
    }

    func hudLines() -> [String] {
        let p50 = LatencyMetrics.percentile("spine.input_to_photon", 0.50).map { String(format: "%.1f", $0) } ?? "—"
        let p95 = LatencyMetrics.percentile("spine.input_to_photon", 0.95).map { String(format: "%.1f", $0) } ?? "—"
        let p99 = LatencyMetrics.percentile("spine.input_to_photon", 0.99).map { String(format: "%.1f", $0) } ?? "—"
        let gpu = String(format: "%.2f", lastGPUUploadMs)
        let wrapP50 = MetalPreviewPool.shared.wrapP50.map { String(format: "%.2f", $0) } ?? "—"
        let totalOrigin = max(embeddedCount + synthesizedCount + processedCount, 1)
        return [
            String(format: "in→photon: %.1fms  (p50 %@ · p95 %@ · p99 %@)", lastInputToPhotonMs, p50, p95, p99),
            String(format: "prefetch hit: %.0f%%  queue: %d  rip: %.0f/s", prefetchHitRate * 100, decodeQueueDepth, ripVelocity),
            "drops: \(droppedFrames)  tier: \(paintedTier.rawValue)  dir: \(direction > 0 ? "→" : "←")",
            "GPU wrap: \(gpu)ms (p50 \(wrapP50) · target ~0 · IOSurface→MTL)",
            "preview: emb \(embeddedCount) · synth \(synthesizedCount) · jpg \(processedCount)  (\(Int(100 * embeddedCount / totalOrigin))% emb)",
            String(format: "mem sil %.1fMB (%d) · prev %.1fMB (%d)", silhouetteMB, silhouetteCount, previewMB, previewCount),
        ]
    }
}
