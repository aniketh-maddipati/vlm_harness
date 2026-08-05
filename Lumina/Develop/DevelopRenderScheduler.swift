import AppKit
import CoreImage
import Foundation
import os

/// Stage-aware bounded cache of final presentation surfaces.
///
/// This cache holds only post-look, geometry-applied results. The RAW-stage
/// linear surfaces live inside each `PreparedRawSession`; prepared sessions
/// and metadata live in `PreparedRawSessionRegistry`.
actor DevelopPresentationCache {
    struct Entry {
        let key: String
        let ciImage: CIImage
        let cgImage: CGImage?
        let fidelity: DevelopFidelityState
        let byteEstimate: Int
        var lastAccess: CFAbsoluteTime
        let speculative: Bool
    }

    private var entries: [String: Entry] = [:]
    private var totalBytes = 0
    private let budgetBytes: Int

    init(budgetMegabytes: Int = 512) {
        self.budgetBytes = max(budgetMegabytes, 64) * 1_024 * 1_024
    }

    func get(_ key: String) -> Entry? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = CFAbsoluteTimeGetCurrent()
        entries[key] = entry
        return entry
    }

    func put(key: String, ciImage: CIImage, cgImage: CGImage?, fidelity: DevelopFidelityState, speculative: Bool = false) {
        // RGBAh estimate: 8 bytes/pixel for the lazy CI recipe's realized size,
        // plus the bitmap when present.
        let extent = ciImage.extent
        var bytes = Int(extent.width * extent.height) * 8
        if let cg = cgImage { bytes += cg.bytesPerRow * cg.height }
        if let old = entries[key] { totalBytes -= old.byteEstimate }
        entries[key] = Entry(
            key: key,
            ciImage: ciImage,
            cgImage: cgImage,
            fidelity: fidelity,
            byteEstimate: bytes,
            lastAccess: CFAbsoluteTimeGetCurrent(),
            speculative: speculative
        )
        totalBytes += bytes
        evictIfNeeded()
    }

    func invalidate(photoID: UUID) {
        let prefix = photoID.uuidString
        for key in entries.keys where key.hasPrefix(prefix) {
            if let old = entries.removeValue(forKey: key) {
                totalBytes -= old.byteEstimate
            }
        }
    }

    func invalidateAll() {
        entries.removeAll()
        totalBytes = 0
    }

    /// Memory pressure: speculative/prefetch entries go first, then everything
    /// except the given photo's most recent surfaces.
    func trimForMemoryPressure(keeping keepID: UUID?) {
        for (key, entry) in entries where entry.speculative {
            entries.removeValue(forKey: key)
            totalBytes -= entry.byteEstimate
        }
        guard let keepID else { return }
        let keepPrefix = keepID.uuidString
        for (key, entry) in entries where !key.hasPrefix(keepPrefix) {
            entries.removeValue(forKey: key)
            totalBytes -= entry.byteEstimate
        }
    }

    private func evictIfNeeded() {
        while totalBytes > budgetBytes,
              let oldest = entries.values.min(by: { $0.lastAccess < $1.lastAccess }) {
            if let old = entries.removeValue(forKey: oldest.key) {
                totalBytes -= old.byteEstimate
            }
        }
    }
}

/// Async counting semaphore for global render concurrency.
actor RenderGate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = limit }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            available += 1
        }
    }
}

/// Debug instrumentation for develop responsiveness.
struct DevelopRenderMetrics {
    var cacheHits = 0
    var cacheMisses = 0
    var rawStageHits = 0
    var cancelled = 0
    var staleRejected = 0
    var completed = 0
    var lastDurationMs: Double = 0
    var lastQuality: DevelopRenderQuality = .interactive
    var lastFidelity: DevelopFidelityState = .interactive

    mutating func record(result: DevelopRenderResult, stale: Bool) {
        if stale {
            staleRejected += 1
            return
        }
        if result.cancelled {
            cancelled += 1
            return
        }
        if result.cacheHit { cacheHits += 1 } else { cacheMisses += 1 }
        if result.rawStageCacheHit { rawStageHits += 1 }
        completed += 1
        lastDurationMs = result.durationMs
        lastQuality = result.quality
        lastFidelity = result.fidelity
    }

    var summaryLine: String {
        String(
            format: "dev cache hit=%d miss=%d rawHit=%d cancel=%d stale=%d last=%.1fms %@/%@",
            cacheHits, cacheMisses, rawStageHits, cancelled, staleRejected,
            lastDurationMs, lastQuality.rawValue, lastFidelity.rawValue
        )
    }
}

