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

    init(budgetMegabytes: Int? = nil) {
        let resolved = budgetMegabytes ?? Self.defaultBudgetMegabytes()
        self.budgetBytes = max(resolved, 64) * 1_024 * 1_024
    }

    private static func defaultBudgetMegabytes() -> Int {
        let physical = ProcessInfo.processInfo.physicalMemory
        if physical <= 8 * 1_024 * 1_024 * 1_024 { return 256 }
        if physical <= 16 * 1_024 * 1_024 * 1_024 { return 384 }
        return 512
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
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var available: Int
    private var waiters: [Waiter] = []
    private var cancelledWaiterIDs: Set<UUID> = []

    init(limit: Int) { available = limit }

    /// Cancellation-aware acquire. Superseded slider requests are removed
    /// from the lane instead of forming a FIFO wall ahead of the latest frame.
    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if available > 0 {
            available -= 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || cancelledWaiterIDs.remove(id) != nil {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            available += 1
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else {
            cancelledWaiterIDs.insert(id)
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
/// - At most `interactiveLimit` visible + speculative renders globally.
/// - Export is serialized on its own lane and never starves the visible photo.
/// - New requests supersede older generation IDs; superseded results may finish
///   inside Core Image but never publish or enter a cache.
@MainActor
@Observable
final class DevelopRenderScheduler {
    private(set) var metrics = DevelopRenderMetrics()
    private(set) var presented: [UUID: DevelopRenderResult] = [:]
    private(set) var fidelityByPhoto: [UUID: DevelopFidelityState] = [:]

    /// One visible lane plus one speculative lane.
    static let interactiveLimit = 2

    private let gate = RenderGenerationGate()
    private let cache = DevelopPresentationCache()
    /// Visible work owns a reserved lane. Neighbor/background work can fill
    /// caches but cannot queue ahead of the photograph the user clicked.
    private let visibleRenderGate = RenderGate(limit: 1)
    private let speculativeRenderGate = RenderGate(limit: DevelopRenderScheduler.interactiveLimit - 1)
    private var inflight: [UUID: Task<Void, Never>] = [:]
    private var settleTasks: [UUID: Task<Void, Never>] = [:]
    private var speculativeTasks: [UUID: Task<Void, Never>] = [:]
    private var speculativeTaskTokens: [UUID: UUID] = [:]
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
        for (_, task) in speculativeTasks { task.cancel() }
        inflight.removeAll()
        settleTasks.removeAll()
        speculativeTasks.removeAll()
        speculativeTaskTokens.removeAll()
        Task { await gate.invalidateAll() }
    }

    /// Drop in-flight work for every photo except the one being viewed — stops
    /// arrow-key spam from stacking settled demosaics across the filmstrip.
    func cancelExcept(photoID: UUID) {
        for (id, task) in inflight where id != photoID {
            task.cancel()
            inflight[id] = nil
        }
        for (id, task) in settleTasks where id != photoID {
            task.cancel()
            settleTasks[id] = nil
        }
        for (id, task) in speculativeTasks where id != photoID {
            task.cancel()
            speculativeTasks[id] = nil
            speculativeTaskTokens[id] = nil
        }
        visiblePhotoID = photoID
    }

    // MARK: - Interactive scrub

    /// Open / navigate path — publish a fast interactive RAW, then promote the
    /// same asset in place to viewport-sized authoritative RAW.
    func openPhotograph(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        settledLongEdge: Int
    ) {
        cancelExcept(photoID: photoID)
        pendingRecipe[photoID] = recipe
        fidelityByPhoto[photoID] = .settling
        inflight[photoID]?.cancel()
        settleTasks[photoID]?.cancel()

        let task = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            guard let latest = self.pendingRecipe[photoID] else { return }
            let openedAt = CFAbsoluteTimeGetCurrent()
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: latest,
                quality: .interactive
            )
            guard !Task.isCancelled, self.visiblePhotoID == photoID else { return }
            LatencyMetrics.record(
                "p0.edit.open_interactive_ms",
                milliseconds: (CFAbsoluteTimeGetCurrent() - openedAt) * 1000
            )

            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled,
                  self.visiblePhotoID == photoID,
                  let current = self.pendingRecipe[photoID] else { return }
            let promotionStart = CFAbsoluteTimeGetCurrent()
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: current,
                quality: .settled,
                longEdgeCap: settledLongEdge
            )
            guard !Task.isCancelled, self.visiblePhotoID == photoID else { return }
            LatencyMetrics.record(
                "p0.edit.promote_settled_ms",
                milliseconds: (CFAbsoluteTimeGetCurrent() - promotionStart) * 1000
            )
        }
        inflight[photoID] = task
    }

    /// High-frequency slider path — coalesce + interactive quality only.
    /// Settled upgrade runs on gesture end via `settlePhotograph`, not mid-scrub.
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
            try? await Task.sleep(nanoseconds: 8_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let latest = self.pendingRecipe[photoID] else { return }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: latest,
                quality: .interactive
            )
        }
        inflight[photoID] = task
    }

    /// Authoritative settle after a scrub gesture ends (or open pause).
    func settlePhotograph(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        settledLongEdge: Int
    ) {
        pendingRecipe[photoID] = recipe
        scheduleSettled(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            longEdgeCap: settledLongEdge
        )
    }

    /// Authoritative settled render after input pauses. One per photo.
    private func scheduleSettled(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        longEdgeCap: Int
    ) {
        settleTasks[photoID]?.cancel()
        fidelityByPhoto[photoID] = .settling
        settleTasks[photoID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, let self else { return }
            let latest = self.pendingRecipe[photoID] ?? recipe
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: latest,
                quality: .settled,
                longEdgeCap: longEdgeCap
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
        let beforeReq = RawRenderRequest(
            generation: 0,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: .neutral,
            quality: .settled,
            source: .originalRAW
        )
        let afterReq = RawRenderRequest(
            generation: 0,
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

    /// Prewarm interactive RAW stages only. Speculative work may populate
    /// caches, but `renderNow` never publishes it to the focused surface.
    func prewarm(photos: [(id: UUID, rawURL: URL)], recipe: EditRecipe) {
        for (index, photo) in photos.prefix(3).enumerated() {
            speculativeTasks[photo.id]?.cancel()
            let token = UUID()
            speculativeTaskTokens[photo.id] = token
            speculativeTasks[photo.id] = Task(priority: index == 0 ? .userInitiated : .utility) { [weak self] in
                guard let self else { return }
                await self.renderNow(
                    photoID: photo.id,
                    rawURL: photo.rawURL,
                    proxyURL: nil,
                    recipe: recipe,
                    quality: .interactive,
                    speculative: true
                )
                if self.speculativeTaskTokens[photo.id] == token {
                    self.speculativeTasks[photo.id] = nil
                    self.speculativeTaskTokens[photo.id] = nil
                }
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
        longEdgeCap: Int? = nil,
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
            region: region,
            longEdgeCap: longEdgeCap
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
            if !speculative,
               !Task.isCancelled,
               visiblePhotoID == photoID,
               await gate.isCurrent(generation, for: photoID) {
                present(result)
            }
            return
        }
        Self.signposter.emitEvent("cacheMiss", id: signpostID)

        let lane = speculative ? speculativeRenderGate : visibleRenderGate
        guard await lane.acquire() else {
            Self.signposter.emitEvent("cancelledInQueue", id: signpostID)
            return
        }
        let queueDelayMs = (CFAbsoluteTimeGetCurrent() - queuedAt) * 1000
        Self.signposter.emitEvent("queueDelay", id: signpostID, "\(queueDelayMs, format: .fixed(precision: 1))ms")

        // Superseded before starting? Skip the evaluation entirely.
        if await !gate.isCurrent(generation, for: photoID) {
            await lane.release()
            Self.signposter.emitEvent("staleDiscardPreRender", id: signpostID)
            return
        }

        // Display-path interactive `durationMs` is graph construction only:
        // CIRAWFilter.outputImage is lazy, and GPU evaluation happens inside
        // DevelopMetalView.draw (`p0.edit.draw_ms`). Settled/export still
        // include evaluation because they materialize a CGImage.
        let evalState = Self.signposter.beginInterval("evaluate", id: signpostID)
        let rendered = await DevelopRenderGraph.render(request)
        Self.signposter.endInterval("evaluate", evalState)
        await lane.release()

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
        guard !speculative, visiblePhotoID == photoID else {
            Self.signposter.emitEvent("cachedSpeculative", id: signpostID)
            return
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
        LatencyMetrics.record(
            "p0.edit.quality_presented.\(result.quality.rawValue)",
            milliseconds: result.durationMs
        )
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
        await BrowsePixelService.shared.trimForMemoryPressure()
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