/// Latest-wins render coordinator.
///
/// - At most one authoritative (settled/1:1) render active per photo.
/// - At most `interactiveLimit` interactive/settled renders globally (tunable).
/// - Export is serialized on its own lane and never starves the visible photo.
/// - New requests supersede older generation IDs; superseded results may finish
///   inside Core Image but never publish or enter a cache.
@MainActor
@Observable
final class DevelopRenderScheduler {
    private(set) var metrics = DevelopRenderMetrics()
    private(set) var presented: [UUID: DevelopRenderResult] = [:]
    private(set) var fidelityByPhoto: [UUID: DevelopFidelityState] = [:]

    /// Tunable global limit for interactive + settled renders.
    static var interactiveLimit = 2

    private let gate = RenderGenerationGate()
    private let cache = DevelopPresentationCache()
    private let renderGate = RenderGate(limit: DevelopRenderScheduler.interactiveLimit)
    private var inflight: [UUID: Task<Void, Never>] = [:]
    private var settleTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingRecipe: [UUID: EditRecipe] = [:]
    private var exportQueue: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var visiblePhotoID: UUID?

    private static let signposter = OSSignposter(subsystem: "app.lumina.develop", category: "render")

    /// Before/After cached surfaces — switch without re-render.
    private var beforeSurface: [UUID: CIImage] = [:]
    private var afterSurface: [UUID: CIImage] = [:]
    private var beforeBitmap: [UUID: CGImage] = [:]

    init() {
        installMemoryPressureHandler()
    }

    func cancelAll() {
        for (_, task) in inflight { task.cancel() }
        for (_, task) in settleTasks { task.cancel() }
        inflight.removeAll()
        settleTasks.removeAll()
        Task { await gate.invalidateAll() }
    }

    // MARK: - Interactive scrub

    /// High-frequency slider path — coalesce + interactive quality only.
    /// Key auto-repeat / UI event bursts collapse into the latest recipe.
    func scrub(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe
    ) {
        visiblePhotoID = photoID
        pendingRecipe[photoID] = recipe
        fidelityByPhoto[photoID] = .interactive
        inflight[photoID]?.cancel()
        settleTasks[photoID]?.cancel()

        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let latest = self.pendingRecipe[photoID] else { return }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: latest,
                quality: .interactive
            )
            guard !Task.isCancelled else { return }
            self.scheduleSettled(photoID: photoID, rawURL: rawURL, proxyURL: proxyURL, recipe: latest)
        }
        inflight[photoID] = task
    }

    /// Authoritative settled render after input pauses. One per photo.
    private func scheduleSettled(photoID: UUID, rawURL: URL, proxyURL: URL?, recipe: EditRecipe) {
        settleTasks[photoID]?.cancel()
        fidelityByPhoto[photoID] = .settling
        settleTasks[photoID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: recipe,
                quality: .settled
            )
        }
    }

    func renderOneToOne(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        region: DevelopRenderRegion
    ) async {
        fidelityByPhoto[photoID] = .oneToOneRAW
        await renderNow(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .oneToOne,
            region: region
        )
    }

    // MARK: - Prewarm / Before-After

    func warmBeforeAfter(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe
    ) async {
        let gen = await gate.next(for: photoID)
        let beforeReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: .neutral,
            quality: .settled,
            source: .originalRAW
        )
        let afterReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .settled,
            source: .originalRAW
        )
        let before = await DevelopRenderGraph.render(beforeReq)
        let after = await DevelopRenderGraph.render(afterReq)
        if let img = before.ciImage {
            beforeSurface[photoID] = img
            beforeBitmap[photoID] = before.cgImage
        }
        if let img = after.ciImage { afterSurface[photoID] = img }
    }

    /// Prewarm sessions + settled surfaces for the leader and visible references.
    func prewarm(photos: [(id: UUID, rawURL: URL)], recipe: EditRecipe) {
        for (index, photo) in photos.prefix(3).enumerated() {
            Task(priority: index == 0 ? .userInitiated : .utility) { [weak self] in
                guard let self else { return }
                await self.renderNow(
                    photoID: photo.id,
                    rawURL: photo.rawURL,
                    proxyURL: nil,
                    recipe: recipe,
                    quality: .settled,
                    speculative: index > 0
                )
            }
        }
    }

    /// Instant Before/After using cached surfaces.
    func beforeImage(for photoID: UUID) -> CIImage? { beforeSurface[photoID] }
    func beforeBitmap(for photoID: UUID) -> CGImage? { beforeBitmap[photoID] }
    func afterImage(for photoID: UUID) -> CIImage? { afterSurface[photoID] ?? presented[photoID]?.ciImage }

    func presentedCIImage(for photoID: UUID) -> CIImage? { presented[photoID]?.ciImage }
    func presentedImage(for photoID: UUID) -> CGImage? { presented[photoID]?.cgImage }

    // MARK: - Export lane

    /// Serialized, independent of interactive work.
    func enqueueExport(_ work: @escaping @Sendable () async -> Void) {
        let previous = exportQueue
        exportQueue = Task(priority: .utility) {
            await previous?.value
            await work()
        }
    }

    // MARK: - Core render

    private func renderNow(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        quality: DevelopRenderQuality,
        region: DevelopRenderRegion = .full,
        speculative: Bool = false
    ) async {
        let signpostID = Self.signposter.makeSignpostID()
        let requestState = Self.signposter.beginInterval("request", id: signpostID)
        defer { Self.signposter.endInterval("request", requestState) }

        let queuedAt = CFAbsoluteTimeGetCurrent()
        let generation = await gate.next(for: photoID)
        let request = RawRenderRequest(
            generation: generation,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: quality,
            region: region
        )

        let key = request.cacheKey
        if let cached = await cache.get(key) {
            Self.signposter.emitEvent("cacheHit", id: signpostID)
            let result = DevelopRenderResult(
                requestID: request.id,
                generation: generation,
                photoID: photoID,
                quality: quality,
                fidelity: cached.fidelity,
                ciImage: cached.ciImage,
                cgImage: cached.cgImage,
                extent: cached.ciImage.extent,
                durationMs: 0,
                cacheHit: true,
                rawStageCacheHit: true,
                cancelled: false,
                usedProxyFallback: cached.fidelity == .proxyFallback,
                colorSpaceName: "cached"
            )
            present(result)
            return
        }
        Self.signposter.emitEvent("cacheMiss", id: signpostID)

        await renderGate.acquire()
        let queueDelayMs = (CFAbsoluteTimeGetCurrent() - queuedAt) * 1000
        Self.signposter.emitEvent("queueDelay", id: signpostID, "\(queueDelayMs, format: .fixed(precision: 1))ms")

        // Superseded before starting? Skip the evaluation entirely.
        if await !gate.isCurrent(generation, for: photoID) {
            await renderGate.release()
            Self.signposter.emitEvent("staleDiscardPreRender", id: signpostID)
            return
        }

        let evalState = Self.signposter.beginInterval("evaluate", id: signpostID)
        let rendered = await DevelopRenderGraph.render(request)
        Self.signposter.endInterval("evaluate", evalState)
        await renderGate.release()

        if Task.isCancelled {
            let flag = DevelopRenderResult(
                requestID: rendered.requestID,
                generation: rendered.generation,
                photoID: rendered.photoID,
                quality: rendered.quality,
                fidelity: rendered.fidelity,
                ciImage: nil,
                cgImage: nil,
                extent: .zero,
                durationMs: rendered.durationMs,
                cacheHit: false,
                rawStageCacheHit: rendered.rawStageCacheHit,
                cancelled: true,
                usedProxyFallback: rendered.usedProxyFallback,
                colorSpaceName: rendered.colorSpaceName
            )
            metrics.record(result: flag, stale: false)
            return
        }

        // Superseded results must never publish or enter a cache.
        let current = await gate.isCurrent(generation, for: photoID)
        guard current else {
            Self.signposter.emitEvent("staleDiscard", id: signpostID)
            metrics.record(result: rendered, stale: true)
            return
        }

        if let image = rendered.ciImage {
            await cache.put(
                key: key,
                ciImage: image,
                cgImage: rendered.cgImage,
                fidelity: rendered.fidelity,
                speculative: speculative
            )
            if quality == .settled {
                afterSurface[photoID] = image
                Self.signposter.emitEvent("settlement", id: signpostID)
            }
        }
        present(rendered)
        Self.signposter.emitEvent("presented", id: signpostID)
    }

    private func present(_ result: DevelopRenderResult) {
        let previousGen = presented[result.photoID]?.generation
        guard RenderGenerationOrdering.shouldPresent(candidate: result.generation, presented: previousGen) else {
            metrics.record(result: result, stale: true)
            return
        }
        presented[result.photoID] = result
        fidelityByPhoto[result.photoID] = result.fidelity
        metrics.record(result: result, stale: false)
    }

    // MARK: - Memory pressure

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let critical = source.data.contains(.critical)
            Task { await self.respondToMemoryPressure(critical: critical) }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func respondToMemoryPressure(critical: Bool) async {
        let keep = visiblePhotoID
        // 1. Speculative prefetch, then presentation surfaces of other photos.
        await cache.trimForMemoryPressure(keeping: critical ? keep : nil)
        // 2. Post-look Before/After surfaces for non-visible photos.
        if critical {
            beforeSurface = beforeSurface.filter { $0.key == keep }
            afterSurface = afterSurface.filter { $0.key == keep }
            beforeBitmap = beforeBitmap.filter { $0.key == keep }
            // 3. RAW sessions except the visible one.
            await PreparedRawSessionRegistry.shared.trimForMemoryPressure(keeping: keep)
            // 4. Core Image resource reclamation outside active presentation.
            DevelopRenderGraph.sharedContext.clearCaches()
        }
    }
}
